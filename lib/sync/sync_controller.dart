import 'dart:async';

import 'package:flutter/foundation.dart';

import 'nearby_transport.dart';
import 'sync_service.dart';

/// Glue between the transport (bytes) and SyncService (merge logic).
/// Replaces the stub; keeps the same public surface the screens use:
///   SyncController.peerCount, start(), broadcastReport().
///
/// Sync is state-based: on connect, each side sends everything it has, and
/// merging is idempotent, so duplicates are harmless.
class SyncController {
  SyncController._();

  static final NearbyTransport _transport = NearbyTransport();

  /// Connected peers, for the Home screen chip.
  static final ValueNotifier<int> peerCount = _transport.peerCount;

  /// Bumped by SyncService whenever incoming data changed the local DB.
  /// Screens can listen to this to reload without being reopened.
  static ValueNotifier<int> get dataVersion =>
      SyncService.instance.dataVersion;

  static bool _started = false;
  static bool _starting = false;

  // Incoming merges and outgoing snapshots run one at a time so DB
  // reads and writes never interleave.
  static Future<void> _queue = Future.value();

  /// Call after login with the team/device name. Safe to call repeatedly.
  static Future<void> start(String deviceName) async {
    if (_started || _starting) return;
    _starting = true;

    _transport.onPeerConnected = (endpointId) {
      _enqueue(() async {
        final payloads = await SyncService.instance.buildSnapshotPayloads();
        for (final p in payloads) {
          await _transport.sendTo(endpointId, p);
        }
        debugPrint('[sync] sent ${payloads.length} payloads to $endpointId');
      });
    };

    _transport.onBytes = (endpointId, bytes) {
      _enqueue(() async {
        final changed = await SyncService.instance.applyIncoming(bytes);
        debugPrint(
          '[sync] ${bytes.length} B from $endpointId, changed=$changed',
        );
      });
    };

    try {
      _started = await _transport.start(deviceName);
    } finally {
      _starting = false;
    }
  }

  /// Push one report (fields + messages) to every connected peer.
  /// Call after creating a report or sending a message.
  static Future<void> broadcastReport(String reportId) async {
    if (_transport.peers.isEmpty) return;
    try {
      final payloads =
          await SyncService.instance.buildReportPayloads(reportId);
      for (final p in payloads) {
        await _transport.broadcast(p);
      }
    } catch (e) {
      debugPrint('[sync] broadcastReport failed: $e');
    }
  }

  static Future<void> stop() async {
    await _transport.stop();
    _started = false;
  }

  static void _enqueue(Future<void> Function() job) {
    _queue = _queue.then((_) => job()).catchError((Object e) {
      debugPrint('[sync] job failed: $e');
    });
  }
}