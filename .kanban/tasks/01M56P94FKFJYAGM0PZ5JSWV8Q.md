---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5a1zp7nt10kx7b5p3h50ka6
  text: |-
    Research:
    - `KanbanHost.currentScanIndex(around:)` calls `rescan` when no current index is in `scanCache`. Two parallel calls each run `rescan`, so each call runs `BoardLocator.scan` and reads the keys again. `ScanCache` counts the running scans (`runningScans`), but no call waits for a running scan.
    - A cancel of the call during a scan must stop the scan and throw `gitCancelled` (CrossRepoReadTests.cancelledScanStoresNoIndex). Thus the first call runs the scan in its own task (structured). A shared unstructured Task would not get the cancel of the caller.
    - Plan: the host keeps a `RunningScan` for each list of places while a scan runs. A second call waits for its index. A cancel of a waiting call ends only its own wait (it throws `gitCancelled`). When the scan gives no index (for example, a cancel of the first call), each waiting call checks the cache again and can start its own scan.
    - Test seam: `BoardScanObserver` gets `scanWaitDidStart(inPlaces:)`, so that a unit test knows that the second call waits. The only conformer is the test `ScanRecorder`.
  timestamp: 2026-10-19T12:25:35.733505+00:00
- actor: claude-code
  id: 01m5a2e92k6bbjgj27c0b2mtta
  text: |-
    Implementation landed:
    - New `RunningScan` (Sources/FoundationModelsKanban/CrossRepo/RunningScan.swift): the record of one running scan. Waiting calls keep a continuation behind a Mutex. A cancel handler ends only the wait of its own call (it returns `nil`), so no unstructured Task is necessary.
    - `KanbanHost.currentScanIndex(around:)` now loops: current index -> return it; no running scan -> `rescan` (the caller runs the scan in its own task, so its cancel still stops the scan); a running scan -> wait for its index. When that scan gives no index (for example, a cancel of the first call), the waiting call checks again and can scan itself. A cancelled waiter throws `gitCancelled(arguments: [])`.
    - `rescan` registers the `RunningScan` before the first suspension (before `watch(places)`), and calls `finish(giving:)` on each path. The old body of `rescan` is now `scanOutcome`, which gives a `Result`.
    - `BoardScanObserver.scanWaitDidStart(inPlaces:)` is the test seam. The only conformer is the test `ScanRecorder`.
    - Tests (ScanCacheTests, "Parallel calls"): `parallelCallsShareOneScan` (one scan, one key read of each repo), `cancelledWaitEndsOnlyItsWait`, `waitingCallScansAgainAfterCancelledScan`. They use the new `HeldScanFixture` and a `ScanKeyReader` that holds the key reads of the `lib` repo at a `TestGate`. RED before the change: scanCount 2, key reads 2 for each repo, scanWaitCount 0. GREEN after the change.
    - Full `swift test`: 1612 tests in 132 suites passed, 0 issues. CrossRepoParallelLoadTests.boardFieldsLoadAtSameTime passed (11.9 s). Only the accepted mlx Metal and SwiftPM "missing creator" warnings.
  timestamp: 2026-10-19T12:33:33.779341+00:00
- actor: claude-code
  id: 01m5a2edwv6hvzyh3fyr0sqtqf
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/CrossRepo/RunningScan.swift (new), Sources/FoundationModelsKanban/Tool/KanbanHost.swift, Sources/FoundationModelsKanban/CrossRepo/ScanChange.swift, Tests/FoundationModelsKanbanTests/CrossRepo/ScanCacheTests.swift. `swift test`: 1612 tests, 132 suites, 0 issues.
    - next: /review
  timestamp: 2026-10-19T12:33:38.715493+00:00
- actor: claude-code
  id: 01m5a2m0mg5w3r6mhqbzyv8f35
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (fcf4e2e). 4 files reviewed. 0 findings, 0 confirmed, 1 refuted, 7 attempted, 0 failed. The ignore rule (.reviewignore) excluded 2 files in .kanban/.
    - next: none. The task is in done.
  timestamp: 2026-10-19T12:36:41.744315+00:00
- actor: claude-code
  id: 01m5a2mbqs787rb7tqgpqp0982
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 4 files
    - test: green — swift test, 1612 passed
    - commit: fcf4e2e
    - review: clean — 0 findings
  timestamp: 2026-10-19T12:36:53.113806+00:00
position_column: done
position_ordinal: ff9980
title: Share one running scan between the parallel requests of one call
---
## What
When one call names two related boards (for example `{ lib: board(id: "lib") tools: board(id: "tools") }`), `KanbanGraph.relatedBoards` answers the two requests at the same time. Each request calls `KanbanHost.currentScanIndex(around:)`. When no index is current, each request runs its own `rescan`: `watch(places)` shares the start of the place watcher, but each request then runs `BoardLocator.scan` with its own reads of git. The load of each board starts only after the scan of its own request ends.

## Evidence (^wphkeqk, 2026-10-17)
- Full `swift test` (1592 tests): CrossRepoParallelLoadTests.boardFieldsLoadAtSameTime failed: `startsBeforeFirstEnd(of: [lib, tools]) == 2` was false. The test needs both loads to start within the load delay of 300 ms.
- Alone, the test passed 3 of 3 (47 to 69 s each, most of it git setup and git reads under machine load).
- The order of the two load starts depends on when each of the two scans ends; under load, two scans with real git can end more than 300 ms apart.

## Acceptance
- [x] A request that needs the index while a scan of the same places runs waits for that scan and uses its index; it does not start a second scan.
- [x] A unit test with a key reader that blocks proves that two parallel requests run one scan (one read of each key).
- [x] CrossRepoParallelLoadTests passes in the full `swift test`.