---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m53mdj7hxsdn9xa2p0hvpz19
  text: |-
    Research:
    - `FolderStreams.add` runs in `BoardWatcher.init`, which `StartedWatcher.init`, `BoardWatcher.started`, `BoardEngine.load`, `BoardEngine.movedWatch`, `KanbanHost.makeUnloadableWatch` and `KanbanHost.makeFolderWatch` call. All of them are sync now, so all of them must become async when `add` becomes async.
    - `FolderStreams.remove` runs in `BoardWatcher.stop()` (async, callers already await) and in the `isolated deinit` of `BoardWatcher` (cannot await).
    - Plan: make `FolderStreams` an actor whose executor is its own serial `DispatchSerialQueue`. Then each FSEvents call runs on that queue thread, and an async caller suspends with no blocked pool thread. Put the FSEvents calls behind a `FolderEventService` seam, so that a test can give a start that blocks.
    - KanbanHost: `watch(_:)`, `markUnloadable` and `recordBoard` become async. After each await, the host must check again for a watch that a parallel call made, and for `close()`.
    - WatcherBudget: `SerialGate(slots: 16)`, one slot for each test case. No test takes two slots (no nested suite has the trait twice), and no slot holder waits for a test that waits for a slot. The 1033 waiters waited only because the slot holders could not run: their pool threads were blocked in FSEvents calls.
    - ScanCacheTests.readsRunNoGit: the router drops events whose id is not after `FSEventsGetCurrentEventId()` at the add. That id is not a barrier: fseventsd gives an id when it reads the kernel event, so a file change from before the add can get a later id. A late `.repo`/`.place` event of the setup then expires the scan index, and the next read scans and reads keys again. This is a real defect: the scan cache takes an event as a change, also when the files are the same as the scan read them. The live graph already compares file signatures for this reason.
  timestamp: 2026-10-17T00:33:03.729785+00:00
- actor: claude-code
  id: 01m53qgb2tnmrmtz1ttzedtdyq
  text: |-
    Progress:
    - FolderStreams is now an actor on its own DispatchSerialQueue executor; FSEvents calls go through the new FolderEventService seam (Sources/FoundationModelsKanban/Observe/FolderEventService.swift). BoardWatcher.init, StartedWatcher.init, BoardWatcher.started and the KanbanHost watch helpers are async; the host checks its state again after each watcher start (keepPlaceWatch, keepKnownFolder, markUnloadable).
    - RED: the new FolderStreamsPoolTests test hung with the old sync FolderStreams (all pool threads blocked). GREEN: it passes in 0.03 s.
    - Scan cache: new ScanMarks (Sources/FoundationModelsKanban/CrossRepo/ScanMarks.swift). A scan records the file state of each repo before it reads keys; a change whose files are the same does not expire the index. ScanMarksTests: 3 RED, then 25/25 GREEN with ScanChangeTests.
    - Full run 1 after these changes: no blocked thread (sample shows only the main thread and one idle worker). It stopped at 0% CPU with one test waiting: PathRefCacheTests.firstCommitFindsBoard waits in ScanRecorder.waitForChange(.commits) forever. Cause: a late setup event (`.repo` of the repo, from before the watcher add) makes the host forget the path-ref record and stop its watcher, so the `.commits` change never comes. The same late-event defect makes PathBoardKeyTests.nodeReadsPathBoard give node null (the record of the path board is forgotten).
    - Other failures in run 1 (also in the earlier runs of ^yf3bpss, so not new): KanbanHostTests.boardsLoadInParallel and two CrossRepoParallelLoadTests. Cause: BoardEngine.load waits for the watcher start, and the starts of one host run one at a time on FolderStreams, so the second load starts after the first load ends.
    - Next: path-ref records compare a RepoMark; ScanRecorder.waitForChange asks the condition after each change; BoardEngine.load starts the watcher and the load at the same time and compares each file one time after the watcher started.
  timestamp: 2026-10-17T01:27:00.442765+00:00
- actor: claude-code
  id: 01m5417sf9pekfmy79p0jmb6cx
  text: 'Finding (diagnostic log of a full run, then removed): two full runs passed (1583 tests in 129 suites), but some runs stop with 1 to 4 tests that wait forever for one watcher event (CrossRepoReadTests.unknownKeyScansAgain, RemoteAssigneeFeedTests, BoardWatcherTests.manualEditChangesLaterQuery, ScanCacheTests.newRepoFolderIsFound, ReplacedRepoTests.viewReadsNewRepo). No thread is blocked. The log of the stuck test shows that its stream (started with a past `since`) gave no event at all after the start: the move of `e-new-lib` into the watched place never came. fseventsd logs, for each stream that starts with a past `since`: "scan_old: bailing out because device mounted @ ... has dls 0x0 and dls->fci 0x0" — fseventsd keeps no history on this volume, so a history replay gives nothing, and a change during the history scan is lost. The design of FolderStreams depends on the history replay ("the new stream starts at the last event that the router got, so FSEvents gives it each later event from its history"). That is the defect that loses events. Fix: start each stream at "now" (no history); before the old stream stops, flush it (FSEventStreamFlushSync) so that it gives each event that occurred before; drop a repeated event id with a bounded set of recent ids (no HistoryDone state); give a new folder one batch with its folder after the add, so that its receiver compares its files.'
  timestamp: 2026-10-17T04:17:06.025143+00:00
