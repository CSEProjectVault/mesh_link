# MeshLink Design Note

## Problem

Field teams (rescue, trekking) work with no signal. Several people may update the same incident report on different phones while out of contact. When the phones meet, they must end up with the same data, without a server and without losing anything critical.

## Requirements

1. No central server; any two phones can sync directly.
2. Phone clocks can be wrong, so wall-clock time alone cannot decide which edit is newer.
3. Sync messages may be dropped, duplicated or arrive out of order.
4. A real emergency signal must never be lost to a merge.

## Design

**Hybrid Logical Clock (HLC).** Each edit carries `(physical time, counter)`. Physical time is compared first and the counter breaks ties. On receiving a remote edit, a phone moves its clock past both its own and the remote one, so a new local edit always sorts after anything it has seen, even if its wall clock is behind.

**Per-field merge.** A report is a map of fields, each with its own HLC. Merging keeps the newer value for each field separately, so two people editing different fields (say title and status) lose nothing.

**Sticky safety flag.** `needsAmbulance` merges with OR instead of last-writer-wins. Once any phone sets it to true, it stays true. A false alarm costs a phone call; a lost emergency can cost a life, so the merge is biased towards the safe side. `ambulanceStatus` is the deliberate exception: it uses normal last-writer-wins, because someone explicitly marking it Resolved is a real correction.

**Tombstone for delete.** Deleting sets a `deleted` field instead of removing the data. A phone that never saw the delete cannot bring the report back when it syncs.

**State-based sync.** Phones send each report's current fields with their HLCs, plus thread messages in small batches (Nearby Connections limits a payload to about 32 KB). Because the merge is idempotent, commutative and associative, duplicate, reordered or dropped messages only delay convergence and never corrupt it. Thread messages are append-only with unique ids, so they never conflict.

## A bug found while testing

The first version broke ties between edits only through the HLC. Two phones can produce the exact same HLC (same millisecond, same counter) with different values. Then neither edit counted as newer, and the winner depended on which phone merged first, so the phones could disagree forever. The unit tests hadn't caught it because they never created equal timestamps. The fix is a deterministic tie-break on the value, which every phone computes the same way. The randomized test and a dedicated tie test now cover this case.

## How it is tested

- Unit tests cover the clock and each merge rule.
- A randomized simulation runs 2, 6 and 12 phones making random edits while messages are delayed, duplicated, reordered and dropped (hundreds of seeds). After a final sync round every phone must hold identical state, and a raised emergency flag must never be lost.

## Trade-offs and limits

| Choice | Benefit | Cost |
|---|---|---|
| Last-writer-wins per field | Simple and easy to reason about | A concurrent edit to the same field is silently overwritten; a text CRDT would keep both |
| Full-state sync | Simple, robust to lost messages | Resends unchanged data; delta sync would use less bandwidth |
| Hand-rolled CRDT instead of Automerge | Small, fully understood, tailored to the safety rules | Less general and not formally verified |
| Tombstones | Delete is safe | Deleted data is never reclaimed |

## Future work

- Benchmarks: sync time and payload size versus number of reports.
- Delta sync, and a text CRDT for `description`.
- Tests with many physical devices over real Bluetooth / Wi-Fi.
