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
- actor: claude-code
  id: 01m5810a2hjh7t73hz78egx45z
  text: |-
    ### review — findings
    - evidence: review sha 6d957ec~1..6d957ec — 2 findings (2 confirmed, 2 refuted). Tests/FoundationModelsKanbanTests/Observe/HeldStartService.swift:10, Tests/FoundationModelsKanbanTests/Observe/HeldStartService.swift:36
    - next: Remove the second fake. Put the hold on the first start into QuietFolderEvents, or into one shared fake that both suites use, and take currentEventID from that one fake. Then review again.
  timestamp: 2026-10-18T17:29:58.609972+00:00
- actor: claude-code
  id: 01m5810w5fjd2fnksa1dspt43s
  text: |-
    ### finish iteration 2 — findings
    - implement: changed (work in the tree; FolderStreams code landed in a35a913 under ^wphkeqk)
    - test: green — swift test: 1599 passed, 0 failed, 0 skipped
    - commit: 6d957ec
    - review: findings — Tests/FoundationModelsKanbanTests/Observe/HeldStartService.swift:10, Tests/FoundationModelsKanbanTests/Observe/HeldStartService.swift:36 (reuse/reuse: HeldStartService repeats QuietFolderEvents)
  timestamp: 2026-10-18T17:30:17.135668+00:00
- actor: claude-code
  id: 01m581ba6wpgf9375a6yzf1z2g
  text: |-
    Implementation (review findings, reuse/reuse):
    - One FolderEventService fake is in the test target now: QuietFolderEvents, in the new file Tests/FoundationModelsKanbanTests/Observe/QuietFolderEvents.swift (moved out of FolderStreamsTests.swift, with QuietStream). It has one event id counter.
    - The hold of the first start is an option of that fake: `QuietFolderEvents(holdingFirstStartWith: StartHold?)`. The default is no hold. StartHold has the semaphore and the AsyncStream of the old fake: `waitForHeldStart()` and `release()`. The fake records the paths of the held start before it waits, so startCount counts the held start, as before.
    - HeldStartService.swift is deleted. Users changed: FolderStreamsTests.waitingAddsShareOneStream, FolderStreamsPoolTests.heldStartHoldsNoPoolThread, KanbanHostTests.loadStartsWhileWatcherStartWaits. `import Synchronization` is removed from FolderStreamsTests.swift (no Mutex is left there). No text in the repo names HeldStartService now.
    - Note: `swift test --filter Observe` runs no test ("No matching test cases were run"), because a test id holds the suite name, not the folder name. I ran `--filter 'FolderStreamsTests|FolderStreamsPoolTests|BoardWatcherTests|KanbanHostTests'` in its place: 54 tests in 4 suites passed.
    - Acceptance check against HEAD code: FolderStreams is an actor whose `unownedExecutor` is its own DispatchSerialQueue `changes`; each call of `service.currentEventID()`, `service.startStream(...)` and `stream.end()` is in an actor-isolated method (`watchEachFolder`, `startStream`, `endStreamWithNoFolder`), and `removeWithoutWait` sends its end to that queue. FolderStreamsPoolTests holds the first start and proves that 4 x processor count other tasks end while it waits. The full swift test passes. FolderEventWait.timeLimit stays 60 s; no `.timeLimit` trait is in the tests.
  timestamp: 2026-10-18T17:35:59.196813+00:00
- actor: claude-code
  id: 01m581bdwr65a88twjmxvebm60
  text: |-
    ### implement — changed
    - evidence: 5 files — Tests/FoundationModelsKanbanTests/Observe/QuietFolderEvents.swift (new), Tests/FoundationModelsKanbanTests/Observe/HeldStartService.swift (deleted), Tests/FoundationModelsKanbanTests/Observe/FolderStreamsTests.swift, Tests/FoundationModelsKanbanTests/Observe/FolderStreamsPoolTests.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanHostTests.swift. `swift test --filter Observe`: 0 tests matched. `swift test --filter 'FolderStreamsTests|FolderStreamsPoolTests|BoardWatcherTests|KanbanHostTests'`: 54 passed in 4 suites, 0 failed, 0 skipped. Full `swift test` (one process): 1599 passed in 131 suites, 0 failed, 0 skipped. No source warnings (only the build-system note "missing creator for mutated node" of the mlx-swift_Cmlx bundle).
    - next: /review. Both findings and the 3 acceptance items are `- [x]`. Not committed. Task stays in doing.
  timestamp: 2026-10-18T17:36:02.968967+00:00
