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
      // Special case: needsAmbulance uses OR-merge, not plain LWW —
      // once true, it stays true unless BOTH sides agree it's false.
      // This matters because losing a real emergency signal is worse
      // than a false positive.
      if (key == 'needsAmbulance' && fields.containsKey(key)) {
        bool merged = (fields[key]!.value as bool) || (otherField.value as bool);
        HLC newerTs = otherField.timestamp.isAfter(fields[key]!.timestamp)
            ? otherField.timestamp
            : fields[key]!.timestamp;
        fields[key] = FieldValue(merged, newerTs);
        return;
      }

      // Default: Last-Writer-Wins, but using the HLC's isAfter()
      // instead of a plain integer comparison — this is what makes
      // it resistant to clock drift between devices.
      if (!fields.containsKey(key) || otherField.timestamp.isAfter(fields[key]!.timestamp)) {
        fields[key] = otherField;
      }
    });
  }

  @override
  String toString() =>
      fields.entries.map((e) => '${e.key}: ${e.value.value} (${e.value.timestamp})').join(', ');
}