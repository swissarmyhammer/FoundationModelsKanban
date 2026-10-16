---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m51mrcej8eq8jn9x0r5mqz6v
  text: |-
    Research (static review). Areas read: Observe/FolderStreams.swift, Observe/BoardWatcher.swift, Tests WatcherBudget.swift, SerialGate in Tool/KanbanGraph.swift, Git.run and GitRecord in Identity/BoardKey.swift, Events/BoardLock.swift, Tool/Commit.swift.

    Found a real deadlock path:
    - `Commit.commit(_:along:)` calls `EventLog.lock(sortedByKey:)`. `LockedFile.waitForLock` calls `flock(LOCK_EX)`, which blocks the thread. The caller is async, so the thread is a thread of the Swift cooperative pool.
    - While the commit holds the flock, it does `try await writes[index].applyChangedFiles()`. That goes to `LiveGraph.apply` -> `BoardLoader.readFiles`, which adds child tasks to a task group. These child tasks, and the resume after the await, need a free thread of the cooperative pool.
    - A second commit of a different engine in the same process (for example a related board, or a second host on the same board) blocks a pool thread in `flock` until the first commit releases the lock. When the blocked waiters (and other blocking calls) take all pool threads (about one for each processor: 18 on this machine), the holder can never continue. Then the whole test process stops with 0% CPU, and a `.timeLimit` trait cannot fire, because its timer also needs a pool thread.
    - EventLogTests already has a note that a `flock` wait must not run on the cooperative pool, and ^dqxhqwy fixed the same type of problem for Git.run.

    Areas with no hang path found:
    - FolderStreams holds its Mutex across FSEventStreamCreate/Start/Stop/Invalidate, but the FSEvents callback takes only the router table lock and calls AsyncStream.yield, which does not block. No cycle.
    - SerialGate (and WatcherBudget, which uses it) releases its slot in a `defer`, also when the operation throws.
    - Git.run resumes its continuation one time on exit and pipe end, on cancel, and on its time limit.

    Run 1 of the full suite (with the code at HEAD): 1562 tests passed in 52 s. Runs 2 to 10 are in progress with `timeout 900 swift test --skip-build`.
  timestamp: 2026-10-16T06:00:29.394860+00:00
- actor: claude-code
  id: 01m51nbcf3dg7v40vm28xsaqc2
  text: |-
    Reproduced the hang, and found its cause.

    Runs at HEAD (`timeout 900 swift test --skip-build`, logs in the session scratchpad runs/ folder): run 1, 2, 4, 5 passed (46 to 60 s). Run 3 finished but failed: 140 tests exceeded the 60 s time limit together, and 6 FSEvents waits failed (load average was about 90). Run 6 hung: the log stopped at line 5598, and the swiftpm-testing-helper (pid 6327, my own) stayed at 0.0% CPU with 4 threads.

    Evidence from run 6:
    - `sample 6327 10`: only 2 threads. The main thread waits in CFRunLoopRun (mach_msg), and one workqueue thread is parked. No thread is blocked in a lock, in flock, or in a syscall. Thus every task waits for a resume that never comes.
    - `swift-inspect dump-concurrency 6327` shows the cycle:
      - Task 9687 (the test `UnreadableRelatedBoardTests.changeOfFilesLoadsAgain(breakage:)`, flag `cancelled` from its time limit): `KanbanGraph.close` -> `KanbanHost.close` -> `BoardEngine.close` -> `BoardWatch.end()`, which waits for `consumer.value` of the first watch (W1).
      - Task 57114 (the consumer of W1, `cancelled`): `BoardEngine.receive` -> `SerialGate.run` (it HOLDS the engine gate) -> `applyPublishing` -> `apply` -> `adopt` -> `BoardWatch.end()` of the moved watch (W2), which waits for `consumer.value` of W2.
      - Task 57160 (the consumer of W2, `cancelled`): `BoardEngine.receive` -> `SerialGate.run` -> `SerialGate.enter()`, which waits for the gate that Task 57114 holds.
    - Cause: when `close()` runs during an await of `BoardEngine.apply` (after `movedWatch` made W2), `adopt(_:)` sees a closed engine and calls `await moved.end()` INSIDE the serial gate. `end()` waits for the consumer task of W2. That task got a batch and waits to enter the same gate. The gate wait and `consumer.value` do not react to cancel, so the time limit of the test cannot stop the wait, and the whole run stops with 0% CPU.

    The flock path of my first comment is real in theory, but run 6 did not show it (no thread blocked in flock). I will record it as a new task and not fix it here.

    Plan: TDD test in KanbanHostTests (next to `closedEngineEndsMovedWatch`): `adopt` on a closed engine must return before the consumer task of the moved watch ends. Fix: `adopt` stops the moved watch and cancels its task, with no wait for the task (the task then applies nothing, because the engine is closed).
  timestamp: 2026-10-16T06:10:52.003006+00:00
