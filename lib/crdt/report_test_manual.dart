import 'hlc.dart';
import 'report.dart';

void main() {
  print('--- Scenario 1: different fields, no conflict ---');
  var a1 = Report({
    'victims': FieldValue(15, HLC.tick(null)),
  });
  var b1 = Report({
    'needsAmbulance': FieldValue(true, HLC.tick(null)),
  });
  a1.mergeWith(b1);
  print('Result: $a1\n');
  // Expect: both fields present, nothing lost

  print('--- Scenario 2: same field, different values, newer wins ---');
  var clock1 = HLC.tick(null);
  var a2 = Report({'victims': FieldValue(15, clock1)});
  var clock2 = HLC.tick(clock1); // deliberately later than clock1
  var b2 = Report({'victims': FieldValue(12, clock2)});
  a2.mergeWith(b2);
  print('Result: $a2');
  print('Expected: victims should be 12 (the newer edit)\n');

  print('--- Scenario 3: ambulance OR-merge ---');
  var clockEarly = HLC.tick(null);
  var a3 = Report({'needsAmbulance': FieldValue(true, clockEarly)});
  var clockLater = HLC.tick(clockEarly);
  var b3 = Report({'needsAmbulance': FieldValue(false, clockLater)});
  a3.mergeWith(b3);
  print('Result: $a3');
  print('Expected: true — even though the LATER edit said false, OR-merge keeps true\n');

  print('--- Scenario 4: idempotency, merge twice ---');
  var a4 = Report({'victims': FieldValue(15, HLC.tick(null))});
  var b4 = Report({'victims': FieldValue(20, HLC.tick(a4.fields['victims']!.timestamp))});
  a4.mergeWith(b4);
  var firstResult = a4.toString();
  a4.mergeWith(b4); // merge the SAME thing again
  var secondResult = a4.toString();
  print('First merge: $firstResult');
  print('Second merge (same input): $secondResult');
  print('Expected: identical — merging twice should not change anything\n');
}