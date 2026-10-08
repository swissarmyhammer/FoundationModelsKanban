---
comments:
- actor: wballard
  id: 01m4cg2vabvbp10fyq6a27ts1v
  text: |-
    Research done.
    - `KanbanGraph` loads only the current board today (related boards come with ^BoardLocator task). So one watcher per loaded board means one watcher now; the code keeps the watcher per board so the cross-repo work can add more.
    - `KanbanGraph` has no `close()` yet; this task adds it (plan.md §7.2).
    - Plan: `BoardWatcher` (actor) wraps an FSEvents stream with `kFSEventStreamCreateFlagFileEvents` and gives the paths of each group as one `[URL]` in an `AsyncStream`. The stream retains a small sink object through the context retain/release callbacks; the watcher stops the stream in `stop()` and in its deinit.
    - `KanbanGraph` starts the watcher before the first load (so no change between load and watch is lost), on `.kanban/` or, when it is not there, on the repo root. One consumer task per watcher sends each batch through the serial gate.
    - Filter: `LiveGraph.changedRefs(among:)` keeps only the node files whose signature differs from the recorded one; `changedRefs()` (full compare) moves from Commit.swift to LiveGraph.swift so that the watcher reuses it when `.kanban/` appears or FSEvents says MustScanSubDirs.
    - Existing test `KanbanGraphTests.boardStaysInMemory` writes a task after the first call and expects the old graph. With a live watcher that is no longer true, so the test calls `close()` before the write; its claim (the board stays in memory and is not loaded again per call) stays the same.
  timestamp: 2026-10-08T00:54:46.347284+00:00
- actor: wballard
  id: 01m4cgqg4aaf4nvtt8pwd17dcd
  text: |-
    Implementation landed (TDD: 5 acceptance tests RED on assertions with stubs, then GREEN; then 2 more RED/GREEN tests for the lost-events path).

    Design notes for the next agent:
    - `BoardWatcher` (actor, Observe/BoardWatcher.swift): FSEvents stream with `kFSEventStreamCreateFlagFileEvents | UseCFTypes`, latency 0.05 s, `SinceNow`, own serial dispatch queue. `BatchSink` (final class) is the context `info`; the stream retains it through the context retain/release callbacks. `stop()` and `isolated deinit` stop, invalidate, and release the stream, and finish `batches`. When a group has MustScanSubDirs / UserDropped / KernelDropped, the batch also holds the watched directory.
    - `KanbanGraph`: `WatchState` enum (`notStarted`, `watching(BoardWatch)`, `closed`). The watcher starts in `loadedSession()` BEFORE `LiveGraph.load`, so no change between load and watch is lost. One consumer `Task` per watcher (weak self) sends each batch through the serial gate (`receive` -> `gate.run` -> `applyBatch`). A batch that fails is logged with swift-log; the commit check still catches the change.
    - Repo with no `.kanban/`: the watcher watches the repo root. On a batch, when `.kanban/` now exists, a new watcher starts on `.kanban/`, the old one stops, and the batch gets `log.directory` added, so it compares each file.
    - `CommitSession.apply(watchedPaths:)`: when a path is the board directory, full compare (`LiveGraph.changedRefs()`, moved from Commit.swift to LiveGraph.swift); else `LiveGraph.changedRefs(among:)` (signature filter). Then `live.apply(changedPaths:)` and `updateSearch()`. `EventLog.isBoardDirectory(at:)` is now internal.
    - `close()` stops the watcher, cancels the consumer task, and awaits it. After it returns, no apply can happen.
    - Test hook: `LiveGraphObserver.didApply(changedPaths:)`, injected through the internal init (`observingBatchesWith:`). Tests wait on its `AsyncStream` with a 10 s limit (not a pass rule). The close test uses a second `BoardWatcher` as a probe for a definite signal.
    - `KanbanGraphTests.boardStaysInMemory` now calls `close()` before its write (with a live watcher the old assertion is no longer true). `KanbanGraphTests.boardResponse(withTask:titled:)` is a new shared helper; `queryOnFixtureLogs` uses it.
    - Related boards: none are loaded yet (BoardLocator task). The watcher code is per board, so that task must add one `BoardWatch` for each related board it loads.
    - Not in this card: the change feed per batch (plan.md §5.6, change feed) belongs to the Subscriptions task. `LiveGraph.apply` returns the new event ids; `CommitSession.apply(watchedPaths:)` discards them for now.
  timestamp: 2026-10-08T01:06:03.018977+00:00
- actor: wballard
  id: 01m4cgqjnmykf8fvf7tkqt121n
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsKanban/Observe/BoardWatcher.swift (new), Sources/FoundationModelsKanban/Observe/LiveGraph.swift, Sources/FoundationModelsKanban/Tool/Commit.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Sources/FoundationModelsKanban/Events/EventLog.swift, Tests/FoundationModelsKanbanTests/Observe/BoardWatcherTests.swift (new), Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift. `swift test --filter BoardWatcherTests`: 7/7 pass. `swift test`: 855 tests in 51 suites pass; only the known SwiftPM "missing creator" warning. periphery scan: No unused code detected.
    - next: /review
  timestamp: 2026-10-08T01:06:05.620466+00:00
depends_on:
- 01M4B3ZDK527CRVKQQRT87RGHJ
- 01M4B4ADV9EPW7N9VGBVBVV8WM
- 01M4B4180ZBKH8RSE3FA9REHS7
position_column: doing
position_ordinal: '80'
title: 'Live graph: FSEvents watcher and batches'
---
## What
The FSEvents watcher that drives the live graph. The basis is plan.md §5.6 and §12 item 25. Applying the changed files is in the separate task "Live graph: apply changed files to the graph".
- `Sources/FoundationModelsKanban/Observe/BoardWatcher.swift`: an FSEvents stream with file-level events on `.kanban/` of each loaded board, for the life of `KanbanGraph`. Each board that `KanbanGraph` loads (the current board and each related board) gets its own watcher.
- A repo with no `.kanban/` yet: watch the repo directory until `.kanban/` appears, then load the board and move the watcher to `.kanban/`.
- Batches: the changed paths of one FSEvents group go to the serial gate as one batch, and `LiveGraph.apply` runs inside the gate. Ignore a file whose signature equals the recorded signature (own writes, repeated events). After a batch, update the searcher of the board.
- `KanbanGraph.close()`: stop all watchers.

## Acceptance Criteria
- [x] With no subscriber, a manual edit of a task log changes the result of a later query (wait for the batch with an async expectation and a timeout).
- [x] The tool's own write makes no `apply` call (a test counter on `apply`).
- [x] A `.kanban/` directory that appears after the first call is loaded and watched; after `close()`, a file change makes no `apply` call.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Observe/BoardWatcherTests.swift`.
- [x] Run `swift test --filter BoardWatcherTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.