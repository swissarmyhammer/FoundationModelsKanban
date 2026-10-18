---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m547jk47r31726n9dxjn26rg
  text: |-
    ### finish iteration 1 — stuck
    - no step ran. The task says "Decide". The user must choose how a watcher test ends when FSEvents gives no event, with no time limit.
    - next: the user picks a rule. Then /finish can run the task.
  timestamp: 2026-10-17T06:07:51.431830+00:00
- actor: claude-code
  id: 01m55wrjdn7rbqt4tfv24b6bkj
  text: |-
    ### decision — user
    - The user said: "well that will need some time limit".
    - Decision: a wait for an FSEvents event in a watcher test has a time limit. When the limit ends, the test fails with a clear message (the path and the change it waited for). The run continues.
    - Scope: only the wait helpers that wait for an FSEvents event or batch. One shared constant. No `.timeLimit` traits on suites or tests come back. Other waits (locks, search readiness, loads) stay with no time limit.
    - next: /implement adds the limit to the FSEvents wait helpers, then the full swift test runs.
  timestamp: 2026-10-17T21:37:21.845160+00:00
- actor: claude-code
  id: 01m55zeht95hq7zgd2a6xwqpjv
  text: |-
    Research:
    - 25 waits with no time limit wait for an FSEvents event: 8 shared helpers (BoardWatcherTests.hasBatch and .query, CrossRepoReadTests.becomesReady, CrossRepoReadinessCacheTests.task(_:becomesReady:), ScanRecorder.waitForChange, PathRepo.replace, UnreadableBoardRecorder.waitForChange, SubscriptionTests.events) and 17 inline waits (FolderStreamsTests, BoardWatchTests, AgentPlanPostTests, ChangeFilterTests, KanbanHostTests.movedEngineAppliesNoFileOfNewRepo with EventLogTests.waitUntil, and subscription waits in SubscriptionTests, SharedShortIDTests, UnreadableRelatedBoardTests, RemoteAssigneeFeedTests, CrossRepoActorTests).
    - HEAD had Observe/StreamWait.swift (10 s limit, gave nil). The ^yf3bpss work deleted it. The new helper is Observe/FolderEventWait.swift: one constant `timeLimitSeconds = 60`, and `value(waitingFor:at:within:of:)` throws FolderEventTimeout with the change and the path.
    - Design: the wait runs in a child task of a task group, and a second child sleeps for the limit. A cancel of a pending AsyncStream read ends the stream, but on success no read is open, so a later wait on the same stream works (test valueEndsWaitAndStreamStaysUsable).
    - Build blocker found and removed: `.build/checkouts/tree-sitter-php/.build/index-build/...` (a recursive index build of sourcekit-lsp, child of `sah serve`, cwd this repo) made SwiftPM stop with "File name too long". I removed only that nested `.build` folder.
    - TDD: FolderEventWaitTests RED (stub with no limit: "an error was expected but none was thrown"), then GREEN (2/2 pass, 0.103 s).
  timestamp: 2026-10-17T22:24:19.273433+00:00
- actor: claude-code
  id: 01m562p15pwm506h54jb5dbctg
  text: |-
    Full run and examination:
    - Full `swift test` (one process): 1585 tests in 130 suites, the run ended after 1483.6 s (no hang). 1579 passed, 6 failed, each with "The FSEvents event did not come before the time limit (60.0 seconds). The test waited for <change> at <path>." 0 compiler warnings in Sources/ and Tests/.
    - The 6 failed tests: CrossRepoReadinessCacheTests.relatedChangeClosesCycle (lib/.kanban), FolderStreamsTests.otherLetterCaseGetsEvents (marker.txt), CrossRepoReadTests.readyAfterCompleteInSameProcess (lib/.kanban), CrossRepoReadTests.unknownKeyScansAgain (e-new-lib), ReplacedRepoTests.changeOfOldEngineIsNotSent (new-lib), ReplacedRepoTests.subscriberGetsChangesOfNewRepo (new-lib).
    - Examination: late, not lost by the code. Evidence: (1) fseventsd used 100 % CPU during and after the run; the system made about 1625 FSEvents events each second while the tests were idle; a different `sah serve` session ran `ls -f` on the temporary folder for more than 8 minutes. (2) Run of only the 6 tests: 3 passed (otherLetterCaseGetsEvents needed 15 s for one write), 3 failed again. (3) A diagnostic in PathRepo.replace() (removed after the run) and a new run of ReplacedRepoTests: all 6 tests of the suite passed, the 2 subscriber tests in 15 s. (4) A run of readyAfterCompleteInSameProcess and readyAfterWriteOfDifferentProcess: both passed (40.9 s). The code path of a path-ref change was read: only KanbanHost.knownFolderDidChange forgets a record and tells the observer, and the subscription path (followMovedRelatedBoard) does not change the record. No code defect found.
    - Not done: the limit stays 60 s as decided. When fseventsd is saturated, a delivery can take more than 60 s. The user decides if the limit must be higher, or if the outside load must stop before a run.
  timestamp: 2026-10-17T23:20:50.102880+00:00
