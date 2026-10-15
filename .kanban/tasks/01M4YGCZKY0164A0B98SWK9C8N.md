---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m50ctrexrgn5wc27x7rjw2aj
  text: 'Research done. Each folder watch goes through `BoardWatcher(watching:)` (S/Observe/BoardWatcher.swift), made by `StartedWatcher(watching:)` in S/Tool/BoardEngine.swift. Callers: `BoardEngine.load` and `movedWatch`, and the host for scan places, unloadable boards, and path-ref folders (`makeFolderWatch`, `makeUnloadableWatch`). Plan: add `FolderStreams` (S/Observe) that the host owns. It keeps one FSEvents stream over all folder paths, and an `EventRouter` gives each event group to each `BatchSink` whose folder holds the path. A set change starts the new stream, then flushes and stops the old one (FSEventStreamFlushSync), then flushes the new one; event ids seen while the two streams run are dropped the second time. Routing uses the path from `fcntl(F_GETPATH)`, the same vnode path that FSEvents gives, so letter case and /var vs /private/var agree. `BoardWatcher` keeps its API (batches, stop, isRunning) and takes the `FolderStreams` to use. plan.md §5.6 says one stream for each board: I record the change in divergence.md §16 (plan.md stays frozen).'
  timestamp: 2026-10-15T18:22:44.189258+00:00
- actor: claude-code
  id: 01m50kznqdq10hse1kd1p0wkm3
  text: |-
    Progress notes:
    - Try 1: the new stream started with `sinceNow`. Events between the stop of the old stream and the start of the new stream were lost (flaky tests). Fix: the new stream starts at the last event that the router got, and FSEvents gives the later events from its history. The router drops an event that it gave before, until the HistoryDone mark.
    - Try 2: `FSEventStreamFlushSync` waits 130-185 ms for history. It held the lock on cooperative threads, and the full suite had many 60 s time-limit failures. Fix: no flush. No step of a change waits for FSEvents.
    - Try 3: history replay gave events from before the add to a new folder (a path-ref test saw a git run). Fix: each route keeps the event id of its add and drops older events. New test `folderGetsNoEventFromBeforeItsAdd` (RED first, then GREEN).
    - Also: the new stream starts no later than the add of a new folder, so an event of the new folder is not lost when the old stream gives a later event of another folder first.
    - Full suite: one run passed all 1530 tests. Other runs on this machine had 60 s time-limit failures in cross-repo and subscription tests. A clean copy of HEAD (without this change) in the scratchpad had the same failures (99 time limits), so the cause is the machine load (a test process of a different repo runs for 31 hours), not this change. Each failed suite passes alone.
  timestamp: 2026-10-15T20:27:45.261353+00:00
- actor: claude-code
  id: 01m50kzs4t3btbwt6jem84smny
  text: |-
    ### implement — changed
    - evidence: new S/Observe/FolderStreams.swift (FolderStreams, EventRouter); S/Observe/BoardWatcher.swift uses the host streams; S/Tool/BoardEngine.swift and S/Tool/KanbanHost.swift pass one FolderStreams for each host; tests in T/Observe/FolderStreamsTests.swift, T/Tool/KanbanHostTests.swift (hostHoldsOneStream, editDuringSecondLoadArrives, editGoesToItsEngineOnly), T/Observe/BoardWatcherTests.swift, T/Tool/BoardWatchTests.swift, T/WatcherBudget.swift; divergence.md §16 Gap 4. Build has no warnings. Watcher, host, and stream suites: 46 tests pass. Full suite: 1530 pass in a run with low load.
    - next: /review. The WatcherBudget trait can maybe go now, but each test still makes its own host, so it stays for this change.
  timestamp: 2026-10-15T20:27:48.762833+00:00
