// lib/sync/sync_controller.dart (STUB)
import 'package:flutter/foundation.dart';

class SyncController {
  static final ValueNotifier<int> peerCount = ValueNotifier<int>(0);
  static Future<void> start(String deviceName) async {}
  static Future<void> broadcastReport(String reportId) async {}
}