- actor: claude-code
  id: 01m562p5eq487j0gm6x7pv4t7s
  text: |-
    ### implement — changed
    - evidence: new Tests/FoundationModelsKanbanTests/Observe/FolderEventWait.swift (timeLimitSeconds = 60, FolderEventTimeout) and FolderEventWaitTests.swift (RED then GREEN, 2/2); changed waits in BoardWatcherTests, ScanCacheTests (ScanRecorder.waitForChange), UnreadableRelatedBoardTests, SubscriptionTests.events(_:of:afterChangeAt:), ReplacedRepoTests, CrossRepoReadTests, CrossRepoReadinessCacheTests, PathRefCacheTests, PathBoardKeyTests, CrossRepoActorTests, CrossRepoEventBoardTests, CrossRepoRefFilterTests, RemoteAssigneeFeedTests, SharedShortIDTests, ReadmeExamplesTests, ChangeFilterTests, FolderStreamsTests, BoardWatchTests, AgentPlanPostTests, KanbanHostTests. swift build --build-tests: 0 errors, 0 warnings. Full swift test: 1585 tests in 130 suites, 1579 passed, 6 failed at the 60 s limit (late FSEvents delivery under outside load; each passed on a later run), no hang.
    - next: the user decides if 60 s stays when fseventsd is saturated; then /test and /review.
  timestamp: 2026-10-17T23:20:54.487604+00:00
- actor: claude-code
  id: 01m562qbzmrwj02xpa84hs08kr
  text: |-
    ### finish iteration 2 — red
    - implement: changed — Tests/FoundationModelsKanbanTests/Observe/FolderEventWait.swift (new, timeLimitSeconds = 60), FolderEventWaitTests.swift (new), waits changed in about 20 test files. swift build --build-tests: 0 errors, 0 warnings.
    - test: red — swift test: 1585 tests, 1579 passed, 6 failed at the 60 s limit: CrossRepoReadinessCacheTests.relatedChangeClosesCycle, FolderStreamsTests.otherLetterCaseGetsEvents, CrossRepoReadTests.readyAfterCompleteInSameProcess, CrossRepoReadTests.unknownKeyScansAgain, ReplacedRepoTests.changeOfOldEngineIsNotSent, ReplacedRepoTests.subscriberGetsChangesOfNewRepo. No hang.
    - note: ReplacedRepoTests failed on the rerun, and passed when a diagnostic was in PathRepo.replace(). That is the sign of a race, not of a late event.
    - commit: not run. review: not run.
    - next: /implement examines the 6 tests as possible races in the code (the user does not accept "machine load").
  timestamp: 2026-10-17T23:21:33.940332+00:00
- actor: claude-code
  id: 01m56cvnwk18wx1mj3x8tpkjyp
  text: |-
    Iteration 3 examination (the 6 tests at the 60 s limit):

    Defect found and fixed: a stream switch in FolderStreams loses events.
    - Trace of ReplacedRepoTests (temporary stderr diagnostic, now removed), 3 suite runs: the 2 subscriber tests failed each time, the 4 other tests passed each time. In the subscriber tests the old engine watches the repo folder itself (no `.kanban/`). Its compare batch from the load makes it retire about 1 s after the move, so the host removes its folder and the stream switches (new stream at "now", FlushSync and stop of the old stream). After that switch the host got no event of the move in 60 s. Hosts of the same run with no switch got the events of the same time after 11 s. Thus the events were lost, not late.
    - Standalone probe with no package code (scratchpad/switch): stream A, write, 0.5 s, stream B at "now", FlushSync(A) (returns in 0.000 s), stop A. The event came from no stream in 3 of 8 runs (90 s wait). Control with no switch: 0 of 8 lost (1 of 8 at an earlier time with a 90 s wait, 0 of 8 with a 240 s wait).
    - Cause: fseventsd can hold an event that it read before the start of the new stream and did not send yet. FlushSync does not wait for it, the old stream stops, and the new stream does not get it.
    - Fix (TDD): after each change of the set of folders, `EventRouter.reportLostEvents(skipping:)` gives each folder that stays one batch with the folder itself (the same as a batch of lost events), so its receiver compares each file. The added folder gets no such batch. RED: 2 new tests in FolderStreamsTests with a fake service (QuietFolderEvents) failed on the missing batch; GREEN: both pass. FolderStreamsTests.writeBeforeAddArrives now accepts the event of the file or the compare batch (the new contract). divergence.md §16 Gap 4 states the new rule.

    Checked and not a defect:
    - Letter case: a probe that opens the folder by its lowercase path, reads F_GETPATH, and watches that path got 6 of 6 marker events with disk-case paths (0.3 to 14.6 s). In the failed traced run of otherLetterCaseGetsEvents the stream got the event of the folder itself after 16.5 s, so the path match works; the marker event did not come in 60 s, and no switch happened (one sink only).
    - /private/var vs /var: eventPath uses F_GETPATH; events come with /private/var; WatchedPlace keeps both bases.
    - Watcher start not awaited: each watcher start is awaited before the test writes (BoardWatcher init awaits FolderStreams.add; engine load awaits its watcher; recordBoard awaits the watch).
    - Wait that subscribes late: each wait reads a buffered AsyncStream that exists before the write.
    - Dedup of event ids: dedup is before the routes; ids are unique; capacity 4096.

    Outside load, with evidence (not a cause in this repo):
    - fseventsd uses 100 to 155 % CPU with no test running; it has 7313 CPU minutes in 9.6 days of uptime.
    - A rust-analyzer (pid 88269, child of a different `sah serve` session, 9 h 43 min old) added 344 FSEvents clients in 10 minutes; a test process adds 4 to 7.
    - FSEvents calls alone (standalone probe): create+start up to 1.3 s, FlushSync up to 1.6 s.
    - In passing runs the event id of the change is assigned only about 12 ids before delivery, 10 to 15 s after the write: fseventsd reads the kernel queue late.
    - The temporary folder of the user has about 1 million entries (directory size 81 MB, link count 65535); a different session runs `ls -f` on it for more than 40 minutes.
  timestamp: 2026-10-18T02:18:40.915560+00:00
