# MeshLink — Offline Field Sync

Rescue and trekking teams often work where there is no signal. MeshLink lets phones share incident reports directly with each other over Bluetooth / Wi-Fi (Android Nearby Connections), with no server and no internet. When two people edit the same report while out of contact, the edits merge automatically and every phone ends up with the same data.
   📄 **[Read the full design note →](docs/DESIGN.md)**

## Design

| Problem | Approach |
|---|---|
| Phone clocks disagree | **Hybrid Logical Clock** (`lib/crdt/hlc.dart`): wall time plus a counter, so a wrong clock can't make a new edit look old |
| Two people edit the same report offline | **Per-field last-writer-wins** (`lib/crdt/report.dart`): edits to different fields are all kept |
| A safety flag must never be lost | `needsAmbulance` is an **OR-merge** (once true, it stays true), unlike ordinary fields |
| Identical timestamps from two phones | Deterministic tie-break on the value, so the winner never depends on merge order |
| Deleting a report | A `deleted` field is a tombstone; an older copy can't bring the report back |
| Chat threads on a report | Append-only messages with unique ids, which never conflict |
| Radio links are flaky | **State-based sync** (`lib/sync/sync_service.dart`): merging is idempotent, commutative and associative, so duplicates, drops and reordering are harmless |

## Correctness tests

```
flutter test test/crdt_test.dart test/convergence_test.dart
```

- `crdt_test.dart` — unit tests for the clock and each merge rule.
- `convergence_test.dart` — randomized simulation: 2 / 6 / 12 phones make random edits while messages are delayed, duplicated, reordered and dropped (hundreds of seeds). After a final sync round all phones must hold identical state, and a raised emergency flag must never be lost.

## Stack

Flutter · SQLite (`sqflite`) · Nearby Connections (`P2P_CLUSTER`) · hand-rolled HLC + field-level CRDT (no Automerge).

## Project structure

```
lib/
  crdt/      # HLC clock and Report merge logic
  db/        # SQLite storage (fields with per-field HLC, thread messages)
  sync/      # Nearby transport, payload building, merge on receive
  services/  # Auth, location, report actions
  screens/   # UI
test/        # Unit + randomized convergence tests
```

## Run

```
flutter doctor
flutter pub get
flutter run          # Android device with Bluetooth/Wi-Fi
```

## Limitations and future work

- Last-writer-wins can silently drop a concurrent edit to the same field; a text CRDT for `description` would preserve both.
- Full-state sync resends whole reports; delta sync would cut bandwidth for large reports.
- No benchmarks yet on sync time and payload size versus report count.
- Not yet tested on a large number of physical devices.
