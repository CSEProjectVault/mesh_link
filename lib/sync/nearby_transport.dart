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
/// SELF-HEALING: Nearby silently stops advertising and discovering when
/// Bluetooth or Wi-Fi is switched off, and does not restart by itself when
/// they come back. So while this phone has no peers, a timer restarts BOTH
/// advertising and discovery every few seconds. That is what lets two phones
/// find each other again after the radios are toggled, without restarting
/// the app.
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
  bool _restarting = false;
  int _pendingChecks = 0;
  late String _myName;
  Timer? _healthTimer;
  final Set<String> _pending = <String>{};

  Future<void> start(String deviceName) async {
    if (_running) return;
    _running = true;
    // The random suffix keeps names unique even if two phones pick the same
    // team name, and gives a stable ordering for the tie-break below.
    _myName = '$deviceName#${Random().nextInt(9000) + 1000}';

    await _startRadios();

    // A slightly different period per phone, so two phones do not always
    // restart at exactly the same moment.
    final seconds = 10 + Random().nextInt(6);
    _healthTimer?.cancel();
    _healthTimer =
        Timer.periodic(Duration(seconds: seconds), (_) => _checkHealth());
  }

  Future<void> stop() async {
    _running = false;
    _healthTimer?.cancel();
    _healthTimer = null;
    await _stopRadios(dropConnections: true);
    _pending.clear();
    connectedPeers.value = <String>{};
  }

  /// Hard reset: drop every connection and search again from scratch.
  /// Wired to the connection chip on the home screen (tap to reconnect).
  Future<void> restart() async {
    if (!_running || _restarting) return;
    await _restartRadios(dropConnections: true);
  }

  Future<void> send(String endpointId, Uint8List bytes) async {
    try {
      await Nearby().sendBytesPayload(endpointId, bytes);
    } catch (e) {
      debugPrint('Nearby send failed: $e');
      // The link is most likely dead (radio switched off, phone walked away).
      await _dropPeer(endpointId);
    }
  }

  // ---- Keeping the connection alive ---------------------------------------

  Future<void> _checkHealth() async {
    if (!_running || _restarting) return;

    // Connected: nothing to do.
    if (connectedPeers.value.isNotEmpty) {
      _pendingChecks = 0;
      return;
    }

    // A connection attempt is in flight: give it a little time, but not
    // forever, because a stuck attempt would block that phone for good.
    if (_pending.isNotEmpty && ++_pendingChecks < 3) return;

    _pendingChecks = 0;
    await _restartRadios();
  }

  Future<void> _restartRadios({bool dropConnections = false}) async {
    _restarting = true;
    try {
      await _stopRadios(dropConnections: dropConnections);
      _pending.clear();
      if (dropConnections) connectedPeers.value = <String>{};
      if (_running) await _startRadios();
    } finally {
      _restarting = false;
    }
  }

  Future<void> _stopRadios({bool dropConnections = false}) async {
    try {
      await Nearby().stopAdvertising();
    } catch (_) {}
    try {
      await Nearby().stopDiscovery();
    } catch (_) {}
    if (dropConnections) {
      try {
        await Nearby().stopAllEndpoints();
      } catch (_) {}
    }
  }

  Future<void> _startRadios() async {
    await _advertise();
    await _discover();
  }

  Future<void> _dropPeer(String id) async {
    _pending.remove(id);
    try {
      await Nearby().disconnectFromEndpoint(id);
    } catch (_) {}
    if (connectedPeers.value.contains(id)) {
      connectedPeers.value = <String>{...connectedPeers.value}..remove(id);
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
          _requestConnection(id);
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

  Future<void> _requestConnection(String id) async {
    try {
      await Nearby().requestConnection(
        _myName,
        id,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (e) {
      // Without this, a failed request left the id in _pending forever and
      // that phone could never be connected to again.
      debugPrint('Nearby requestConnection failed: $e');
      _pending.remove(id);
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
