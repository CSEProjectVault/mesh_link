import '../crdt/report.dart';
import '../sync/sync_service.dart';
import 'pin_models.dart';

class ReportPinAdapter {
  // Generates a report/pin ID that's safe to create offline, on any
  // device, with no risk of two different phones ever picking the
  // same ID — combines device name + current time.
  static String generateId(String deviceName) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return '${deviceName}_$now';
  }

  // Turn a freshly-created Pin (from CreatePinScreen) into a Report,
  // ready to be saved via DatabaseHelper.
  static Report reportFromPin(Pin pin, String authorName) {
    // Use the device's shared clock (not a fresh one) so this edit is always
    // ordered after anything already received from other phones.
    final ts = SyncService.instance.nextClock();
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
      // asNameMap() returns null for unknown names instead of throwing, so a
      // bad value from another phone cannot crash the home screen.
      severity:
          Severity.values.asNameMap()[f['severity']?.value] ?? Severity.medium,
      category: PinCategory.values.asNameMap()[f['category']?.value] ??
          PinCategory.hazard,
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
  //
  // [deliveredIds] are the ids of our own messages that another phone has
  // confirmed receiving (DatabaseHelper.getDeliveredIds).
  static List<ThreadMessage> threadMessagesFromRows(
    List<Map<String, dynamic>> rows,
    String pinId,
    String currentDeviceName, [
    Set<String> deliveredIds = const <String>{},
  ]) {
    return rows.map((row) {
      final physical = row['hlc_physical'] as int;
      final id = row['id'] as String;
      final isOwn = row['from_team'] == currentDeviceName;
      return ThreadMessage(
        id: id,
        pinId: pinId,
        authorName: row['from_team'] as String,
        text: row['content'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(physical),
        isOwnDevice: isOwn,
        // Messages from other phones have obviously arrived. Our own show the
        // double tick only once another phone has confirmed receiving them;
        // until then they show the waiting clock.
        synced: isOwn ? deliveredIds.contains(id) : true,
      );
    }).toList();
  }
}