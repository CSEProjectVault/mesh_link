import 'hlc.dart';
void main() {
  print('--- tick() basics ---');
  final t0 = HLC.tick(null);
  print('t0 = $t0');

  final t1 = HLC.tick(t0);
  print('t1 = $t1');
  assert(t1.isAfter(t0), 't1 should be after t0');
  HLC last = t1;
  for (var i = 0; i < 5; i++) {
    final next = HLC.tick(last);
    print('tick $i -> $next');
    assert(next.isAfter(last), 'each tick must be after the previous one');
    last = next;
  }

  print('\n--- isAfter() ordering ---');
  final a = HLC(1000, 3);
  final b = HLC(1000, 5);
  final c = HLC(1001, 0);
  print('$a isAfter $b? ${a.isAfter(b)}'); 
  print('$b isAfter $a? ${b.isAfter(a)}'); 
  print('$c isAfter $b? ${c.isAfter(b)}'); 
  assert(!a.isAfter(b));
  assert(b.isAfter(a));
  assert(c.isAfter(b));

  final int base = DateTime.now().millisecondsSinceEpoch + 60000;

  print('\n--- receive(): tied physical time, remote has higher counter ---');
  final localTied = HLC(base, 1);
  final remoteTied = HLC(base, 4);
  final merged1 = HLC.receive(localTied, remoteTied);
  print('receive($localTied, $remoteTied) -> $merged1');
  assert(merged1.isAfter(localTied));
  assert(merged1.isAfter(remoteTied));
  assert(merged1.physicalTime == base);
  assert(merged1.logicalCounter == 5, 'should bump past the higher counter (4+1)');

  print('\n--- receive(): local is ahead in physical time ---');
  final localAhead = HLC(base + 5000, 2);
  final remoteBehind = HLC(base, 9);
  final merged2 = HLC.receive(localAhead, remoteBehind);
  print('receive($localAhead, $remoteBehind) -> $merged2');
  assert(merged2.isAfter(localAhead));
  assert(merged2.isAfter(remoteBehind));
  assert(merged2.physicalTime == base + 5000);
  assert(merged2.logicalCounter == 3, 'should be local counter + 1, ignoring remote');

  print('\n--- receive(): remote is ahead in physical time ---');
  final localOlder = HLC(base, 50);
  final remoteFuture = HLC(base + 8000, 0);
  final merged3 = HLC.receive(localOlder, remoteFuture);
  print('receive($localOlder, $remoteFuture) -> $merged3');
  assert(merged3.isAfter(localOlder));
  assert(merged3.isAfter(remoteFuture));
  assert(merged3.physicalTime == base + 8000);
  assert(merged3.logicalCounter == 1, 'should be remote counter + 1, ignoring local');

  print('\nAll assertions passed — clock ordering behaves sensibly.');
}
