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
- actor: claude-code
  id: 01m5adr0kag2wabe4qcnbt7w2c
  text: |-
    ### review — findings
    - evidence: review sha 1ae2a1c~1..1ae2a1c; 1 finding (1 confirmed, 0 refuted) — Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift:485 (reuse/reuse)
    - next: implement the open item in the "Review Findings (2026-10-19 10:49)" section. The task stays in review.
  timestamp: 2026-10-19T15:51:07.114763+00:00
- actor: claude-code
  id: 01m5adrhk1qnyatch2gqcpw985
  text: |-
    ### finish iteration 1 — findings
    - implement: not run — the code is in WIP commit 1ae2a1c
    - test: green — swift test, 1613 passed (same tree as the ^nxrqcgn run)
    - commit: no-change — the code was already in 1ae2a1c
    - review: findings — Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift:485
  timestamp: 2026-10-19T15:51:24.513021+00:00
- actor: claude-code
  id: 01m5adzddran6hak3j7za99skj
  text: |-
    Review finding EventLogTests.swift:485 (reuse/reuse) is fixed.
    - New internal helpers in S/Events/BoardLock.swift on `EventLog`: `openLockFile()` (the one `open` with `O_RDWR | O_CREAT | O_CLOEXEC` and `lockFileMode`; it throws `lockFailed`) and `static tryLock(on:)` (the one `flock(LOCK_EX | LOCK_NB)`). `callFlock(on:operation:)` moved from `LockedFile` to `EventLog` as `fileprivate`, so that `tryLock` and the blocking wait share it.
    - `LockedFile.lock(of:)` and `LockedFile.waitForLock(on:)` now call these helpers.
    - Same cause, second place in the test file: `EventLogTests.isLockFree(of:)` also repeated the open and the `flock(LOCK_EX | LOCK_NB)`. It now calls `openLockFile()` and `tryLock(on:)` too. It also no longer calls `close(-1)` when the open fails. `holdLockWithOwnDescriptor(of:)` calls the helpers and keeps its raw descriptor for the release on its own thread.
    - After the change, `rg 'flock\(|O_CLOEXEC|lockFileMode' Sources Tests IntegrationTests` finds only BoardLock.swift.
    - RED: `swift build --build-tests` failed because `openLockFile` and `tryLock` did not exist. GREEN: `swift test --filter EventLogTests` passed 21 tests. Full `swift test`: 1613 tests in 132 suites passed. The only compiler warning is the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-19T15:55:09.624447+00:00
- actor: claude-code
  id: 01m5adzfd43awyn2cbzcvb2tge
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsKanban/Events/BoardLock.swift, Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift. `swift test`: 1613 tests in 132 suites passed, 0 failures, only the accepted "missing creator" warning. Finding EventLogTests.swift:485 is checked.
    - next: /test, then /review. The task stays in doing.
  timestamp: 2026-10-19T15:55:11.652459+00:00
- actor: claude-code
  id: 01m5ae3r6k0yccb7x2kemyhhrw
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (3e5c099): 1 finding, 1 confirmed, 0 refuted — Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift:141 (test-integrity/no-test-cheating). The prior finding at EventLogTests.swift:485 is checked.
    - next: Make an open failure in `isLockFree` fail the test, not return "lock is held". Then run review again.
  timestamp: 2026-10-19T15:57:31.731714+00:00
- actor: claude-code
  id: 01m5ae437vtf3djmm0k9kz3k3g
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 2 files (BoardLock.swift, EventLogTests.swift)
    - test: green — swift test, 1613 passed
    - commit: 3e5c099
    - review: findings — Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift:141
  timestamp: 2026-10-19T15:57:43.035504+00:00
- actor: claude-code
  id: 01m5aeaqazmqcxms5qy7ysqy19
  text: |-
    Review finding EventLogTests.swift:141 (test-integrity/no-test-cheating) is fixed. Only the test file changed.
    - `isLockFree(of:)` now has `throws(EventLogError)` and no `catch`. An open failure from `openLockFile()` goes to the caller.
    - Same cause, second place in the same helper: a `tryLock` code that is not `0` and not `EWOULDBLOCK` also became "lock is held". Now only `EWOULDBLOCK` gives `false`. Each other code throws `EventLogError.lockFailed(path:code:)`.
    - `waitUntil` now takes `() async throws -> Bool`. An error from the check ends the wait at once and goes to the test. The wait still has no deadline (divergence.md S6). The callers in KanbanHostTests, FolderStreamsTests, TestGate, BoardKeyTests and ScanCacheTests give closures that do not throw, so they compile with no change.
    - `waitForLockRelease` calls `try isLockFree(of:)`. `lockExcludesOtherDescriptor` and `expectOneLockHolds` use `#expect(try ...)`.
    - New test `lockCheckFailsWhenLockFileCannotOpen`: a board with no `.kanban` directory. It expects `lockFailed(path:, code: ENOENT)`.
    - I found no other helper in EventLogTests.swift that changes an error into a wait. `TemporaryDirectory.deinit` uses `try?`, but it is not a wait, and a `deinit` cannot throw.
    - RED: the new test failed: "an error was expected but none was thrown and \"false\" was returned". GREEN: `swift test --filter EventLogTests`: 22 tests passed. Full `swift test`: 1614 tests in 132 suites passed. The only warning is the accepted SwiftPM "missing creator" warning.
    - Note: the validator dump has 12098 lines. I read the swift and test-integrity rule sections in full. I did not read all of the other sections.
  timestamp: 2026-10-19T16:01:20.223659+00:00
- actor: claude-code
  id: 01m5aeas6ka0qvspnaxekhp00g
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift. RED: lockCheckFailsWhenLockFileCannotOpen failed (false returned, no error). GREEN: EventLogTests 22 passed. `swift test`: 1614 tests in 132 suites passed, 0 failures, only the accepted "missing creator" warning. Finding EventLogTests.swift:141 is checked.
    - next: /test, then /review. The task stays in doing.
  timestamp: 2026-10-19T16:01:22.131999+00:00
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

## Review Findings (2026-10-19 10:49)

> Scope: `review sha 1ae2a1c~1..1ae2a1c` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 3 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `Package.resolved` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift:485` `reuse/reuse` — The test helper `holdLockWithOwnDescriptor` repeats the production lock sequence: it opens the lock file with `O_RDWR | O_CREAT | O_CLOEXEC` and calls `flock(LOCK_EX | LOCK_NB)`, which is the same steps as `LockedFile.lock(of:)` and `callFlock` in BoardLock.swift. If the open flags or lock mode change in production, this copy can silently diverge and the test would stop testing the real lock path. Extract the open-and-try-lock step into one internal helper that both `LockedFile.lock(of:)` and the test call, for example `openLockFile(of:)` plus a non-blocking `tryLock(descriptor)`. The test can then call the shared helper and keep its own raw descriptor for release on another thread. If the test must stay separate, add a comment stating why it duplicates the production open flags.

## Review Findings (2026-10-19 10:56)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 6 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

- [x] `Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift:141` `test-integrity/no-test-cheating` — The `catch` in `isLockFree` swallows every error from `openLockFile()` and returns `false`, which means 'lock is held'. `waitForLockRelease` calls `isLockFree` through `waitUntil`, and `waitUntil` has no deadline. If the lock file can never be opened, the wait never ends and the test hangs instead of failing. The failure is hidden, not proven. Do not map an open failure to 'not free'. Let the error propagate, for example make `isLockFree` a throwing function and use `try log.openLockFile()` without the `catch`, or make the wait fail after a deadline. Then an open failure fails the test at once and the test does not hang.
