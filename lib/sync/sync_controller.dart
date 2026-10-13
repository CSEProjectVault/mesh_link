import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'nearby_transport.dart';
import 'sync_service.dart';

/// Glue between the transport (bytes over Nearby) and SyncService
/// (reports and merging). Screens only use three things from here:
///   - start(deviceName)       called once from the home screen
///   - broadcastReport(id)     called after any local edit or message
///   - peerCount               number of connected phones, for the UI chip
class SyncController {
  SyncController._();

  static final ValueNotifier<int> peerCount = ValueNotifier<int>(0);
  static bool _started = false;
    static Future<void> stop() async {
    await NearbyTransport.instance.stop();
    _started = false;
    peerCount.value = 0;
  }
  /// Safe to call more than once; only the first call does anything.
  static Future<void> start(String deviceName) async {
    if (_started) return;
    _started = true;

    await _requestPermissions();

    final transport = NearbyTransport.instance;

    transport.connectedPeers.addListener(() {
      peerCount.value = transport.connectedPeers.value.length;
    });

    // A phone just connected: send it everything we have. It does the same
    // for us. Merging is idempotent, so duplicates and any order are fine.
    transport.onPeerConnected = (String peerId) async {
      final payloads = await SyncService.instance.buildSnapshotPayloads();
      for (final p in payloads) {
        await transport.send(peerId, p);
      }
    };

    transport.onBytes = (String peerId, Uint8List bytes) async {
      await SyncService.instance.applyIncoming(bytes);
    };

    await transport.start(deviceName);
  }

  /// Push one report (fields + messages) to every connected phone.
  /// Does nothing when nobody is connected; the data goes out in the full
  /// snapshot the next time a phone connects.
  static Future<void> broadcastReport(String reportId) async {
    final peers = NearbyTransport.instance.connectedPeers.value;
    if (peers.isEmpty) return;

    final payloads = await SyncService.instance.buildReportPayloads(reportId);
    for (final peer in peers) {
      for (final p in payloads) {
        await NearbyTransport.instance.send(peer, p);
      }
    }
  }

  static Future<void> _requestPermissions() async {
    final results = await <Permission>[
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();

    // Some of these do not exist on older Android versions and report as
    // denied there, so this only logs. If sync does not start, this log is
    // the first place to look.
    results.forEach((permission, status) {
      if (!status.isGranted) {
        debugPrint('Sync: permission not granted: $permission ($status)');
      }
    });
  }
}