- actor: claude-code
  id: 01m56t3zk5z64jh4xx1y60na1r
  text: |-
    ### implement — stuck
    - evidence (changed files):
      - Sources/FoundationModelsKanban/Observe/FolderStreams.swift: after each stream switch, `EventRouter.reportLostEvents(skipping:)` gives each folder that stays a compare batch (the added folder gets none). Cause found with a trace and a standalone probe: a new stream at "now" plus FlushSync and stop of the old stream lost the event of a write 0.5 s before the switch in 3 of 8 switches (0 of 8 with no switch).
      - Sources/FoundationModelsKanban/CrossRepo/ScanMarks.swift (`ScanMarks.changes(inPlaceAt:)`, `RepoMark.changes(ofRepoAt:from:to:)`, `FileStamp.isDirectory`, `FileStamp.isSameEntry(as:)`), ScanChange.swift (`BoardIndex.resolving(_:)`), ScanCache.swift, PathRefRecord.swift: a compare of a place resolves into the same precise changes that the events of the files give. Without this, the compare batches made PathBoardKeyTests.nodeReadsPathBoard and dependencyOnDoneTaskIsReady fail (the path-ref record was forgotten for a new board log).
      - Tests: FolderStreamsTests (2 new tests with the fake QuietFolderEvents; writeBeforeAddArrives accepts the event or the compare batch), PathRefRecordTests (3 new), ScanMarksTests (2 new). TDD: each new test RED, then GREEN.
      - divergence.md §16 Gap 4: the switch rule and the compare rule.
      - New task ^5jswv8q: share one running scan between the parallel requests of one call (CrossRepoParallelLoadTests.boardFieldsLoadAtSameTime failed once in a full run).
    - tests: `swift build --build-tests` 0 errors, 0 warnings in Sources/ and Tests/. The 6 tests of iteration 2 alone after the last change: 18 of 18 pass (3 runs each). Earlier per-test runs: 29 of 30. The 4 tests that failed in the first full run with the switch fix only: 12 of 12 alone after the resolution fix.
    - full `swift test` (one process each): run A 1592 tests, 2 failed (CrossRepoParallelLoadTests.boardFieldsLoadAtSameTime expectation; AgentPlanPostTests.watcherBatchPostsNothing at 60 s). Run B 1592 tests, 2 failed at 60 s (UnreadableRelatedBoardTests.subscriberGetsChangeWithRustDependency, ScanCacheTests.newBoardLogIsEnabled). Run C (with a temporary trace, removed) 1592 tests, 2 failed at 60 s (UnreadableRelatedBoardTests.subscriberGetsChangeWithRustDependency, SharedShortIDTests.subscriptionSendsTaskThatSharesItsShortIDLater). None of the 6 tests of iteration 2 failed. Each of the other failed tests passed 3 of 3 alone.
    - why stuck: the full run does not pass, and the remaining cause needs a decision. Trace of run C: SharedShortIDTests had one stream and no switch after the write; fseventsd gave the events of that time with a dispatch lag of about 30 s, and the write event did not come in 60 s. UnreadableRelatedBoardTests got its FSEvents batch in time; the change then needed three FolderStreams changes that took 17.5 s, 4.1 s, and 19.8 s (each waits for FSEvents calls to fseventsd), plus a scan with real git and a lib load. The test process registered 2348 FSEvents clients in 24 minutes (each watcher add or remove makes a new stream); an outside rust-analyzer registered 344 in 10 minutes; fseventsd uses 100 to 155 % CPU when no test runs.
    - next (the user decides): (a) make FolderStreams change the stream less often, for example no new stream when a folder is removed (this changes the design in divergence.md §16); (b) lower WatcherBudget.slotCount (16 now) so that fewer tests make FSEvents calls at the same time; (c) stop the outside load before a run. The time limit stays 60 s as the user decided.
  timestamp: 2026-10-18T06:10:24.485048+00:00
