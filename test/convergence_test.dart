import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_link/crdt/hlc.dart';
import 'package:mesh_link/crdt/report.dart';

/// Randomized convergence test.
///
/// N phones make random edits while messages (full report snapshots, as in
/// SyncService) are delayed, reordered, duplicated and dropped, which
/// models flaky radio links and network partitions. Afterwards the phones
/// get one reliable round of syncing. The CRDT promise is that they must
/// then all hold exactly the same state.

Report copyOf(Report r) => Report(Map<String, FieldValue>.from(r.fields));

String snapshot(Report r) {
  final keys = r.fields.keys.toList()..sort();
  return keys.map((k) {
    final f = r.fields[k]!;
    return '$k=${f.value}@${f.timestamp.physicalTime}:${f.timestamp.logicalCounter}';
  }).join(' | ');
}

class Phone {
  final int id;
  Report report = Report({});
  HLC? clock;
  bool everRaisedAmbulance = false;
  Phone(this.id);

  void edit(String field, dynamic value) {
    clock = HLC.tick(clock);
    report.mergeWith(Report({field: FieldValue(value, clock!)}));
    if (field == 'needsAmbulance' && value == true) everRaisedAmbulance = true;
  }

  void receive(Report incoming) {
    for (final f in incoming.fields.values) {
      clock = clock == null ? f.timestamp : HLC.receive(clock!, f.timestamp);
    }
    report.mergeWith(incoming);
  }
}

/// Returns the converged snapshot, so callers can compare runs.
String runSimulation(int seed, {int phones = 6, int steps = 400}) {
  final rng = Random(seed);
  const fields = ['title', 'description', 'status', 'priority', 'ambulanceStatus'];
  final ps = [for (var i = 0; i < phones; i++) Phone(i)];
  final inFlight = <(int, Report)>[]; // (destination, snapshot)

  for (var s = 0; s < steps; s++) {
    final p = ps[rng.nextInt(phones)];
    switch (rng.nextInt(4)) {
      case 0: // edit an ordinary field
        final f = fields[rng.nextInt(fields.length)];
        p.edit(f, '$f-${rng.nextInt(5)}');
      case 1: // raise or (try to) clear the emergency flag
        p.edit('needsAmbulance', rng.nextBool());
      case 2: // send a snapshot to a random peer; may arrive late
        final to = rng.nextInt(phones);
        if (to != p.id) inFlight.add((to, copyOf(p.report)));
        if (rng.nextInt(5) == 0 && inFlight.isNotEmpty) {
          inFlight.add(inFlight.last); // duplicate delivery
        }
      case 3: // deliver a random in-flight message (reordering), or drop it
        if (inFlight.isNotEmpty) {
          final (to, snap) = inFlight.removeAt(rng.nextInt(inFlight.length));
          if (rng.nextInt(4) != 0) ps[to].receive(snap); // 25% dropped
        }
    }
  }

  // Phones come back in range: everything still in flight is delivered,
  // then each phone shares its state with every other phone, twice.
  for (final (to, snap) in inFlight) {
    ps[to].receive(snap);
  }
  for (var round = 0; round < 2; round++) {
    for (final a in ps) {
      for (final b in ps) {
        if (a != b) b.receive(copyOf(a.report));
      }
    }
  }

  final reference = snapshot(ps.first.report);
  for (final p in ps) {
    expect(snapshot(p.report), reference,
        reason: 'seed $seed: phone ${p.id} diverged');
  }

  // Safety property: once any phone raised the emergency flag, it can
  // never be lost by merging, whatever the delivery order.
  if (ps.any((p) => p.everRaisedAmbulance)) {
    expect(ps.first.report.fields['needsAmbulance']!.value, isTrue,
        reason: 'seed $seed: emergency flag was lost');
  }
  return reference;
}

void main() {
  group('Randomized convergence', () {
    test('6 phones converge under delay, drop, duplication and reordering '
        '(200 seeds)', () {
      for (var seed = 0; seed < 200; seed++) {
        runSimulation(seed);
      }
    });

    test('also holds for 2 phones and for 12 phones', () {
      for (var seed = 0; seed < 50; seed++) {
        runSimulation(seed, phones: 2);
        runSimulation(seed, phones: 12, steps: 800);
      }
    });
  });

  group('Exact HLC ties', () {
    test('two phones writing different values at the identical HLC '
        'still converge', () {
      final a = Report({'status': FieldValue('Open', HLC(5000, 3))});
      final b = Report({'status': FieldValue('Resolved', HLC(5000, 3))});
      final ab = copyOf(a)..mergeWith(b);
      final ba = copyOf(b)..mergeWith(a);
      expect(snapshot(ab), snapshot(ba));
    });
  });
}