- actor: claude-code
  id: 01m581fq5tn0ng2ashf2ex5csk
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (8fa55b1); 2 findings, 2 confirmed, 0 refuted — Tests/FoundationModelsKanbanTests/Observe/FolderStreamsTests.swift:210, Tests/FoundationModelsKanbanTests/Observe/QuietFolderEvents.swift:79. The two prior findings (HeldStartService.swift:10 and :36) are fixed: the file is removed, and the hold is now in QuietFolderEvents.
    - next: release the hold on all paths in FolderStreamsTests, FolderStreamsPoolTests and KanbanHostTests; put one shared test gate under StartHold and the other gate helpers where the contract fits.
  timestamp: 2026-10-18T17:38:23.546491+00:00
- actor: claude-code
  id: 01m581gh7fsg0c5qx53ww6yf1r
  text: |-
    ### finish iteration 3 — findings
    - implement: changed — QuietFolderEvents.swift (shared fake, StartHold option), HeldStartService.swift deleted, 3 users updated
    - test: green — swift test: 1599 passed, 0 failed, 0 skipped
    - commit: 8fa55b1
    - review: findings — Tests/FoundationModelsKanbanTests/Observe/FolderStreamsTests.swift:210 (completeness/inverse-operation-coverage: hold released only on the success path), Tests/FoundationModelsKanbanTests/Observe/QuietFolderEvents.swift:79 (reuse/reuse: StartHold repeats the gates in LoadRecorder, CountingKeyReader, GatedEmbedder). Prior findings :10 and :36 fixed.
  timestamp: 2026-10-18T17:38:50.223838+00:00
- actor: claude-code
  id: 01m5823swwt9zydvtg0e4fhwmf
  text: |-
    Implementation (review findings of 2026-10-18 12:36):
    - New shared gate: Tests/FoundationModelsKanbanTests/TestGate.swift (`TestGate`). API: `recordArrival()`, `waitForArrival()` (returns at once after an earlier arrival, can be called many times, a cancel ends it), `release()` (permanent, a second call does nothing), `waitUntilReleased()` (async, throws CancellationError on cancel), `blockUntilReleased()` (sync; a semaphore that each passed thread signals again, so the release stays permanent). Tests: TestGateTests.swift, 5 tests. RED: 5 of 5 failed against an empty scaffold. GREEN: 5 of 5 passed.
    - Moved onto TestGate: StartHold (now `typealias StartHold = TestGate`; QuietFolderEvents calls `recordArrival()` and then `blockUntilReleased()`), LoadRecorder (load start arrival), CountingKeyReader (blocked read arrival; the gate gets no release, so only the cancel ends the wait), GatedEmbedder (arrival count = start count, async release), HeldConsumer (async release), StageOverlapProbe in LoaderTests (the awaited type releases, the held type blocks).
    - Kept separate, with a comment that says why: LockWaitProgress in EventLogTests. It holds no call and waits for nothing; each start must read the release flag and count itself in one lock. ScanRecorder and UnreadableBoardRecorder are streams of observed change values, not gates, so they stay as they are.
    - Release on every path: `defer { hold.release() }` in FolderStreamsPoolTests.heldStartHoldsNoPoolThread and KanbanHostTests.loadStartsWhileWatcherStartWaits; in FolderStreamsTests.waitingAddsShareOneStream the defer is inside the task group body, because the group waits for each child before it ends, also when the body throws. Same cause removed in the other gate users: `defer { consumer.release() }` in KanbanHostTests.closedEngineDoesNotWaitForMovedConsumer, and `defer { embedder.release() }` in the 3 SearchReadinessTests tests. The explicit releases in the bodies stay, because the tests check state before the release.
    - Discovery: the BoardLoader workers are task group tasks on the cooperative pool, so StageOverlapProbe blocks one pool thread until a different worker starts the awaited type (this was the same before the change; the comment now says so).
    - FolderEventWait.timeLimit stays 60 s. No `.timeLimit` trait is in the tests.
  timestamp: 2026-10-18T17:49:21.692735+00:00