- actor: claude-code
  id: 01m56t5ahjsr7mysssqmqjd4qz
  text: |-
    ### finish iteration 3 — stuck
    - implement: stuck — defect fixed: a stream switch lost an event that fseventsd held (probe: 3 of 8 switches lost the write). Fix: after each switch, each watched folder that stays gets one compare batch (EventRouter.reportLostEvents(skipping:)); ScanMarks, ScanChange, ScanCache, PathRefRecord turn a compare into exact changes. New tests: 2 FolderStreamsTests, 3 PathRefRecordTests, 2 ScanMarksTests. Build 0 errors, 0 warnings.
    - test: red — the 6 named tests 18/18 alone. Full swift test 1592 tests: run A 2 failed (CrossRepoParallelLoadTests, AgentPlanPostTests), run B 2 failed (UnreadableRelatedBoardTests, ScanCacheTests.newBoardLogIsEnabled), run C 2 failed (UnreadableRelatedBoardTests, SharedShortIDTests). Each passed 3/3 alone.
    - note: the test process registered 2348 FSEvents clients in 24 minutes, because each folder add or remove makes a new stream. New task ^5jswv8q for the parallel scan.
    - commit: not run. review: not run.
    - next: the user picks (a) fewer stream switches (design change, divergence.md §16), (b) a lower WatcherBudget.slotCount, or (c) no outside load before a run.
  timestamp: 2026-10-18T06:11:08.466807+00:00
- actor: claude-code
  id: 01m57fhgc31118024c4m7hb3sw
  text: |-
    ### decision — user
    - The user chose: fewer stream switches.
    - Change the design (divergence.md §16): a folder remove makes no new stream. The router ignores events of folders that are not watched. A new stream is necessary only when a folder that the current stream does not cover is added. Look for a way to make fewer switches for adds also (for example, a stream on a common parent folder).
    - next: /implement makes the change, updates divergence.md §16, and runs the full swift test.
  timestamp: 2026-10-18T12:24:47.747184+00:00
- actor: claude-code
  id: 01m57fts908tfgxn5ptxemf5z5
  text: |-
    Iteration 4 research and design (fewer stream switches):
    - Today `FolderStreams.add` and `.remove` each call `replaceStream`, so each change of the set of folders makes a new FSEvents stream. `add` runs as one actor job (event id, router insert, stream start), so adds that come at the same time make one switch each.
    - Remove: the router removes the route; the stream does not change. The stream keeps the path of the removed folder until the next switch; the router gives no event for a path with no route. When the router has no route, the stream ends.
    - Add: a new stream only when a path of the router is not in a folder that the current stream watches. A re-add of a removed folder, or a folder in a watched folder, makes no new stream. A new stream watches only the folders of the router (the paths of removed folders go away at that time).
    - Way to make fewer switches for adds, chosen: collect the adds that wait. The router insert of an add runs before the add waits for the actor, as a pending route (it gets no event yet). The actor job of an add first gives each pending route its start id, then starts one stream for all routes. Thus each add that waits while a slow switch runs is in the next switch, and the later jobs find their folder watched and make no stream. This adds no delay.
    - Not chosen: (1) a stream on a common parent folder: the parent of the test folders is the temporary folder of the user (about 1 million entries, and other processes write there), and the parent of repos can be the home folder or `/`. fseventsd must then send each event of that tree, which gives it more work, not less, and more dropped-event flags. (2) a debounce with a timer: each add must wait for the stream before it returns (the caller writes just after), so a timer adds its delay to each add, and a slow FSEvents call already collects the adds that come during it.
    - The compare batch stays: after each switch, each active route whose folder the old stream watched gets one batch with its folder (`EventRouter.reportLostEvents`).
    - The event id call (`currentEventID`) stays on the actor queue (no FSEvents call on the cooperative pool).
  timestamp: 2026-10-18T12:29:51.776970+00:00
