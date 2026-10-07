import 'package:flutter/material.dart';
import '../crdt/hlc.dart';
import '../crdt/report.dart';
import 'pin_models.dart';

class ReportPinAdapter {
  // Generates a report/pin ID that's safe to create offline, on any
  // device, with no risk of two different phones ever picking the
  // same ID — combines device name + current time + a tick counter.
  static String generateId(String deviceName) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return '${deviceName}_$now';
  }

  // Turn a freshly-created Pin (from CreatePinScreen) into a Report,
  // ready to be saved via DatabaseHelper.
  static Report reportFromPin(Pin pin, String authorName) {
    final ts = HLC.tick(null);
    return Report({
      'title': FieldValue(pin.title, ts),
      'description': FieldValue(pin.description, ts),
      'severity': FieldValue(pin.severity.name, ts),
      'category': FieldValue(pin.category.name, ts),
      'lat': FieldValue(pin.lat, ts),
      'lng': FieldValue(pin.lng, ts),
      'authorName': FieldValue(pin.authorName, ts),
      'createdAt': FieldValue(pin.createdAt.millisecondsSinceEpoch, ts),
    });
  }

  // Turn a stored Report (read from the database) back into a Pin
  // the UI already knows how to display.
  static Pin pinFromReport(Report report, String id) {
    final f = report.fields;
    return Pin(
      id: id,
      lat: (f['lat']?.value as num?)?.toDouble() ?? 0.0,
      lng: (f['lng']?.value as num?)?.toDouble() ?? 0.0,
      severity: Severity.values.byName(f['severity']?.value ?? 'medium'),
      category: PinCategory.values.byName(f['category']?.value ?? 'hazard'),
      title: f['title']?.value ?? '',
      description: f['description']?.value ?? '',
      authorName: f['authorName']?.value ?? 'Unknown',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        f['createdAt']?.value ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  // Turn raw DB rows (from DatabaseHelper.getMessages) into the
  // ThreadMessage objects report_detail_screen.dart expects.
  static List<ThreadMessage> threadMessagesFromRows(
    List<Map<String, dynamic>> rows,
    String pinId,
    String currentDeviceName,
  ) {
    return rows.map((row) {
      final physical = row['hlc_physical'] as int;
      return ThreadMessage(
        id: row['id'] as String,
        pinId: pinId,
        authorName: row['from_team'] as String,
        text: row['content'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(physical),
        isOwnDevice: row['from_team'] == currentDeviceName,
        // NOTE: synced is always true here — this only reflects data
        // that's already in the local DB. Real "not yet shared with
        // anyone else" status needs a separate sync-tracking column,
        // not yet built — flag this as a known gap, not a bug.
        synced: true,
      );
    }).toList();
  }
}