- actor: claude-code
  id: 01m547h4vnse0ec200bk5xv1zz
  text: |-
    ### implement — stuck
    - Done (all acceptance items of the card): FolderStreams is an actor on its own DispatchSerialQueue; each FSEvents call goes through FolderEventService on that queue; async callers wait with no blocked pool thread. Test FolderStreamsPoolTests (held fake start): RED = hang with the old sync code, GREEN = 0.03 s.
    - Also fixed: late FSEvents events (ScanMarks for the scan index, PathRefRecord for path refs; ScanCacheTests.readsRunNoGit is a real defect, fixed); ScanRecorder.waitForChange asks the condition after each change; BoardEngine.load starts the watcher and the load at the same time and compares each file one time after; two calls share one place-watcher start; FolderStreams starts each stream at "now" (no history replay, which fseventsd cannot give here: "scan_old: bailing out ... dls 0x0"), flushes the old stream before it stops, and drops repeated event ids with a bounded set; BoardEngine.readsRoot tells the host before it retires.
    - WatcherBudget: no defect. 16 slots, one per test case, no nested slot, no holder waits for a waiter.
    - Evidence: `swift build --build-tests`: 0 errors, 0 source warnings. Full `swift test`: 2 runs passed (1583 tests in 129 suites, 0 issues); 4 runs stopped at 0% CPU with 1 to 4 tests that wait for one FSEvents event that never comes (last run: 1568 passed, 0 failed, AgentPlanPostTests.watcherBatchPostsNothing and RemoteAssigneeFeedTests.deleteOfRemoteAssigneeGivesUpdate waiting). A standalone probe outside the package shows the same: FSEventStreamFlushSync gives 0 of 5 events; a 15 s wait gives 4 of 5.
    - Blocker: with no test time limit, a watcher test waits forever when FSEvents gives no event. A person must decide the rule (new task ^wphkeqk). A runaway sourcekit-lsp background index (child of `sah`) builds recursive `.build/index-build/checkouts/...` folders in this repo during the runs.
    - next: the user decides ^wphkeqk; then run the full `swift test` again.
  timestamp: 2026-10-17T06:07:04.053891+00:00
- actor: claude-code
  id: 01m547ja7s0apkr4bpn9ewtemf
  text: |-
    ### finish iteration 1 — stuck
    - implement: stuck — FolderStreams is an actor on its own serial queue, FSEvents calls go through FolderEventService; new FolderStreamsPoolTests (passes in 0.03 s, hung with the old code); ScanMarks and PathRefRecord fix ScanCacheTests.readsRunNoGit; ScanRecorder.waitForChange fix; shared watcher start; streams start at now. 7 new files, 18 changed. swift build --build-tests: 0 errors, 0 source warnings.
    - test: full swift test does not pass each time. 2 runs 1583/1583 passed (earlier stream design). 5 runs stopped with 1 to 4 tests that wait for an FSEvents event that does not come (last run, final code: 1568 passed, 0 failed, 2 waiting).
    - commit: not run. review: not run.
    - next: the user decides ^wphkeqk (how a watcher test ends when FSEvents gives no event, with no time limit). Then the full swift test runs again.
  timestamp: 2026-10-17T06:07:42.329089+00:00
position_column: doing
position_ordinal: '8380'
title: Do not block the cooperative pool with the FSEvents calls of FolderStreams
---
## What
`FolderStreams.add`, `remove` and `replaceStream` call `FSEventsGetCurrentEventId`, `FSEventStreamCreate`, `FSEventStreamStart` and `FSEventStreamStop`. Each call is a synchronous Mach message to fseventsd. The calls run on a thread of the Swift cooperative pool, inside the `state` lock. When fseventsd is slow to answer, each pool thread blocks in `mach_msg`, and the full process stops: tasks that do not use FSEvents also cannot run.

## Evidence (^yf3bpss, 2026-10-16)
- A full `swift test` run with no test time limits stopped at 0% CPU. `sample` showed each `com.apple.root.default-qos.cooperative` thread in `FSEventsGetCurrentEventId > mach_msg` or `FSEventStreamStart > mach_msg`. `swift-inspect dump-concurrency` showed 1033 tests that waited for a `WatcherBudget` slot, and slot holders that waited for batches.
- When the test process stopped, fseventsd answered other clients again.

## Acceptance Criteria
- [ ] No FSEvents call of `FolderStreams` runs on a thread of the cooperative pool. The calls run on a thread or queue of their own, and the async caller waits with no blocked pool thread.
- [ ] A test proves it. Example: a fake FSEvents seam that blocks the start, and many tasks that do other work and must all end while the start is blocked.
- [ ] The full `swift test` run passes.