- actor: claude-code
  id: 01m57gqynv2xs9vmbjg4wnefcw
  text: |-
    Iteration 4 implementation landed (not committed):
    - FolderStreams.swift: `add` is nonisolated; it puts the sink in the router as a waiting sink (`EventRouter.insert(_:at:)`), then waits for the actor job `watchEachFolder(adding:)`. The job gives each waiting sink its start id (`startWaitingSinks(after:)`, the `currentEventID` call stays on the actor queue), and makes a new stream only when `StreamState.watchesEach(of:)` is false. `remove` and `removeWithoutWait` make no new stream; `endStreamWithNoFolder()` ends the stream when no sink stays. After a change of the stream, `reportLostEvents(inFoldersOf: oldPaths)` gives a compare batch to each started sink whose folder the old stream watched. `shrinkStream`, `replaceStream`, and `reportLostEvents(skipping:)` are removed.
    - Tests (FolderStreamsTests, with the fakes QuietFolderEvents (records the paths of each start) and HeldStartService (counts starts)): removeMakesNoNewStream, addInWatchedFolderMakesNoNewStream, addOfRemovedFolderMakesNoNewStream, switchAfterRemoveLosesNoChange, waitingAddsShareOneStream. RED: the first 4 failed on the start count (3, 2, 4 starts) and the extra compare batch; waitingAddsShareOneStream did not end in 60 s (old code puts the sink in the router only on the actor, so the waiting adds never show) and was stopped with `timeout`. GREEN: all 5 pass (0.012 to 0.027 s). The test removeReportsLostEventsToEachOtherFolder is replaced by removeMakesNoNewStream (the old contract gave a compare batch on remove).
    - divergence.md §16 Gap 4: new DECIDED sub-item with the rule, the chosen way for adds, the ways not chosen and why, and the tests.
    - `swift build --build-tests`: 0 errors, 0 warnings.

    Discovery (environment, with a probe that has no package code, scratchpad/probe/main.swift): at this time fseventsd (100 % CPU) gives NO event for a path under the temporary folder of the user (/private/var/folders/l7/.../T): 0 of 4 writes in 60 s (in T itself and in T/FoundationModelsKanbanTests). The same probe on /private/tmp/... and on the repo .build folder got each write in 2.5 to 2.9 s. All unit test folders are under T (TemporaryDirectory, GitSandbox). Thus the 3 FolderStreamsTests that wait for a real FSEvents event fail at the 60 s limit now, also alone. T holds about 188,000 entries; TemporaryItems has 65535 links; other processes add TemporaryDirectory.* and code-context-ts-*.lock entries there each minute.
  timestamp: 2026-10-18T12:45:47.579770+00:00
- actor: claude-code
  id: 01m57k0w6bxd4q9pp7spz3e8te
  text: |-
    ### implement — stuck
    - evidence (changed files, not committed):
      - Sources/FoundationModelsKanban/Observe/FolderStreams.swift: a remove makes no new stream (the stream ends when no folder stays); an add makes a new stream only when the running stream does not watch the folder; the adds that wait share one new stream (waiting sinks in EventRouter: `insert(_:at:)`, `startWaitingSinks(after:)`); compare batch after each change of the stream (`reportLostEvents(inFoldersOf:)`).
      - Tests/FoundationModelsKanbanTests/Observe/FolderStreamsTests.swift: 5 new tests (removeMakesNoNewStream, addInWatchedFolderMakesNoNewStream, addOfRemovedFolderMakesNoNewStream, switchAfterRemoveLosesNoChange, waitingAddsShareOneStream); QuietFolderEvents records the paths of each start. HeldStartService.swift counts starts. BoardWatcherTests.swift uses the new router API.
      - divergence.md §16 Gap 4: the new rule, the chosen way for adds (shared start of waiting adds), and why a common parent folder and a timer debounce are not chosen.
    - TDD: 4 tests RED on the start count, waitingAddsShareOneStream RED (did not end; stopped with `timeout`), then 5 of 5 GREEN. `swift build --build-tests`: 0 errors, 0 warnings.
    - full `swift test` (one process each):
      - run 1: 1596 tests in 130 suites, 1591 passed, 5 failed, 906.2 s. FSEvents clients of the test process (fseventsd `fsevent_add_client` for its pid): 1124.
      - run 2: 1596 tests in 130 suites, 1587 passed, 9 failed (10 issues), 849.8 s. FSEvents clients: 1129.
      - Iteration 3 for compare: 2348 FSEvents clients in about 24 min.
      - Each failure is `FolderEventTimeout` (60 s) at a path under /var/folders/l7/.../T. No other failure kind.
    - why stuck: the acceptance item "The full swift test passes" is not met. A probe with no package code (scratchpad/probe/main.swift: one stream at "now", one write) at the same time: under T, 0 of 4 writes came in 60 s, one write came after 144 s, and the stream start took 56 s; under /private/tmp and the repo .build, writes came in 2.5 to 2.9 s. After run 2: stream start 26 s on both paths, events after 6.6 and 21.6 s. fseventsd is at 100 % CPU.
    - next (a person decides): for example (a) move the unit test folders out of the temporary folder of the user (TemporaryDirectory, GitSandbox) to a folder that fseventsd serves, (b) a different time limit, or (c) clean the temporary folder of the user (about 188,000 entries) before a run. The 60 s limit stays as decided until then.
  timestamp: 2026-10-18T13:25:37.099066+00:00
