import 'dart:async';
import 'dart:math';


import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';

/// Moves raw bytes between nearby phones using Google's Nearby Connections.
/// It knows nothing about reports or merging; SyncController connects it
/// to SyncService.
///
/// Both phones advertise AND discover, so nobody has to pick a role. To stop
/// both sides requesting a connection to each other at the same moment, only
/// the phone whose name sorts first sends the request.
///
/// NOTE: the plugin calls below follow the nearby_connections 4.x README.
/// If the analyzer complains about a name or signature, copy the form used in
/// the working spike (lib/sync/nearby_main.dart); the logic stays the same.
class NearbyTransport {
  NearbyTransport._();
  static final NearbyTransport instance = NearbyTransport._();

  static const String _serviceId = 'com.example.mesh_link.sync';
  static const Strategy _strategy = Strategy.P2P_CLUSTER;

  /// Endpoint ids of phones we are currently connected to.
  final ValueNotifier<Set<String>> connectedPeers =
      ValueNotifier<Set<String>>(<String>{});

  /// Called once a connection is fully established.
  void Function(String endpointId)? onPeerConnected;

  /// Called for every bytes payload received.
  void Function(String endpointId, Uint8List bytes)? onBytes;

  bool _running = false;
  late String _myName;
  Timer? _retryTimer;
  final Set<String> _pending = <String>{};

  Future<void> start(String deviceName) async {
    if (_running) return;
    _running = true;
    // The random suffix keeps names unique even if two phones pick the same
    // team name, and gives a stable ordering for the tie-break below.
    _myName = '$deviceName#${Random().nextInt(9000) + 1000}';

    await _advertise();
    await _discover();

    // Discovery can go quiet after a disconnect, so restart it while alone.
    _retryTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (!_running || connectedPeers.value.isNotEmpty) return;
      try {
        await Nearby().stopDiscovery();
      } catch (_) {}
      await _discover();
    });
  }

  Future<void> stop() async {
    _running = false;
    _retryTimer?.cancel();
    try {
      await Nearby().stopAdvertising();
      await Nearby().stopDiscovery();
      await Nearby().stopAllEndpoints();
    } catch (e) {
      debugPrint('Nearby stop error: $e');
    }
    _pending.clear();
    connectedPeers.value = <String>{};
  }

  Future<void> send(String endpointId, Uint8List bytes) async {
    try {
      await Nearby().sendBytesPayload(endpointId, bytes);
    } catch (e) {
      debugPrint('Nearby send failed: $e');
    }
  }

  // ---- Advertising and discovery ------------------------------------------

  Future<void> _advertise() async {
    try {
      await Nearby().startAdvertising(
        _myName,
        _strategy,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
        serviceId: _serviceId,
      );
    } catch (e) {
      debugPrint('Nearby advertise failed: $e');
    }
  }

  Future<void> _discover() async {
    try {
      await Nearby().startDiscovery(
        _myName,
        _strategy,
        onEndpointFound: (String id, String name, String serviceId) {
          if (connectedPeers.value.contains(id) || _pending.contains(id)) {
            return;
          }
          // Only the phone with the smaller name initiates.
          if (_myName.compareTo(name) >= 0) return;
          _pending.add(id);
          Nearby().requestConnection(
            _myName,
            id,
            onConnectionInitiated: _onConnectionInitiated,
            onConnectionResult: _onConnectionResult,
            onDisconnected: _onDisconnected,
          );
        },
        onEndpointLost: (String? id) {
          if (id != null) _pending.remove(id);
        },
        serviceId: _serviceId,
      );
    } catch (e) {
      debugPrint('Nearby discovery failed: $e');
    }
  }

  // ---- Connection lifecycle -----------------------------------------------

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    // Demo mode: accept every connection automatically.
    // (Future work: require a shared trip code before accepting.)
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (String endpointId, Payload payload) {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          onBytes?.call(endpointId, payload.bytes!);
        }
      },
      onPayloadTransferUpdate: (String endpointId, PayloadTransferUpdate u) {},
    );
  }

  void _onConnectionResult(String id, Status status) {
    _pending.remove(id);
    if (status == Status.CONNECTED) {
      connectedPeers.value = <String>{...connectedPeers.value, id};
      onPeerConnected?.call(id);
    }
  }

  void _onDisconnected(String id) {
    _pending.remove(id);
    connectedPeers.value = <String>{...connectedPeers.value}..remove(id);
  }
}
