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
- actor: wballard
  id: 01m4cgzg5z7tctyr9gy3kgqmxz
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (6c990b3); 2 findings, 2 confirmed, 0 refuted — Sources/FoundationModelsKanban/Observe/LiveGraph.swift:121, Tests/FoundationModelsKanbanTests/Observe/BoardWatcherTests.swift:180
    - next: implement the 2 open items in "Review Findings (2026-10-07 20:08)", then review again.
  timestamp: 2026-10-08T01:10:25.215467+00:00
- actor: wballard
  id: 01m4cgzv687nrg6t88j448t69m
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 7 files (Observe/BoardWatcher.swift, Observe/LiveGraph.swift, Tool/Commit.swift, Tool/KanbanGraph.swift, Events/EventLog.swift, BoardWatcherTests.swift, KanbanGraphTests.swift)
    - test: green — swift test 3 runs, 855 passed each; build warnings only the 2 accepted kinds
    - commit: 6c990b3
    - review: findings — Sources/FoundationModelsKanban/Observe/LiveGraph.swift:121, Tests/FoundationModelsKanbanTests/Observe/BoardWatcherTests.swift:180
  timestamp: 2026-10-08T01:10:36.488911+00:00
- actor: wballard
  id: 01m4ch8tjw5tqxw1161ehejgh4
  text: |-
    Review findings (2026-10-07 20:08) fixed.

    1. `reuse/reuse` (LiveGraph.swift): new private `changedRefs(in current: [LocalRef: FileSignature?]) -> Set<LocalRef>` holds the one signature-compare filter. `changedRefs()` gives it the disk signatures of the union of the disk refs and the recorded refs. `changedRefs(among:)` gives it `fileSignatures(of:)`, so the per-ref signature read also is not repeated any more.

    2. `test-integrity/no-test-cheating` (BoardWatcherTests.swift):
    - New internal test seams: `BoardWatcher.isRunning` (the FSEvents stream is not stopped) and `KanbanGraph.activeWatch` (the `BoardWatch` while the state is `.watching`, else nil). `close()`, `applyBatch` and `moveWatchToBoardDirectory(of:)` now use `activeWatch`, so the `case .watching(let watch)` match is in one place only.
    - The close test reads the watch before `close()`, then asserts with no wait: the watcher does not run (`try #require`), the consumer task is cancelled, and the engine has no active watch. Then the behavior check, ordered by the probe batch: the recorder has no batch. The stopped stream is the proof; the probe check only confirms it.
    - Other tests in the file: the `.kanban/`-appears test passed even when the watcher did not move, because a watch on the repo root also sees `.kanban/`. It now asserts that the first watch is on the root, and after the load batch (a definite signal) that the active watch is on `.kanban/` and the root watcher does not run. The own-write test is ordered by one stream: FSEvents gives the events of one stream in order, and the consumer applies batches one at a time, so the own-write batch is done before the marker batch. The other tests wait for a positive batch or use no FSEvents.
    - The old suggestion (a second probe write) does not remove the race, because two FSEvents streams have no order between them. The direct seam check does.

    Red proof: `close()` changed for one run to not call `watch?.end()`. `swift test --filter BoardWatcherTests/closeStopsWatcher` failed at once: "Expectation failed: await !watch.watcher.isRunning". `close()` restored.
  timestamp: 2026-10-08T01:15:30.780239+00:00
- actor: wballard
  id: 01m4ch8y19734h37q28q4c9125
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/Observe/LiveGraph.swift, Sources/FoundationModelsKanban/Observe/BoardWatcher.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Tests/FoundationModelsKanbanTests/Observe/BoardWatcherTests.swift. RED: compile failure on missing `activeWatch`/`isRunning`; GREEN: `swift test --filter BoardWatcherTests` 7/7. Red proof: close() without end() -> closeStopsWatcher failed at `await !watch.watcher.isRunning`; restored. `swift test` x3 (`--skip-build` on runs 2 and 3): 855 tests in 51 suites passed each run; only build warning is the accepted mlx-swift "missing creator". periphery scan (--retain-public, tests indexed and report-excluded): No unused code detected. 2 of 2 findings checked.
    - next: /review
  timestamp: 2026-10-08T01:15:34.313437+00:00
- actor: wballard
  id: 01m4che9yfndpm1xnq5w5jwrr3
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (e5c3932). 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. 4 files reviewed. All prior Review Findings items are checked.
    - next: None. The task is in done.
  timestamp: 2026-10-08T01:18:30.351982+00:00
- actor: wballard
  id: 01m4chegj18grx9b8geakgk5r5
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 4 files (Observe/LiveGraph.swift, Observe/BoardWatcher.swift, Tool/KanbanGraph.swift, BoardWatcherTests.swift); 2/2 findings checked; red proof for close test
    - test: green — swift test 3 runs, 855 passed each; build warnings only the 2 accepted kinds
    - commit: e5c3932
    - review: clean — 0 findings
  timestamp: 2026-10-08T01:18:37.121470+00:00
depends_on:
- 01M4B3ZDK527CRVKQQRT87RGHJ
- 01M4B4ADV9EPW7N9VGBVBVV8WM
- 01M4B4180ZBKH8RSE3FA9REHS7
position_column: done
position_ordinal: ac80
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

## Review Findings (2026-10-07 20:08)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/Observe/LiveGraph.swift:121` `reuse/reuse` — changedRefs(among:) repeats the signature-compare filter of changedRefs() instead of sharing it. Both compare the current signature of a ref with signatures[ref]. A later change to the rule would have to be made in two places. Extract one private helper that takes a map of current signatures and returns the refs whose signature differs from the recorded one, and call it from both changedRefs() and changedRefs(among:).
- [x] `Tests/FoundationModelsKanbanTests/Observe/BoardWatcherTests.swift:180` `test-integrity/no-test-cheating` — The close test checks that no batch was applied right after the probe watcher sees the write. The graph's own FSEvents batch can arrive later than the probe's batch, so the check can pass even when close() does not stop the graph's watcher. The assertion is timing-dependent and does not prove what the test name says. After the probe batch, wait for a fixed signal that the graph's stream has had its chance to deliver, for example a second probe write that the graph would apply and wait for that batch on the probe, then assert the recorder is still empty. Alternatively assert on the watch state directly through an internal test seam.
