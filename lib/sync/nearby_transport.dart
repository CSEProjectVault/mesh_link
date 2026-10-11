import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

/// Bytes-only transport over Google Nearby Connections.
///
/// Knows nothing about reports or CRDTs. It connects to nearby phones and
/// moves opaque byte blobs. A TCP/hotspot fallback (socket_transport.dart)
/// would expose the same surface: [start], [stop], [sendTo], [broadcast],
/// [onBytes], [onPeerConnected], [onPeerDisconnected], [peerCount].

const String kMeshServiceId = 'com.meshlink.app.sync';
const Strategy _strategy = Strategy.P2P_CLUSTER;

// Nearby BYTES payloads are limited to ~32 KB, so larger blobs are split
// into chunks with an 8-byte header: msgId(4) | index(2) | total(2).
const int _maxChunkData = 28000;
const int _headerLen = 8;

typedef BytesCallback = void Function(String endpointId, Uint8List bytes);
typedef PeerCallback = void Function(String endpointId);

class NearbyTransport {
  /// Number of currently connected peers (for the Home screen chip).
  final ValueNotifier<int> peerCount = ValueNotifier<int>(0);

  BytesCallback? onBytes;
  PeerCallback? onPeerConnected;
  PeerCallback? onPeerDisconnected;

  String _myName = '';
  bool _running = false;
  bool _advertising = false;
  bool _discovering = false;
  Timer? _watchdog;
  int _nextMsgId = Random().nextInt(1 << 20);

  final Set<String> _connected = {};
  final Set<String> _pending = {};
  final Map<String, String> _found = {}; // endpointId -> remote name
  final Map<String, _Reassembly> _incoming = {};

  Set<String> get peers => Set.unmodifiable(_connected);
  bool get isRunning => _running;

  void _log(String s) => debugPrint('[nearby] $s');

  // ---- Lifecycle ---------------------------------------------------------

