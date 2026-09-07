import 'hlc.dart';

class FieldValue {
  dynamic value;
  HLC timestamp;
  FieldValue(this.value, this.timestamp);
}

class Report {
  Map<String, FieldValue> fields;
  Report(this.fields);

  // Merge another report into this one, field by field.
  void mergeWith(Report other) {
    other.fields.forEach((key, otherField) {
      // Special case 1: needsAmbulance is a STICKY safety flag.
      // Once true, it stays true — losing a real emergency signal
      // is worse than a false positive. This is OR-merge, not LWW.
      if (key == 'needsAmbulance' && fields.containsKey(key)) {
        bool merged = (fields[key]!.value as bool) || (otherField.value as bool);
        HLC newerTs = otherField.timestamp.isAfter(fields[key]!.timestamp)
            ? otherField.timestamp
            : fields[key]!.timestamp;
        fields[key] = FieldValue(merged, newerTs);
        return;
      }

      // Special case 2: ambulanceStatus tracks the actual resolution
      // (Requested / Dispatched / Resolved). This is a deliberate,
      // attributable correction, so it uses plain LWW — unlike
      // needsAmbulance, it CAN change back, because someone explicitly
      // marked it resolved.
      if (key == 'ambulanceStatus') {
        if (!fields.containsKey(key) || otherField.timestamp.isAfter(fields[key]!.timestamp)) {
          fields[key] = otherField;
        }
        return;
      }

      // Default: Last-Writer-Wins for everything else.
      if (!fields.containsKey(key) || otherField.timestamp.isAfter(fields[key]!.timestamp)) {
        fields[key] = otherField;
      }
    });
  }

  @override
  String toString() =>
      fields.entries.map((e) => '${e.key}: ${e.value.value} (${e.value.timestamp})').join(', ');
}