---
assignees:
- claude-code
position_column: todo
position_ordinal: b880
title: Share one running scan between the parallel requests of one call
---
## What
When one call names two related boards (for example `{ lib: board(id: "lib") tools: board(id: "tools") }`), `KanbanGraph.relatedBoards` answers the two requests at the same time. Each request calls `KanbanHost.currentScanIndex(around:)`. When no index is current, each request runs its own `rescan`: `watch(places)` shares the start of the place watcher, but each request then runs `BoardLocator.scan` with its own reads of git. The load of each board starts only after the scan of its own request ends.

## Evidence (^wphkeqk, 2026-10-17)
- Full `swift test` (1592 tests): CrossRepoParallelLoadTests.boardFieldsLoadAtSameTime failed: `startsBeforeFirstEnd(of: [lib, tools]) == 2` was false. The test needs both loads to start within the load delay of 300 ms.
- Alone, the test passed 3 of 3 (47 to 69 s each, most of it git setup and git reads under machine load).
- The order of the two load starts depends on when each of the two scans ends; under load, two scans with real git can end more than 300 ms apart.

## Acceptance
- [ ] A request that needs the index while a scan of the same places runs waits for that scan and uses its index; it does not start a second scan.
- [ ] A unit test with a key reader that blocks proves that two parallel requests run one scan (one read of each key).
- [ ] CrossRepoParallelLoadTests passes in the full `swift test`.