- actor: claude-code
  id: 01m57k264sk68hthpfzx68900n
  text: |-
    ### finish iteration 4 — stuck
    - implement: stuck — FolderStreams: a remove makes no new stream; an add makes a new stream only when the stream does not cover the folder; adds that come at the same time share one switch; the compare batch after a switch stays. 5 new tests count stream starts through FolderEventService. divergence.md §16 Gap 4 updated. Build 0 errors, 0 warnings.
    - test: red — run 1: 1596 tests, 1591 passed, 5 failed, 1124 FSEvents streams. Run 2: 1596 tests, 1587 passed, 9 failed, 1129 FSEvents streams (was 2348). Each failure is the 60 s FolderEventWait limit at a path under the user temporary folder.
    - evidence: a probe with no package code (scratchpad/probe/main.swift), one stream and one write under the user temporary folder: 0 of 4 writes came in 60 s, one came after 144 s, one stream start took 56 s. fseventsd at 100% CPU.
    - commit: not run. review: not run.
    - next: the user decides: move the test folders (TemporaryDirectory, GitSandbox) out of the user temporary folder, change the limit, or restart fseventsd.
  timestamp: 2026-10-18T13:26:20.057182+00:00
- actor: claude-code
  id: 01m57kebjj0q0k96364d30vcz9
  text: |-
    ### decision — user
    - The user chose: move the test folders out of the user temporary folder.
    - TemporaryDirectory and GitSandbox (and each other test helper that makes a folder in NSTemporaryDirectory or FileManager.temporaryDirectory) make their folders in a separate root, for example /private/tmp/fmk-tests/<run id>/. Each test removes its folder at the end, as now.
    - next: /implement makes the change, then the full swift test runs.
  timestamp: 2026-10-18T13:32:58.834645+00:00
- actor: claude-code
  id: 01m57m1zxc6kqw0sc5rc08b1ay
  text: |-
    Iteration 5 research and change (move the test folders out of the user temporary folder):
    - rg for NSTemporaryDirectory, temporaryDirectory, TMPDIR in Tests/, IntegrationTests/, Sources/: the helpers that make a folder are TemporaryDirectory (EventLogTests.swift, shared parent T/FoundationModelsKanbanTests), GitSandbox (BoardKeyTests.swift, directly in T), and TemporaryGitRepo (IntegrationTests, T/FoundationModelsKanbanIntegrationTests). No source default uses the user temporary folder (only a comment in FolderIdentity.swift).
    - Path only, no folder made, no real FSEvents stream (fake services): RouterSink (FolderStreamsTests), FolderStreamsPoolTests.makeSink, the BoardSource directory in ChangeFeedTests. These stay as they are.
    - New Tests/FoundationModelsKanbanTests/TestFolderRoot.swift: one root for the unit tests, `/private/tmp/fmk-tests/<UUID>` (one run id for each test process). The path is `FolderStreams.eventPath(of:)` of the folder (F_GETPATH), so it is the same path that FSEvents gives. Groups `TemporaryDirectory/` and `GitSandbox/` keep the parent scan of a TemporaryDirectory repo small (plan.md §6.6). At exit (`atexit`), `rmdir` removes the empty group folders and the empty run folder.
    - Note: `URL.resolvingSymlinksInPath()` (and thus `canonicalPath`) gives `/tmp/...` for `/private/tmp/...`, because it removes `/private`. `realpath(3)` and F_GETPATH give `/private/tmp/...`.
    - IntegrationTests is a different package, so it cannot use TestFolderRoot. TemporaryGitRepo uses the same base `/private/tmp/fmk-tests`, a run folder `integration-<UUID>` at its realpath(3), and the same `atexit` rmdir.
    - TDD: TestFolderRootTests RED with a stub (2 of 4 failed: path `/var/folders/.../T`), then RED for the helpers (2 of 4 failed) after the root was correct, then GREEN 4 of 4. After the run, /private/tmp/fmk-tests was empty (the run folder was removed). IntegrationTests: `swift build --build-tests` has no error and no warning in its own files; BoardSmokeTests 1 of 1 passed.
  timestamp: 2026-10-18T13:43:42.252740+00:00