- actor: claude-code
  id: 01m5823xsctmvy2bvxtygxsq9y
  text: |-
    ### implement — changed
    - evidence: 10 files — Tests/FoundationModelsKanbanTests/TestGate.swift (new), Tests/FoundationModelsKanbanTests/TestGateTests.swift (new), Tests/FoundationModelsKanbanTests/Observe/QuietFolderEvents.swift, Tests/FoundationModelsKanbanTests/Observe/FolderStreamsTests.swift, Tests/FoundationModelsKanbanTests/Observe/FolderStreamsPoolTests.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanHostTests.swift, Tests/FoundationModelsKanbanTests/Search/SearchReadinessTests.swift, Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift, Tests/FoundationModelsKanbanTests/Events/LoaderTests.swift, Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift. `swift test --filter TestGateTests`: RED 5 failed, GREEN 5 passed. `swift build --build-tests`: 0 errors, 0 warnings. Full `swift test` (one process): 1604 passed in 132 suites, 0 failed, 0 skipped.
    - next: /review. Both findings of 2026-10-18 12:36 are `- [x]`. Not committed. Task stays in doing.
  timestamp: 2026-10-18T17:49:25.676066+00:00
- actor: claude-code
  id: 01m5828j1mcc4dkwrrphdvrd9e
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (e14c5ee). 10 files reviewed. 0 findings, 0 confirmed, 1 refuted. All prior findings are checked. The two prior findings are fixed: FolderStreamsTests.swift, FolderStreamsPoolTests.swift and KanbanHostTests.swift use `defer { hold.release() }`; StartHold is now `typealias StartHold = TestGate`, and the shared TestGate (Tests/FoundationModelsKanbanTests/TestGate.swift) replaces the gate copies in LoaderTests, SearchReadinessTests, KanbanHostTests and BoardLocatorTests. EventLogTests says in a comment why its record does not use TestGate.
    - next: none. The task is in done.
  timestamp: 2026-10-18T17:51:57.492220+00:00
- actor: claude-code
  id: 01m58290zytc9r63gyr2tqkt0x
  text: |-
    ### finish iteration 4 — clean
    - implement: changed — TestGate.swift (new), TestGateTests.swift (5 tests), StartHold = TestGate, 5 helpers use TestGate, hold released on every path with defer
    - test: green — swift test: 1604 passed, 0 failed, 0 skipped
    - commit: e14c5ee
    - review: clean — 0 findings; prior findings FolderStreamsTests.swift:210 and QuietFolderEvents.swift:79 fixed. Task is in done.
  timestamp: 2026-10-18T17:52:12.798979+00:00
position_column: done
position_ordinal: ff9780
title: Do not block the cooperative pool with the FSEvents calls of FolderStreams
---
## What
`FolderStreams.add`, `remove` and `replaceStream` call `FSEventsGetCurrentEventId`, `FSEventStreamCreate`, `FSEventStreamStart` and `FSEventStreamStop`. Each call is a synchronous Mach message to fseventsd. The calls run on a thread of the Swift cooperative pool, inside the `state` lock. When fseventsd is slow to answer, each pool thread blocks in `mach_msg`, and the full process stops: tasks that do not use FSEvents also cannot run.

## Evidence (^yf3bpss, 2026-10-16)
- A full `swift test` run with no test time limits stopped at 0% CPU. `sample` showed each `com.apple.root.default-qos.cooperative` thread in `FSEventsGetCurrentEventId > mach_msg` or `FSEventStreamStart > mach_msg`. `swift-inspect dump-concurrency` showed 1033 tests that waited for a `WatcherBudget` slot, and slot holders that waited for batches.
- When the test process stopped, fseventsd answered other clients again.

## Acceptance Criteria
- [x] No FSEvents call of `FolderStreams` runs on a thread of the cooperative pool. The calls run on a thread or queue of their own, and the async caller waits with no blocked pool thread.
- [x] A test proves it. Example: a fake FSEvents seam that blocks the start, and many tasks that do other work and must all end while the start is blocked.
- [x] The full `swift test` run passes.

