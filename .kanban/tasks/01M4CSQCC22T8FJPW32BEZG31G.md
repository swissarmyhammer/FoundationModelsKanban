---
comments:
- actor: wballard
  id: 01m4csykzpp8pras48nba0z3vx
  text: |-
    Research done. Findings:
    - EventLogTests: `isLockReleased` calls `flock(LOCK_EX)` with no `LOCK_NB`. `secondLockWaitsForFirst` awaits `waiter.value` of a detached task that blocks in the production `EventLog.lock()` (a blocking `flock`). `Task.value` of an unstructured task does not react to cancellation, so `.timeLimit` cannot stop either wait. The test also has no `.timeLimit`.
    - `Git.run` (Identity/BoardKey.swift, the code that the card calls `BoardKey.run`) reads stdout to its end, then stderr, then calls `waitUntilExit()`. A git command (or an alias, a hook, a credential helper) that writes more than the pipe buffer (64 KiB) to stderr before it closes stdout blocks on the write while this code blocks on the stdout read: a deadlock. Also the child gets the stdin of the test process, and no wait has a deadline. Each test that makes a repo (`GitSandbox.runGit`, BoardKeyTests, BoardLocatorTests, PortabilityTests, CrossRepoReadTests) goes through `Git.run`.
    - BoardWatcherTests `hasBatch` already races the batch stream against `Task.sleep(batchTimeLimit)` in a task group; `for await` on an `AsyncStream` stops on cancellation, so it is bounded. No semaphore, `DispatchGroup.wait`, `readLine`, or continuation wait is in the tests.
    - Production `BoardLock.waitForLock` is a blocking `flock` by design (the commit lock). It is out of scope; only the test code that calls it directly is bounded.
    Plan: a named-deadline poll for the lock checks and for the second-lock wait; `Git.run` reads both pipes at the same time, gives git `/dev/null` as stdin, and waits for the end of git and both pipes with a named time limit (new error `BoardKeyError.gitTimedOut`).
  timestamp: 2026-10-08T03:47:13.526313+00:00
- actor: wballard
  id: 01m4cv5t3sq3ykkbrm1ndweq02
  text: |-
    Discovery during the first 10-run check (all 10 runs failed, 36-37 issues each, no hang):
    - The first version of the new `Git.run` read the two pipes on `DispatchQueue.global()`. In the full parallel suite, many tests call the synchronous `Git.run` from Swift tasks, and each call blocks its thread in `DispatchGroup.wait`. The global queues and the Swift concurrency pool share one small group of threads (about one for each processor). When all of them block, the pipe reads never start, so each git command (even `git init --quiet`) waited the full 30 s limit and threw `gitTimedOut`. The pure `Task.sleep` test `lockWaitEndsAtDeadline` also took 60 s in those runs, which confirms the thread starvation.
    - Fix: each pipe read runs on its own serial `DispatchQueue(label:)`. A serial queue gets a new thread when the pool is full. `terminationHandler` of `Process` is not affected (the GREEN run proves it).
    - New regression test `BoardKeyTests.parallelCommandsAllEnd`: 4 x processor-count tasks run `git --version` at the same time with a 10 s limit. With `DispatchQueue.global()` it failed after 40 s with `gitTimedOut`; with the serial queues it passes in 0.04 s.
    - Lesson: never put a blocking read on a global queue when the caller blocks a Swift concurrency thread to wait for it.
  timestamp: 2026-10-08T04:08:37.753480+00:00
- actor: wballard
  id: 01m4cvb6x4y2mwgy51nmr6y4jg
  text: |-
    ### implement — changed
    - evidence: 3 files. Sources/FoundationModelsKanban/Identity/BoardKey.swift (`Git.run`: stdin is /dev/null; stdout and stderr are read at the same time by `PipeReader`, each on its own serial queue; one `DispatchGroup.wait` with the named limit `Git.defaultTimeLimit` (30 s) covers the exit of git and both reads; new `BoardKeyError.gitTimedOut(arguments:)`). Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift (`isLockReleased(of:within:)` polls `LOCK_NB` through the new `becomesTrue(within:_:)` with `retryPause` 10 ms and `lockWaitLimit` 10 s; `heldLockMessage(of:)` names the lock file; `secondLockWaitsForFirst` waits for the second lock with the deadline before it awaits the detached task; new test `lockWaitEndsAtDeadline`). Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift (new tests `largeErrorOutputDoesNotBlock`, `slowCommandTimesOut`, `parallelCommandsAllEnd`).
    - RED: `lockWaitEndsAtDeadline` hung (stopped by a 45 s shell limit). `largeErrorOutputDoesNotBlock` hung (stdout/stderr deadlock, stopped at 40 s). `slowCommandTimesOut` failed with 2 issues (no throw, 5.09 s). `parallelCommandsAllEnd` failed after 40 s with `gitTimedOut` while the reads used `DispatchQueue.global()`.
    - GREEN: EventLogTests 17 pass; the 3 git tests pass (0.013 s, 0.304 s, 0.037 s).
    - 10-run check, `runloop.sh bezg2 10` (`swift test --skip-build`, 120 s limit each): 10 of 10 pass, 906 tests in 58 suites each, about 6.6 s each, 0 issues, no hang.
    - `swift build --build-tests`: only the known `missing creator` warning. No line longer than 120 characters in the 3 files. periphery: no item in Sources; the same 7 earlier items in test files that this change did not touch.
    - next: /review
  timestamp: 2026-10-08T04:11:34.692057+00:00
position_column: doing
position_ordinal: '80'
title: 'Tests: bound the blocking flock wait in EventLogTests.isLockReleased'
---
## What
One full `swift test` run hung for 30 minutes with no output during the ^emwcz5z work. 65 later runs (normal, suspect suites only, and under CPU load) did not hang, so the cause is not confirmed.

The most probable cause is `isLockReleased` in `Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift`. It calls `flock(descriptor, LOCK_EX)` with no `LOCK_NB`. The call is a blocking system call in a synchronous test, so Swift Testing's `.timeLimit(.minutes(1))` cannot stop it. A child process (for example `git`, started by a parallel test) can hold a copy of the lock file descriptor for a short time. If that copy is held for a long time, the whole run waits with no output.

Change the wait so that it always ends. For example, try `flock(descriptor, LOCK_EX | LOCK_NB)` in a loop with a short pause between tries, and stop at a named deadline. When the deadline passes, the test fails with a clear message and does not hang. Check the other tests for blocking calls that `.timeLimit` cannot stop (for example in `BoardWatcherTests`, `BoardLocatorTests`, `PortabilityTests`, and `BoardKey.run`), and bound them the same way.

## Acceptance Criteria
- [x] No test helper calls a blocking system call that can wait with no end.
- [x] When a lock stays held, the test fails within its deadline with a message that names the lock file.

## Tests
- [x] Add a test in `Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift`: hold the lock on a second descriptor for longer than the deadline, and check that the bounded wait returns "not released" within the deadline.
- [x] Run the full `swift test --skip-build` 10 times in a row with a 120 s limit on each run; expect all pass and no hang.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.