- actor: claude-code
  id: 01m57p02n66ga77zywwptc1h5x
  text: |-
    ### implement — stuck
    - evidence (changed files, not committed):
      - new Tests/FoundationModelsKanbanTests/TestFolderRoot.swift (`TestFolderRoot`, `TestFolderGroup`): one root for the unit tests, `/tmp/fmk-tests/<UUID>` for each test process, groups `TemporaryDirectory/` and `GitSandbox/`, `atexit` rmdir of the empty folders.
      - new Tests/FoundationModelsKanbanTests/TestFolderRootTests.swift: 4 tests (RED with a stub, RED for the helpers, then GREEN 4 of 4).
      - Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift (TemporaryDirectory) and Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift (GitSandbox) use TestFolderRoot.
      - IntegrationTests/Tests/FoundationModelsKanbanIntegrationTests/Support/TemporaryGitRepo.swift: `/tmp/fmk-tests/integration-<UUID>`, `atexit` rmdir. Build: no error and no warning in its files; BoardSmokeTests 1 of 1 pass.
      - No change in Sources/.
    - deviation from the decision, with the reason: the decision said "use the real path" (/private/tmp/...). A full run with the real path: 1600 tests, 39 failed (47 issues); 27 failures were path compares, not FSEvents. Cause: Sources `URL.canonicalPath` uses `resolvingSymlinksInPath()`, which removes `/private` (it gives /tmp/...), so the package gives /tmp/... for some paths and /private/tmp/... for others. I asked the user (A /tmp link form, B Sources realpath, C change 27 tests); the user said "can you figure it out". I chose A: the test paths are /tmp/fmk-tests/... (= canonicalPath), and FSEvents gives /private/tmp/... . This is the same pair as /var/... and /private/var/... before, which the package handles. No Sources change.
    - full `swift test` (one process each), test folders in /tmp/fmk-tests:
      - run 1: 1600 tests in 131 suites, 1592 passed, 8 failed (8 issues), 350.6 s.
      - run 2: 1600 tests in 131 suites, 1585 passed, 15 failed (15 issues), 416.0 s.
      - Each failure is FolderEventTimeout (60 s) at a path under /tmp/fmk-tests. Run 1: SubscriptionTests (union merge), ReplacedRepoTests (2), BoardWatchTests (changed.txt), PathBoardKeyTests (new origin), PathRefCacheTests (3). Run 2: SharedShortIDTests, FolderStreamsTests (3: otherLetterCase, writeJustAfterSecondAdd, twoFolders), BoardWatcherTests (3), ReplacedRepoTests (2), ScanCacheTests (2), CrossRepoReadTests (2), CrossRepoActorTests, PathRefCacheTests.
      - 0 compiler warnings in Sources/ and Tests/.
    - why stuck: the acceptance item "The full swift test passes" is not met. Evidence that the folder is not the cause now: FolderStreamsTests alone 19 of 19 pass in 7.1 s. A probe with no package code after the runs (3 streams at the same time, one write each): the user temporary folder, /private/tmp/claude-501, and a /private/tmp subfolder all got the event after 8.63 s. fseventsd is at 100 % CPU; load average 6. The run time went down (850 to 906 s before, 350 to 416 s now), but the number of 60 s failures did not go down (5 and 9 before, 8 and 15 now).
    - new task ^rk709sr: about 96 TemporaryDirectory folders stay after each full run (771 in the old location), older than this change.
    - next (a person decides): the 60 s limit stays as decided until then.
  timestamp: 2026-10-18T14:17:36.678816+00:00
- actor: claude-code
  id: 01m57p17ez9g3k7f1czfpzgjpf
  text: |-
    ### finish iteration 5 — stuck
    - implement: stuck — TestFolderRoot.swift (new, /tmp/fmk-tests/<UUID>), TestFolderRootTests.swift (4 tests), TemporaryDirectory and GitSandbox use it; IntegrationTests TemporaryGitRepo uses /tmp/fmk-tests/integration-<UUID>. No change in Sources/. The link form /tmp is used, because URL.canonicalPath removes /private (with /private/tmp: 39 failures, 27 of them path compares).
    - test: red — run 1: 1600 tests, 8 failed, 350.6 s. Run 2: 1600 tests, 15 failed, 416.0 s. Each failure is FolderEventTimeout 60 s under /tmp/fmk-tests. 0 warnings.
    - evidence: FolderStreamsTests alone 19/19 in 7.1 s. Probe with no package code, 3 streams: each event came after 8.63 s on all three paths. The folder move did not reduce the failures (before 5 and 9, now 8 and 15).
    - new task: ^rk709sr (about 96 TemporaryDirectory folders stay after each run).
    - commit: not run. review: not run.
    - next: the user decides. The guardrail is near: 3 iterations of code changes did not make the full run green.
  timestamp: 2026-10-18T14:18:14.367154+00:00
- actor: claude-code
  id: 01m57t5kv0r6pfsyf43ne1dr2s
  text: |-
    ### test — green
    - evidence: `swift test` two times. Run 1: 1600 tests in 131 suites, 1600 passed, 0 failed, 44.895 s. Run 2: 1600 tests in 131 suites, 1600 passed, 0 failed, 45.412 s. Exit code 0 for both. No code was changed.
    - failures: none. No test waited for a path.
    - note: a first run, started at 09:53 with the shell tool, did not end. It made no output for 1800 s (swift-test and swiftpm-testing-helper at 0.0 percent CPU). The tool aborted it, and I killed the processes. Its output was lost, so no test name is known. The two runs above came after, with output saved to a file.
    - fseventsd before run 1 (09:53:15): pid 574, 99.4 percent CPU, 9.1 percent memory, RSS 49070368 KB, up 10 days. fseventsd then restarted (new pid 28807, start about 09:53:40).
    - fseventsd before run 2 (10:27:50): pid 28807, 0.0 percent CPU, 0.0 percent memory, RSS 18224 KB.
    - fseventsd after run 2 (10:28:53): pid 28807, 13.1 percent CPU (average since start), 0.0 percent memory, RSS 18256 KB. After run 1 (10:27:45): 0.0 percent CPU, RSS 18208 KB.
    - warnings in the output: one linker note (missing creator for mutated node, mlx-swift_Cmlx.bundle), and 4 "malformed" log lines per run from tests that load bad JSON on purpose.
    - next: none
  timestamp: 2026-10-18T15:30:32.416389+00:00