- actor: claude-code
  id: 01m51nkkymck7e2n5rmwfrkhk9
  text: |-
    TDD done for the cause.

    - New test `KanbanHostTests.closedEngineDoesNotWaitForMovedConsumer` ("A closed engine ends a moved watch with no wait for the task of the watch, which can wait for the engine gate"). It closes an engine, gives `adopt` a moved watch whose task does not end on cancel (helper `HeldConsumer`, the same as a task that waits for the gate), and expects `adopt` to return before the test releases that task. The test fails and does not hang: it releases the task after 10 s.
    - RED (one run, `swift test --filter KanbanHostTests/closedEngine`): "Expectation failed: isAdoptedFirst", failed after 10.044 s.
    - Fix in Sources/FoundationModelsKanban/Tool/BoardEngine.swift: new `BoardWatch.stop()` (stop the watcher and cancel the task, no wait); `end()` now calls `stop()` and then waits; `BoardEngine.adopt(_:)` on a closed engine calls `moved.stop()`, not `moved.end()`. The task of the moved watch then gets the gate after the caller, and applies nothing, because the engine is closed.
    - GREEN (one run, same filter): 2 tests passed (the new test in 0.032 s, and the old `closedEngineEndsMovedWatch`).
    - New task ^vm0j67z records the flock path from my first comment (not seen in a run, not fixed here).
    - Removed my first draft test for the flock path (BoardLockPoolTests.swift); its design is in ^vm0j67z.

    Next: 10 full `swift test` runs in a row with the fix.
  timestamp: 2026-10-16T06:15:21.812298+00:00
- actor: claude-code
  id: 01m51pcmtv9z90pf0q9z5n647d
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsKanban/Tool/BoardEngine.swift (new `BoardWatch.stop()`, `end()` calls it, closed-engine `adopt(_:)` uses `stop()` and does not wait for the task of the moved watch), Tests/FoundationModelsKanbanTests/Tool/KanbanHostTests.swift (new test `closedEngineDoesNotWaitForMovedConsumer`, helper `HeldConsumer`, two named limits). RED: 1 issue, "Expectation failed: isAdoptedFirst" after 10.044 s. GREEN: 2 of 2 passed. With the fix, 10 full runs in a row (`timeout 900 swift test`, run 1 with build, runs 2 to 10 `--skip-build`): each "Test run with 1563 tests in 126 suites passed" (39.9 s to 67.3 s), 0 issues, no warnings other than the accepted "missing creator" warning. Before the fix, run 6 of 6 hung at 0% CPU (sample and `swift-inspect dump-concurrency` in the session scratchpad runs/ folder).
    - cause: `BoardEngine.adopt(_:)` on a closed engine called `BoardWatch.end()` inside the engine serial gate; `end()` waited for the task of the moved watch, and that task waited for the same gate.
    - follow-up: ^vm0j67z (blocking flock wait on a cooperative thread, static finding only). Run 3 at HEAD failed once with 140 time-limit issues at load average about 90; it finished, so it is not this hang, and it did not come back in the 10 runs with the fix.
    - next: /review
  timestamp: 2026-10-16T06:29:01.915505+00:00
- actor: claude-code
  id: 01m51pnq5gjm04v2t5m04cg7rx
  text: |-
    ### test — green
    - evidence: swift build complete, 0 warnings except the allowed SwiftPM "missing creator" warning. swift test: 1563 tests in 126 suites passed, 0 failures, 0 skipped (1 run). Both new closed-engine tests passed. Integration tests (swift test --package-path IntegrationTests with the scratch path): 3 tests in 3 suites passed, 0 failures, 0 skipped.
    - logs: scratchpad files build.log, test-run1.log, test-integration.log
    - next: review
  timestamp: 2026-10-16T06:33:59.216871+00:00
- actor: claude-code
  id: 01m51prah4f9f9qgp6jjamgw2g
  text: |-
    ### commit — changed
    - evidence: local commit of BoardEngine.swift, KanbanHostTests.swift, and the .kanban/tasks/ files (including new task ^vm0j67z). Sha is in git log.
    - next: review
  timestamp: 2026-10-16T06:35:24.580476+00:00
- actor: claude-code
  id: 01m51q21ggzq3yvcczxjx16dtd
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (7010ba3). 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. 2 source files reviewed. The .reviewignore rule excluded 6 .kanban files.
    - next: None. The task moved to done. Follow-up ^vm0j67z records the blocking flock risk.
  timestamp: 2026-10-16T06:40:43.024171+00:00
- actor: claude-code
  id: 01m51q2ewnqvz5r50k61msq628
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — BoardEngine.swift (BoardWatch.stop, adopt on closed engine), KanbanHostTests.swift; hang reproduced and diagnosed with swift-inspect; 10/10 full runs green; follow-up ^vm0j67z
    - test: green — swift test, 1563 passed; IntegrationTests 3 passed
    - commit: 7010ba3
    - review: clean — 0 findings
  timestamp: 2026-10-16T06:40:56.725034+00:00
position_column: done
position_ordinal: ff9480
title: Find why a full swift test run can hang at 0% CPU
---
## What
During the test step of ^x020t0g, one full `swift test` run made no progress for 30 minutes at 0% CPU, and its output was lost. The tester stopped the run. The next full run, with the same code, passed 1552 tests in 62 seconds. An earlier session also saw a test process that did not stop. A hang at 0% CPU can be a deadlock (for example a lock, a continuation that never resumes, or an FSEvents wait), not machine load.

Possible areas: the host FSEvents stream and router (S/Observe/FolderStreams.swift, ^swk9c8n), the WatcherBudget test trait, the serial gate in KanbanGraph, and git runs in Git.run.

## Change
- Run the full suite many times with output saved to a file, and with a time limit on the whole run. When a run hangs, take a sample of the process (`sample <pid>`) to see which threads wait and where.
- Fix the cause. Add a test that fails on the hang.

## Acceptance Criteria
- [x] The cause of the hang is found and recorded on this card.
- [x] The cause is fixed, or a new task records the fix.
- [x] 10 full `swift test` runs in a row finish.

## Tests
- [x] A test for the cause, in temporary fixture folders (never the `.kanban/` of this repo).
- [x] `swift test` passes.