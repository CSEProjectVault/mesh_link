import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_link/crdt/hlc.dart';
import 'package:mesh_link/crdt/report.dart';

/// A copy that can be merged into without touching the original.
Report copyOf(Report r) => Report(Map<String, FieldValue>.from(r.fields));

/// Everything about a report as one comparable string.
String snapshot(Report r) {
  final keys = r.fields.keys.toList()..sort();
  return keys.map((k) {
    final f = r.fields[k]!;
    return '$k=${f.value}@${f.timestamp.physicalTime}:'
        '${f.timestamp.logicalCounter}';
  }).join(' | ');
}

void main() {
  group('Hybrid logical clock', () {
    test('every new local edit is ordered after the previous one', () {
      HLC? last;
      for (var i = 0; i < 1000; i++) {
        final next = HLC.tick(last);
        if (last != null) expect(next.isAfter(last), isTrue);
        last = next;
      }
    });

    test('physical time decides first, the counter breaks ties', () {
      expect(HLC(1001, 0).isAfter(HLC(1000, 9)), isTrue);
      expect(HLC(1000, 5).isAfter(HLC(1000, 3)), isTrue);
      expect(HLC(1000, 3).isAfter(HLC(1000, 5)), isFalse);
      expect(HLC(1000, 3).isAfter(HLC(1000, 3)), isFalse);
    });

    test('a received clock is after both local and remote, even when the '
        'remote phone clock runs fast', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final local = HLC(now + 5000, 2);
      final remote = HLC(now + 60000, 7);
      final merged = HLC.receive(local, remote);
      expect(merged.isAfter(local), isTrue);
      expect(merged.isAfter(remote), isTrue);
    });

    test('an edit made after seeing a future timestamp still sorts after it',
        () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final fromFastPhone = HLC(now + 60000, 4);
      expect(HLC.tick(fromFastPhone).isAfter(fromFastPhone), isTrue);
    });
  });

  group('Report merge (CRDT)', () {
    test('edits to different fields are both kept', () {
      final a = Report({'title': FieldValue('Fallen tree', HLC(1000, 0))});
      final b = Report({'status': FieldValue('Resolved', HLC(2000, 0))});
      a.mergeWith(b);
      expect(a.fields['title']!.value, 'Fallen tree');
      expect(a.fields['status']!.value, 'Resolved');
    });

    test('same field: the newer edit wins', () {
      final a = Report({'status': FieldValue('Open', HLC(1000, 0))});
      final b = Report({'status': FieldValue('In progress', HLC(2000, 0))});
      a.mergeWith(b);
      expect(a.fields['status']!.value, 'In progress');
    });

    test('an old edit arriving late does not overwrite a newer one', () {
      final a = Report({'status': FieldValue('Resolved', HLC(2000, 0))});
      final b = Report({'status': FieldValue('Open', HLC(1000, 0))});
      a.mergeWith(b);
      expect(a.fields['status']!.value, 'Resolved');
    });

    test('edits in the same millisecond are ordered by the counter', () {
      final a = Report({'status': FieldValue('first', HLC(1000, 1))});
      final b = Report({'status': FieldValue('second', HLC(1000, 2))});
      a.mergeWith(b);
      expect(a.fields['status']!.value, 'second');
    });

    test('needsAmbulance never goes back to false', () {
      final a = Report({'needsAmbulance': FieldValue(true, HLC(1000, 0))});
      final b = Report({'needsAmbulance': FieldValue(false, HLC(2000, 0))});
      a.mergeWith(b);
      expect(a.fields['needsAmbulance']!.value, isTrue);

      final c = Report({'needsAmbulance': FieldValue(false, HLC(3000, 0))});
      final d = Report({'needsAmbulance': FieldValue(true, HLC(500, 0))});
      c.mergeWith(d);
      expect(c.fields['needsAmbulance']!.value, isTrue);
    });

    test('merging the same data twice changes nothing', () {
      final a = Report({'victims': FieldValue(15, HLC(1000, 0))});
      final b = Report({
        'victims': FieldValue(20, HLC(2000, 0)),
        'status': FieldValue('Open', HLC(1500, 0)),
      });
      a.mergeWith(b);
      final once = snapshot(a);
      a.mergeWith(b);
      expect(snapshot(a), once);
    });

    test('merge order does not matter for two phones', () {
      final a = Report({
        'title': FieldValue('A title', HLC(1000, 0)),
        'status': FieldValue('Open', HLC(3000, 0)),
      });
      final b = Report({
        'title': FieldValue('B title', HLC(2000, 0)),
        'status': FieldValue('Resolved', HLC(1500, 0)),
      });
      final ab = copyOf(a)..mergeWith(b);
      final ba = copyOf(b)..mergeWith(a);
      expect(snapshot(ab), snapshot(ba));
    });

    test('three phones end in the same state in any merge order', () {
      final rng = Random(42);
      const names = ['title', 'description', 'status', 'severity', 'victims'];

      // Timestamps never collide between phones: 1000 + k*3 + phoneId.
      Report makeReplica(int id) => Report({
            for (final n in names)
              n: FieldValue(
                '$n from phone $id',
                HLC(1000 + rng.nextInt(1000) * 3 + id, 0),
              ),
          });

      final a = makeReplica(0);
      final b = makeReplica(1);
      final c = makeReplica(2);

      final abc = copyOf(a)..mergeWith(b)..mergeWith(c);
      final cab = copyOf(c)..mergeWith(a)..mergeWith(b);
      final bca = copyOf(b)..mergeWith(c)..mergeWith(a);

      expect(snapshot(cab), snapshot(abc));
      expect(snapshot(bca), snapshot(abc));
    });

    test('a deleted mark survives merging older data that lacks it', () {
      final local = Report({
        'title': FieldValue('Fallen tree', HLC(1000, 0)),
        'deleted': FieldValue(true, HLC(3000, 0)),
      });
      final olderCopy = Report({'title': FieldValue('Fallen tree', HLC(1000, 0))});

      // A phone that never saw the delete cannot bring the report back...
      local.mergeWith(olderCopy);
      expect(local.fields['deleted']!.value, isTrue);

      // ...and it learns about the delete when it syncs.
      olderCopy.mergeWith(local);
      expect(olderCopy.fields['deleted']!.value, isTrue);
    });
  });
}