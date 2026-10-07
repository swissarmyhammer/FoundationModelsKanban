---
comments:
- actor: wballard
  id: 01m4bfen3wyrpy9f0680yy8dy0
  text: |-
    Research:
    - `Graph.update(with:)` already resolves each local edge to a slot when the target is there, and keeps a `waiting` index so that a target that comes later resolves the edge. Thus the join of a stage is: insert the nodes of the stage in a fixed order. Same-stage edges (tag `renamedTo`, task `dependsOn`) resolve through `waiting` at the end of the stage. A remote ref and a missing target stay unresolved.
    - Slots depend on the insert order. For equal graphs with 1 and 8 workers, the loader sorts the nodes of each stage by the text of the local ref before the insert.
    - `Graph` is not `Equatable`. The equality test needs a synthesized `Equatable` conformance (all stored properties are Equatable).
    - `EventLog.nodeRefs(ofType:)` is private and gives the refs of a node directory (a missing directory gives none). The loader needs it, so it becomes internal. The board stage has the one ref `.board`; a missing `board.jsonl` gives a log with no node.
    - The k-way merge uses `Heap` from swift-collections `HeapModule` (the package is already a dependency; only the product is new).
    - `TemporaryDirectory` and `ReplayTests.line(atStep:patch:)` in the test target give the fixture helpers.
  timestamp: 2026-10-07T15:24:30.204301+00:00
- actor: wballard
  id: 01m4bfm2bcf8b6mmpcc89k31r2
  text: |-
    Implementation landed (TDD: RED was a compile failure, `BoardLoader` not found; then GREEN).
    - `Events/Loader.swift`: `BoardLoader(reading:withWorkers:reportingTo:)` with `load() async throws(EventLogError) -> LoadedBoard` (`graph`, `events`). `stageOrder` = board, actor, column, tag, task, comment. Each stage: a `WorkQueue` (a `Mutex<ArraySlice<LocalRef>>`), and `min(workerCount, files)` workers in a `withTaskGroup` that return `Result<[StagedLog], EventLogError>`. A worker that fails empties the queue. The join inserts the nodes of a stage in the sort order of the ref text, so slots do not depend on the worker count. `EventMerge` does the k-way merge with `Heap` (ties by list index).
    - `LoaderWorkerObserver` protocol (`workerDidStart`/`workerDidFinish`): the test seam for the peak counter. The default is `nil`.
    - `Graph` now conforms to `Equatable` (synthesized), for the equality criterion.
    - `EventLog.nodeRefs(ofType:)` is now internal (was private).
    - `Package.swift`: the target uses the `HeapModule` product of swift-collections (the package was already a dependency).
    - Swift Testing does not allow `#require` inside `#require` ("recursive expansion of macro"); the test unwraps in steps.
    - The peak test uses `min(4, activeProcessorCount)` workers, because workers can only run at the same time on different processors.
    - Periphery (`periphery scan --retain-public -- --build-system native`) reports no finding in the changed files. Its 4 findings are in `GraphQL/Errors.swift` (assign-only properties `code`, `message`, `path`, `extensions`). That file existed before this task, and this task does not change it.
  timestamp: 2026-10-07T15:27:27.596743+00:00
- actor: wballard
  id: 01m4bfm7hknkg5x8btwxr9713s
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/Events/Loader.swift (new), Tests/FoundationModelsKanbanTests/Events/LoaderTests.swift (new), Sources/FoundationModelsKanban/Model/Graph.swift, Sources/FoundationModelsKanban/Events/EventLog.swift, Package.swift. `swift test --filter LoaderTests`: 9 tests passed. `swift test`: 302 tests in 18 suites passed, 0 compiler warnings.
    - next: /review
  timestamp: 2026-10-07T15:27:32.915786+00:00
- actor: wballard
  id: 01m4bfs4qdhj054w82crxsynh7
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (3cf3efb). 0 findings, 0 confirmed, 0 refuted. 7 validator passes attempted, 0 failed. 5 files reviewed. 4 .kanban files not reviewed because .reviewignore excludes them.
    - next: none. The task is in done.
  timestamp: 2026-10-07T15:30:13.869758+00:00
- actor: wballard
  id: 01m4bfsafr251zb376kp9af8kh
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 5 files (Events/Loader.swift, LoaderTests.swift, Model/Graph.swift, Events/EventLog.swift, Package.swift)
    - test: green — swift test, 302 passed, 0 warnings
    - commit: 3cf3efb
    - review: clean — 0 findings
  timestamp: 2026-10-07T15:30:19.768173+00:00
depends_on:
- 01M4B3XB2P4CK66JYADZWD88DR
- 01M4B3X08THVXHAJEQ4Z8PDB4H
position_column: done
position_ordinal: 8f80
title: 'Parallel loader: stages, work queue, join'
---
## What
Load one board from disk into a `Graph`. The basis is plan.md §5.3 (The parallel loader) and §12 item 23.
- `Sources/FoundationModelsKanban/Events/Loader.swift`: six stages in entity order: board, actors, columns, tags, tasks, comments.
- Work queue: a stage puts its files in a queue; a `TaskGroup` with `ProcessInfo.activeProcessorCount` workers (configurable for tests) takes files until the queue is empty. Each worker folds one node with `Replay`. A barrier ends each stage.
- Join at the end of each stage: change each stored ref to a slot of an earlier stage. Tag `renamedTo` and task `dependsOn` resolve at the end of their own stage. A missing or cross-board target stays unresolved.
- Global event list: a k-way merge by event `id` of the sorted event lists of all files.
- A missing directory (for example no `comments/`) is an empty stage.

## Acceptance Criteria
- [x] A load with 1 worker and a load with 8 workers give equal graphs and equal global event lists.
- [x] After the load, each edge to a node in the board is a slot; a cross-board `dependsOn` stays unresolved.
- [x] With 2000 task files and N workers, the peak number of workers that run at the same time equals N (a test counter records the peak).

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Events/LoaderTests.swift`: write fixture logs with `EventLog`, then load.
- [x] Run `swift test --filter LoaderTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.