## Review Findings (2026-10-18 12:28)

> Scope: `review sha 6d957ec~1..6d957ec` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Tests/FoundationModelsKanbanTests/Observe/HeldStartService.swift:10` `reuse/reuse` — HeldStartService is a near-copy of the existing test fake QuietFolderEvents. It repeats the FolderEventService conformance and the quiet stream, and only adds a hold on the first start. The hold should be a parameter of QuietFolderEvents, not a second fake. Two fakes of one protocol drift apart. Give QuietFolderEvents an optional hold on the first start (a semaphore and an AsyncStream, as in HeldStartService), or move one shared fake into a common test file and have both suites use it. Then delete the second fake.
- [x] `Tests/FoundationModelsKanbanTests/Observe/HeldStartService.swift:36` `reuse/reuse` — HeldStartService.currentEventID repeats the body of QuietFolderEvents.currentEventID. The fake should reuse the existing quiet fake, or the shared fake that replaces it, and not define its own event id counter. Take the event id from the shared fake (see the finding on the class at line 10), so that one implementation provides the id for both suites.

## Review Findings (2026-10-18 12:36)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 5 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> ⚠️ tool rule 'code-hygiene/disallowed-constructs-swift' declined an item — it judged the rest of the code, and this it could not judge:
> disallowed-constructs-swift found no file at Tests/FoundationModelsKanbanTests/Observe/HeldStartService.swift, so its constructs are unread

> ⚠️ tool rule 'code-hygiene/function-length-swift' declined an item — it judged the rest of the code, and this it could not judge:
> function-length-swift found no file at Tests/FoundationModelsKanbanTests/Observe/HeldStartService.swift, so its bodies are unread

> ⚠️ tool rule 'code-hygiene/idioms-swift' declined an item — it judged the rest of the code, and this it could not judge:
> idioms-swift found no file at Tests/FoundationModelsKanbanTests/Observe/HeldStartService.swift, so its declarations are unread

> ⚠️ tool rule 'code-hygiene/magic-numbers-swift' declined an item — it judged the rest of the code, and this it could not judge:
> magic-numbers-swift found no file at Tests/FoundationModelsKanbanTests/Observe/HeldStartService.swift, so its literals are unread

> ⚠️ tool rule 'code-hygiene/missing-docs-swift' declined an item — it judged the rest of the code, and this it could not judge:
> missing-docs-swift found no file at Tests/FoundationModelsKanbanTests/Observe/HeldStartService.swift, so its declarations are unread

- [x] `Tests/FoundationModelsKanbanTests/Observe/FolderStreamsTests.swift:210` `completeness/inverse-operation-coverage` — The hold is released only on the success path. If EventLogTests.waitUntil throws at line 209, hold.release() never runs. The child task blocked in StartHold.wait() (a DispatchSemaphore) cannot be cancelled, so withThrowingTaskGroup cannot finish. The test then hangs instead of reporting the failure. Release the hold on every path. Use `defer { hold.release() }` after the hold is created, or release before the wait in a catch block. Apply the same guard in Tests/FoundationModelsKanbanTests/Observe/FolderStreamsPoolTests.swift:40 and Tests/FoundationModelsKanbanTests/Tool/KanbanHostTests.swift:367, so a failed wait does not leave a blocked thread.
- [x] `Tests/FoundationModelsKanbanTests/Observe/QuietFolderEvents.swift:79` `reuse/reuse` — StartHold reimplements a test gate that already exists in several test helpers: an AsyncStream signals that the blocked call began, and a blocking wait lets the test release it. The same shape appears in LoadRecorder (loadStartSignals, waitForLoadStart), CountingKeyReader (blockedReads, waitForBlockedRead), and GatedEmbedder (waitForStart). Each copy carries its own signal stream, sink, and release logic, so a fix to the gate must be made in each copy. Extract one shared test gate, for example a generic `StartGate` with `yieldArrival()`, `waitUntilReleased()`, and `waitForArrival()`, in a shared test file. Make StartHold a typealias or thin wrapper over it, and move the other helpers onto it where their contract fits. If a helper's contract does not fit (for example, GatedEmbedder is an embedder, not a generic hold), keep it separate and say so in a comment.