position_column: doing
position_ordinal: '8480'
title: Decide what the watcher tests do when FSEvents gives no event
---
## What
Each watcher test (for example CrossRepoReadTests.unknownKeyScansAgain, RemoteAssigneeFeedTests, AgentPlanPostTests.watcherBatchPostsNothing, KanbanHostTests.editDuringSecondLoadArrives) waits with no time limit for one FSEvents event. When FSEvents gives no event, the test and the full `swift test` run never end.

## Evidence (^4p9q125, 2026-10-17)
- Standalone probe outside the package (scratchpad/probe6): a stream at "now" on a real path, one write, then `FSEventStreamFlushSync`: 0 of 5 runs gave the event (FlushSync returned at once). With a 15 s wait: 4 of 5 runs gave the event.
- fseventsd logs "scan_old: bailing out because device mounted @ ... has dls 0x0 and dls->fci 0x0" for each stream with a past `since`, and "failed sending HISTORY_DONE (268435459)".
- A sourcekit-lsp background index (child of the `sah` process) runs `swift-build` in recursive `.build/index-build/checkouts/.../.build/index-build/...` folders of this repo, and the system event id grows by about 1200 events per second while the test process is idle.

## Decision (user, 2026-10-17)
"well that will need some time limit". A wait for an FSEvents event, batch, or change feed event in a test has a time limit. At the limit, the test fails with a clear message (the path and the change that it waited for), and the run continues. Only those wait helpers get the limit, with one shared constant. No `.timeLimit` traits on suites or tests. Other waits (locks, search readiness, loads) keep no time limit.

## Decision (user, 2026-10-18)
Fewer FSEvents stream switches: a folder remove makes no new stream; a folder add makes a new stream only when the current stream does not watch the folder; find a way to make fewer switches for adds; keep the compare batch after a switch; update divergence.md §16.

## Decision (user, 2026-10-18, iteration 5)
Move the test folders out of the user temporary folder, to one shared root in /private/tmp (one run id for each test process). Each test removes its own folder.

## Acceptance
- [x] Each test wait for an FSEvents event, a watcher batch, a scan-place or path-ref change, or a change feed event goes through `FolderEventWait.value(waitingFor:at:within:of:)` (Tests/FoundationModelsKanbanTests/Observe/FolderEventWait.swift).
- [x] One shared constant: `FolderEventWait.timeLimitSeconds = 60`. Its comment gives the value and the reason (measured delays 0.2 to 15 s; 60 s is four times the longest).
- [x] At the limit the test fails with `FolderEventTimeout`, whose message names the change and the path. The run continues.
- [x] No `.timeLimit` trait on a suite or a test.
- [x] Waits for locks, search readiness, loads, held fakes, and the end of a stream keep no time limit.
- [x] Unit tests of the helper: FolderEventWaitTests (RED, then GREEN).
- [x] The full `swift test` runs to the end (no hang).
- [x] A stream switch of FolderStreams loses no change: after each change of the stream, each folder that the old stream watched gets a compare batch (`EventRouter.reportLostEvents(inFoldersOf:)`), and the scan cache and the path-ref record resolve a compare into the precise changes (`RepoMark.changes(ofRepoAt:from:to:)`, `BoardIndex.resolving(_:)`).
- [x] Fewer stream switches (iteration 4): a remove makes no new stream (the stream ends when no folder stays); an add makes a new stream only when the running stream does not watch the folder; the adds that wait while a stream starts share one new stream (waiting sinks in the router). divergence.md §16 Gap 4 states the rule. Tests with the FolderEventService fakes: FolderStreamsTests.removeMakesNoNewStream, addInWatchedFolderMakesNoNewStream, addOfRemovedFolderMakesNoNewStream, switchAfterRemoveLosesNoChange, waitingAddsShareOneStream (RED, then GREEN). FSEvents clients of the test process in a full run: 1124 and 1129 (2348 before).
- [x] Test folders out of the user temporary folder (iteration 5): TemporaryDirectory and GitSandbox use `TestFolderRoot` (Tests/FoundationModelsKanbanTests/TestFolderRoot.swift), run folder `/tmp/fmk-tests/<UUID>` (FSEvents path `/private/tmp/fmk-tests/<UUID>`); IntegrationTests TemporaryGitRepo uses `/tmp/fmk-tests/integration-<UUID>`. The empty run folder is removed at exit. TestFolderRootTests (RED, then GREEN).
- [ ] The full `swift test` passes. Iteration 5 (test folders in /tmp/fmk-tests): run 1 1600 tests, 8 failed (8 issues), 350.6 s; run 2 1600 tests, 15 failed (15 issues), 416.0 s. Each failure is the 60 s FolderEventWait limit at a path under /tmp/fmk-tests. FolderStreamsTests alone: 19 of 19 pass in 7.1 s. A probe with no package code after the runs: the same delay of 8.6 s in the user temporary folder and in /private/tmp. A person must decide the next step (see the step record of iteration 5).