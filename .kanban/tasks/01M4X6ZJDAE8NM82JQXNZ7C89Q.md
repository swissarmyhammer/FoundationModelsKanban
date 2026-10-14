---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4xqbxhnn7gh6ctbjyma5fva
  text: |-
    Research done.
    - BoardLoader.readStages (Sources/FoundationModelsKanban/Events/Loader.swift) has two callers: BoardLoader.load (lists with stageRefs, which calls EventLog.nodeRefs for each type) and LiveGraph.reload (lists from a set of changed refs). Both must keep the same result.
    - The join result depends only on the order of the graph.update / graph.remove calls: stage order, then the sort order of the ref text in each stage. The global event list depends on the order of the per-file event lists (EventMerge breaks equal ids by list index). Plan: read all files in one pool, then group the results by ref.nodeType and join in stageOrder, sorted by StagedLog.precedes. Thus the call order and the list order stay the same as before.
    - Listing: run the six fileList calls in one task group, then put the refs back in stage order. The fileList closure must become @escaping @Sendable (both callers capture Sendable values).
    - Test seam: LoaderWorkerObserver gets a per-file call (workerWillRead(fileOf:)) with a default empty body, so WorkerMeter and WorkerCounter do not change. A test observer holds the board file until a comment file starts (with a timeout). With stages, the comment stage cannot start while the board stage waits, so the old code fails the test. The same hold on the listing closure proves the listings run at the same time.
    - LoaderTests has no .watcherBudget trait; I add it to the suite so that the loader tests run within the WatcherBudget trait.
  timestamp: 2026-10-14T17:29:08.917542+00:00
- actor: claude-code
  id: 01m4xqk0hb1n7q9ph294zkwgyd
  text: |-
    Implementation landed (TDD).
    - RED: two new tests in LoaderTests failed for the expected reason. The pool test failed because no per-file call existed (the board file was never held). The listing test timed out after 5 s, because the old code listed the folders one after the other.
    - GREEN: BoardLoader.readStages now (1) runs the six fileList calls in one task group (listFiles), (2) reads all files of all node types with one WorkQueue and one worker pool (readFiles), (3) groups the folded logs by ref.nodeType and joins them in stageOrder, each type sorted by StagedLog.precedes (joinOrder). The graph.update/remove call order and the event-list order are the same as before, so the graph and the global event list do not change. The worker count is min(workerCount, file count), so the peak stays in the limit.
    - fileList is now `@escaping @Sendable`. Both callers (BoardLoader.load and LiveGraph.reload) compile with no change, because they capture only Sendable values.
    - LoaderWorkerObserver has a new requirement workerWillRead(fileOf:) with a default empty body. WorkerMeter and WorkerCounter do not change.
    - The LoaderTests suite now has the .watcherBudget trait.
    - Divergence: plan.md §5.3 ("Work queue": "The stage ends when all workers are done (a barrier). Then the next stage starts.") still describes the old barriers. I did not edit plan.md (rule: never edit plan.md). A person must update that paragraph.
    - What did not work: nothing failed. Note: the probe in the tests blocks a cooperative thread for at most StageOverlapProbe.holdSeconds (5 s); the pool test needs two workers that can run at the same time.
  timestamp: 2026-10-14T17:33:01.355384+00:00
- actor: claude-code
  id: 01m4xqk24kaqw7v6m0n3hfng1h
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/Events/Loader.swift, Sources/FoundationModelsKanban/Observe/LiveGraph.swift (doc comments only), Tests/FoundationModelsKanbanTests/Events/LoaderTests.swift. `swift test`: 1188 tests in 86 suites passed; the only warning is the accepted SwiftPM "missing creator" warning.
    - next: /review
  timestamp: 2026-10-14T17:33:02.995231+00:00
- actor: claude-code
  id: 01m4xqxhmbt09v5tkeyfzdk1s9
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 files
    - test: green — swift test, 1188 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: 13dad3d
    - review: clean — none
  timestamp: 2026-10-14T17:38:46.539168+00:00
position_column: done
position_ordinal: e280
title: Load all board files in one worker pool and list the node folders at the same time
---
## What
divergence.md §16, L2 and L3. The user: "we do need our board load to be as parallel as possible." This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

- L2: the loader reads the files of one node type at a time: board, actors, columns, tags, tasks, comments (S/Events/Loader.swift:44,109-119). Each stage waits for its slowest file before the next stage starts. But each file folds alone (`log.readLog(of:)`, :171). Only the join needs the stage order. Change: one worker pool reads and folds all files of all node types. Then the join runs in stage order, in memory. This removes five barriers.
- L3: the directory listings run one after the other (:151-156, one for each node type). Change: list the six folders at the same time.
- The result of a load must not change: the same graph, the same events, the same order of the join.

## Acceptance Criteria
- [x] One worker pool reads and folds the files of all six node types.
- [x] The join runs in stage order after all folds are done, and gives the same graph as before.
- [x] The six folder listings run at the same time.
- [x] The peak worker count stays in the current limit.

## Tests
- [x] The worker observer shows that the files of all types are read in one pool (a file of a later type starts before all files of an earlier type end).
- [x] The existing loader tests, the shuffle and replay property test, and the 2000-file peak worker test pass with no change in result.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.