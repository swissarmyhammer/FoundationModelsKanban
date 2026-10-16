---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m51yrg7c8wden4rbhzjgyd9t
  text: |-
    Research:
    - `EventLog.lock()` and `EventLog.lock(sortedByKey:)` are in S/Events/BoardLock.swift. `LockedFile.init(of:)` opens the lock file and calls `waitForLock`, which loops on `flock(LOCK_EX)` and blocks the thread.
    - The only production caller is `commit(_:along:)` in S/Tool/Commit.swift. It is already async. The other callers are in T/Events/EventLogTests.swift (lockExcludesOtherDescriptor, lockWaitEndsAtDeadline, secondLockWaitsForFirst, expectOneLockHolds).
    - ^dqxhqwy (Git.run) used process exit handlers and a cancel handler. That fits a process, not a `flock`. The fitting pattern is the test helper `EventLogTests.runOnOwnThread`: `withCheckedContinuation` plus `Thread.detachNewThread`.
    - Plan for cancel: the wait does not respond to cancel (divergence.md Q24: the wait has no time limit). The detached thread always resumes the continuation with its result, and the caller always gets the lock and releases it, or the descriptor is closed on a failure. Thus a cancel cannot leak the lock or a thread. The wait does not wait for the engine gate, so it cannot deadlock with close or adopt.
    - After the change, `secondLockWaitsForFirst` can call `await log.lock()` directly, so `runOnOwnThread` will have no caller and must go.
  timestamp: 2026-10-16T08:55:19.020393+00:00
- actor: claude-code
  id: 01m51z51zn79tn580adzqyhb07
  text: |-
    Implementation landed.
    - RED: the new test `EventLogTests.lockWaitsBlockNoPoolThread` failed with the blocking wait: `lateStartCount` was 18 (2 x activeProcessorCount tasks), and the test ended after 10.0 s with no hang. The release thread is a thread of its own, so it releases the lock also when each pool thread is blocked.
    - GREEN: the same test passed in 0.027 s.
    - Change: `EventLog.lock()` and `EventLog.lock(sortedByKey:)` are async. `LockedFile.lock(of:)` replaces the old throwing init. `waitForLock` tries `flock(LOCK_EX | LOCK_NB)`. On `EWOULDBLOCK` it waits with `flock(LOCK_EX)` on `Thread.detachNewThread` and resumes a `withCheckedContinuation`. `callFlock(on:operation:)` keeps the EINTR loop for the two calls. The lock order of `lockOrder(of:)` and the wait with no time limit do not change.
    - Cancel: the wait does not respond to cancel. The thread always resumes the continuation with its result. The caller then gets a `LockedFile` that the end of `BoardLock` releases, or the descriptor is closed on a failure. Thus a cancel cannot leak the lock. The wait does not wait for the engine gate, so it adds no deadlock with close or adopt (7010ba3).
    - Test helper `runOnOwnThread` had no caller after `secondLockWaitsForFirst` started to call `await log.lock()`, so I removed it. The shared state of the new test is `LockWaitProgress`, a `Sendable` class over a `Mutex`, because `Mutex` is not copyable and a detached thread must capture it.
    - divergence.md S6 now describes the async wait, the thread of its own, and the cancel behavior.
    - Full `swift test`: 1568 tests in 126 suites passed. The only compiler warning is the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-16T09:02:10.421589+00:00
- actor: claude-code
  id: 01m51z53yar627fhcwtx9acq1q
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/Events/BoardLock.swift, Sources/FoundationModelsKanban/Tool/Commit.swift, Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift, divergence.md. RED: lockWaitsBlockNoPoolThread failed (lateStartCount 18). GREEN: passed in 0.027 s. `swift test`: 1568 tests in 126 suites passed, 0 failures, only the accepted "missing creator" warning.
    - next: /review
  timestamp: 2026-10-16T09:02:12.426838+00:00
- actor: claude-code
  id: 01m521cbe447rnwa0vqajgj9dj
  text: |-
    ### test - red
    - evidence: swift build clean (only the allowed mlx-swift missing creator warning). Full swift test ran 3 times in parallel: 1568 tests, 236, 263 and 254 issues. Almost all issues are the 60 second time limit or FSEvents and git waits, in many suites. Machine load average was 110 to 217.
    - baseline: HEAD without the change (git archive copy in the scratchpad) ran the full suite with 230 issues, and PathRefCacheTests and ReplacedRepoTests failed there with the same 60 second time limits. So the failures are not caused by the change of this task.
    - serial run (--no-parallel): 1568 tests, 3 issues, all 60 second time limits (PathRefCacheTests, ReplacedRepoTests). These suites alone again gave time limits, and they do so on HEAD too.
    - suites that failed in a full run and passed alone: CrossRepoTransferTests, BoardKeyTests, ScanCacheTests, KanbanGraphTests, BoardWatcherTests, KanbanHostTests.
    - EventLogTests alone 5 times: 22 tests passed each time, no flaky behavior.
    - IntegrationTests with the scratch path: 3 tests in 3 suites passed.
    - No source change was made. No time limit was raised. No hang at 0% CPU.
    - next: run the full suite again when the machine load is low.
  timestamp: 2026-10-16T09:41:06.628439+00:00
position_column: doing
position_ordinal: '80'
title: Do not block a thread of the cooperative pool while a commit waits for the board lock
---
## What
Found during ^je3gkw8 by a static review. A full test run did not show this hang yet, but the path is real.

- `Commit.commit(_:along:)` calls `EventLog.lock(sortedByKey:)`. `LockedFile.waitForLock` (S/Events/BoardLock.swift) calls `flock(LOCK_EX)`, which blocks the thread. The caller is async, so the blocked thread is a thread of the Swift cooperative pool.
- While a commit holds the lock, it awaits `applyChangedFiles()` -> `LiveGraph.apply` -> `BoardLoader.readFiles`, which adds child tasks to a task group. These child tasks, and the resume after the await, need a free pool thread.
- When other commits in the same process (other engines on the same board, or related boards) wait in `flock` for the same lock, and these waits take all pool threads (about one for each processor), the holder cannot continue. Then the process stops with 0% CPU, and a test time limit cannot fire.
- EventLogTests has a note that a `flock` wait must not run on the cooperative pool. ^dqxhqwy fixed the same type of problem for Git.run.

## Change
- Make `EventLog.lock()` and `EventLog.lock(sortedByKey:)` async. Try `flock(LOCK_EX | LOCK_NB)` first. When the lock is busy (`EWOULDBLOCK`), wait with `flock(LOCK_EX)` on a thread of its own (`Thread.detachNewThread`) and resume a continuation. Keep the lock order of `lockOrder(of:)`, and keep the wait with no time limit (divergence.md S6).
- Update the callers (Commit.swift, EventLogTests) and the S6 text in divergence.md.

## Tests
- [x] A test that holds the lock of a temporary board with a file descriptor of the test, starts 2 x `activeProcessorCount` tasks that call `await log.lock()`, and expects that each task starts before a thread of the test releases the lock. With the blocking wait, the tasks start only after the release, so the test fails (and does not hang).
- [x] `swift test` passes.