- actor: claude-code
  id: 01m50pw04n5pv4t896gr28r7rm
  text: |-
    ### test - red
    - evidence: `swift build` is clean (one allowed "missing creator" warning only). `swift test` full suite, 1530 tests: run 1 had 103 issues, run 2 had 5 issues, run 3 had 81 issues. Run 3 was the final run after the failing suites ran alone. Nearly all issues are "Time limit was exceeded: 60.000 seconds". The tests that fail are different in each run. The machine load average is 127 to 145.
    - The failing suites alone (14 suites, 124 tests) passed in 11 seconds. CrossRepoCycleReadinessTests alone (5 tests) passed in 1.9 seconds.
    - Other issues in the runs: BoardWatchTests "isFound" and AgentPlanPostTests "hasBatch" (a watcher batch did not come in time), and BoardKeyTests got `.gitCancelled` where it expected `.gitTimedOut` (the cancel of the 60 second limit came first). Each of them follows a test that waited for a slot of the WatcherBudget (16 slots) while the machine was loaded.
    - Integration tests (`swift test` in IntegrationTests with the integration-build scratch path): 3 tests passed, 0 failures.
    - I found no failure that comes from the code of this task. I did not raise a time limit. I did not change code.
    - next: run the full suite again on a machine with low load. The queue of the WatcherBudget makes one full run about 80 to 90 seconds, so a 60 second limit fails on a loaded machine.
  timestamp: 2026-10-15T21:18:10.581731+00:00
- actor: claude-code
  id: 01m50tem7zsgh5ystn036ex75w
  text: |-
    ### test - green
    - evidence: waited 60 minutes for load (105 down to about 90, never under 60), then ran anyway. `swift build` complete, one allowed "missing creator" warning only. `swift test` full suite (1 run): 1530 tests in 121 suites passed in 57.6 seconds, exit 0, 0 issues, 0 skipped, no warnings other than the allowed one. Load at run: 90 to 103.
    - No baseline was needed. No code or time limit was changed.
    - next: /review.
  timestamp: 2026-10-15T22:20:46.719496+00:00
- actor: claude-code
  id: 01m50tfav6jh2jgh20srr12t5e
  text: |-
    ### commit — changed
    - evidence: 7f0443d feat(observe): use one FSEvents stream for each host (^swk9c8n). 14 files: FolderStreams.swift and FolderStreamsTests.swift (new), BoardWatcher, BoardEngine, KanbanHost, their tests, WatcherBudget, divergence.md, and .kanban/tasks files.
    - next: Not staged on purpose: Package.resolved and .kanban/mcp.17281.log. The commit is local only. No push.
  timestamp: 2026-10-15T22:21:09.862923+00:00
position_column: doing
position_ordinal: '80'
title: Use one FSEvents stream for each host, not one for each watched folder
---
## What
The test step of ^gz2mxwz measured the FSEvents stream limit with a scratch probe. The limit is for the whole system, not for one process. On this machine one process got only 36 streams before `FSEventStreamStart` failed. With a second probe that held 20 streams, a third probe got only 16. Other apps on the machine hold the rest.

Now the Swift package starts one FSEvents stream for each watched folder:
- one for each board engine (S/Tool/BoardEngine.swift);
- one for each scan place (S/CrossRepo/ScanCache.swift, ^3prjnb4);
- one for each board that cannot be read (^z4jcv8j).

A process with many ACP sessions and many related boards can thus run out of streams. Then a watcher does not start, and the board does not see manual edits. This breaks the user's rule "file watch detection to allow manual poking of files" (divergence.md §16).

Change: `KanbanHost` keeps one FSEvents stream for all the folders that it watches. `FSEventStreamCreate` takes an array of paths. When the set of folders changes (a board loads or closes, a scan place is added), make a new stream for the new set, start it, and then stop the old stream, so that no event is lost. Send each event to the engine, scan place, or unreadable board that owns its path.

Keep the current behavior for each owner: the same batches, the same full compare when events are lost, and the same event for a directory inside `.kanban/` (^qys059z).

## Acceptance Criteria
- [x] A host with N boards, M scan places, and K unreadable boards uses one FSEvents stream (two for a short time while the set changes).
- [x] Each owner still gets exactly the events for its own paths.
- [x] A change in the set of folders loses no event.
- [x] All existing watcher tests still pass.

## Tests
- [x] A test that opens many boards and scan places and checks that the host holds one stream.
- [x] A test that adds a board while another board gets a change, and checks that the change still arrives.
- [x] A test that events for two boards go to the right engine.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.