  /// Starts advertising AND discovering, so every phone is both. Returns
  /// false if permissions were denied (safe to call again later).
  Future<bool> start(String deviceName) async {
    if (_running) return true;
    if (!await _ensurePermissions()) return false;

    // Unique suffix so two phones with the same team name never tie.
    _myName = '$deviceName#${Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0')}';
    _running = true;
    _log('starting as $_myName');

    await _startAdvertising();
    await _startDiscovery();
    _watchdog = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _watchdogTick(),
    );
    return true;
  }

  Future<void> stop() async {
    _running = false;
    _watchdog?.cancel();
    _watchdog = null;
    await _stopRadios();
    try {
      await Nearby().stopAllEndpoints();
    } catch (_) {}
    _connected.clear();
    _pending.clear();
    _incoming.clear();
    peerCount.value = 0;
  }

  // ---- Sending -----------------------------------------------------------

  Future<void> sendTo(String endpointId, Uint8List bytes) async {
    if (!_connected.contains(endpointId)) return;
    final total = max(1, (bytes.length / _maxChunkData).ceil());
    if (total > 0xFFFF) throw StateError('Payload too large: ${bytes.length}');
    final msgId = (_nextMsgId++) & 0x7FFFFFFF;

    for (var i = 0; i < total; i++) {
      final start = i * _maxChunkData;
      final end = min(start + _maxChunkData, bytes.length);
      final len = end - start;
      final buf = Uint8List(_headerLen + len);
      final bd = ByteData.sublistView(buf);
      bd.setUint32(0, msgId);
      bd.setUint16(4, i);
      bd.setUint16(6, total);
      buf.setRange(_headerLen, _headerLen + len, bytes, start);
      await Nearby().sendBytesPayload(endpointId, buf);
    }
  }

  Future<void> broadcast(Uint8List bytes) async {
    for (final id in _connected.toList()) {
      try {
        await sendTo(id, bytes);
      } catch (e) {
        _log('send to $id failed: $e');
      }
    }
  }

  // ---- Advertising / discovery ------------------------------------------

  Future<void> _startAdvertising() async {
    try {
      _advertising = await Nearby().startAdvertising(
        _myName,
        _strategy,
        onConnectionInitiated: _onInitiated,
        onConnectionResult: _onResult,
        onDisconnected: _onDisconnected,
        serviceId: kMeshServiceId,
      );
      _log('advertising: $_advertising');
    } catch (e) {
      _advertising = e.toString().contains('ALREADY');
      _log('advertise error: $e');
    }
  }

  Future<void> _startDiscovery() async {
    try {
      _discovering = await Nearby().startDiscovery(
        _myName,
        _strategy,
        onEndpointFound: _onEndpointFound,
        onEndpointLost: _onEndpointLost,
        serviceId: kMeshServiceId,
      );
      _log('discovering: $_discovering');
    } catch (e) {
      _discovering = e.toString().contains('ALREADY');
      _log('discovery error: $e');
    }
  }

  Future<void> _stopRadios() async {
    try {
      await Nearby().stopAdvertising();
    } catch (_) {}
    try {
      await Nearby().stopDiscovery();
    } catch (_) {}
    _advertising = false;
    _discovering = false;
    _found.clear();
  }

  /// Recovers after airplane mode, radios toggled, or a dropped link.
  Future<void> _watchdogTick() async {
    if (!_running) return;
    if (_connected.isEmpty) {
      if (_pending.isNotEmpty) return; // a connection is in progress
      await _stopRadios();
      await _startAdvertising();
      await _startDiscovery();
    } else {
      if (!_advertising) await _startAdvertising();
      if (!_discovering) await _startDiscovery();
    }
  }

  // ---- Connection callbacks ---------------------------------------------

  void _onEndpointFound(String id, String name, String serviceId) {
    _found[id] = name;
    if (_connected.contains(id) || _pending.contains(id)) return;

    // Only one side initiates, otherwise both request at once and collide.
    if (_myName.compareTo(name) < 0) {
      _request(id);
    } else {
      // The other side should initiate. Fall back if it never does.
      Future.delayed(const Duration(seconds: 8), () {
        if (_running &&
            _found.containsKey(id) &&
            !_connected.contains(id) &&
            !_pending.contains(id)) {
          _request(id);
        }
      });
    }
  }

  void _onEndpointLost(String? id) {
    if (id == null) return;
    _found.remove(id);
    _pending.remove(id);
  }

  Future<void> _request(String id) async {
    _pending.add(id);
    _log('requesting connection to $id');
    try {
      await Nearby().requestConnection(
        _myName,
        id,
        onConnectionInitiated: _onInitiated,
        onConnectionResult: _onResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      _pending.remove(id);
      _log('requestConnection failed: $e');
    }
  }

  void _onInitiated(String id, ConnectionInfo info) {
    _pending.add(id);
    _log('connection initiated with ${info.endpointName}, accepting');
    // NOTE: "Recieved" is misspelled in the plugin's own API.
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endpointId, payload) {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          _handleChunk(endpointId, payload.bytes!);
        }
      },
      onPayloadTransferUpdate: (endpointId, update) {},
    );
  }

  void _onResult(String id, Status status) {
    _pending.remove(id);
    _log('connection result $id: $status');
    if (status == Status.CONNECTED) {
      _connected.add(id);
      peerCount.value = _connected.length;
      onPeerConnected?.call(id);
    }
  }

  void _onDisconnected(String id) {
    _log('disconnected: $id');
    _connected.remove(id);
    _pending.remove(id);
    _incoming.removeWhere((key, _) => key.startsWith('$id:'));
    peerCount.value = _connected.length;
    onPeerDisconnected?.call(id);
    Future.delayed(const Duration(seconds: 3), _watchdogTick);
  }

  // ---- Reassembly --------------------------------------------------------

  void _handleChunk(String endpointId, Uint8List raw) {
    if (raw.length < _headerLen) return;
    final bd = ByteData.sublistView(raw);
    final msgId = bd.getUint32(0);
    final idx = bd.getUint16(4);
    final total = bd.getUint16(6);
    final data = Uint8List.fromList(Uint8List.sublistView(raw, _headerLen));

    if (total <= 1) {
      onBytes?.call(endpointId, data);
      return;
    }

    final key = '$endpointId:$msgId';
    final r = _incoming.putIfAbsent(key, () => _Reassembly(total));
    if (idx >= r.parts.length || r.parts[idx] != null) return;
    r.parts[idx] = data;
    r.received++;

    if (r.received == r.parts.length) {
      _incoming.remove(key);
      final builder = BytesBuilder(copy: false);
      for (final p in r.parts) {
        builder.add(p!);
      }
      onBytes?.call(endpointId, builder.takeBytes());
    }
  }

  // ---- Permissions -------------------------------------------------------

  Future<bool> _ensurePermissions() async {
    if (!Platform.isAndroid) return true;
    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;

    final perms = <Permission>[Permission.location];
    if (sdk >= 31) {
      perms.addAll([
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ]);
    }
    if (sdk >= 33) perms.add(Permission.nearbyWifiDevices);

    final results = await perms.request();
    final denied = results.entries.where((e) => !e.value.isGranted).toList();
    for (final d in denied) {
      _log('DENIED: ${d.key}');
    }
    if (!(await Permission.location.serviceStatus).isEnabled) {
      _log('WARNING: Location services are OFF; discovery may fail.');
    }
    return denied.isEmpty;
  }
}

class _Reassembly {
  final List<Uint8List?> parts;
  int received = 0;
  _Reassembly(int total) : parts = List<Uint8List?>.filled(total, null);
}
