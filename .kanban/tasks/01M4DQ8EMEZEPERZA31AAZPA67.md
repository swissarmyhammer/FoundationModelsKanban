---
comments:
- actor: wballard
  id: 01m4dqr77gwxcgz9wvcznxvjv0
  text: |-
    Research done. Findings:
    - `becomesTrue(within:_:)` checks the deadline at the top of each loop pass, then calls the condition, then `Task.sleep(retryPause)`. The condition (`isLockFree`) uses `LOCK_NB`, so it does not block. The loop stops only when `ContinuousClock.now >= deadline`, so `waited >= heldLockWaitLimit` is always true. `ContinuousClock` is monotonic.
    - `Task.sleep` does not block a thread, but its wake-up and the resume of the test after the `await` need a free thread of the Swift cooperative pool. In a full parallel run, many tests block pool threads: each synchronous `Git.run` (GitSandbox, `BoardKey.read`, engine set-up with `readingKeyWith: BoardKey.read`) blocks its thread in `DispatchGroup.wait` until git ends, and `secondLockWaitsForFirst` blocks a pool thread in `Task.detached { try log.lock() }` (a blocking `flock`) for at least `holdDuration`. When the pool is full, each wake-up of the wait comes late, so the wait ends seconds after its deadline. ^bezg31g saw the same effect at a larger scale (a pure `Task.sleep` test took 60 s when the pool was starved).
    - Thus the 3.21 s is scheduling delay after the deadline, not a wait that ignores the deadline. The upper bound `heldLockWaitLimit + deadlineTolerance` (2.3 s) measures machine load, not the deadline.
    - `Git.run` blocks a cooperative thread also in production (the engine reads board keys synchronously from async paths). To change that, `BoardKey.read`, `readingKeyWith`, `BoardLocator.scan` and the `KanbanGraph` set-up must become async. That is a large change outside this card, so it gets a new task.
    Plan: the deadline test asserts "not released", `waited >= heldLockWaitLimit`, and `waited < hangLimit` (a generous named bound that proves "no hang"), and gets `.timeLimit(.minutes(1))` like the other lock tests, so a wait with no deadline fails and does not hang. `deadlineTolerance` goes. `secondLockWaitsForFirst` gets the blocking second lock on a thread of its own, off the cooperative pool.
  timestamp: 2026-10-08T12:28:01.136349+00:00
- actor: wballard
  id: 01m4dr141n94ca5zad4a6ja1nt
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift.
      - Cause: `becomesTrue(within:_:)` ends at its deadline (monotonic `ContinuousClock`, non-blocking `LOCK_NB` check), but each `Task.sleep` wake-up and the resume of the test need a free thread of the Swift cooperative pool. In a full parallel run, other tests block pool threads (synchronous `Git.run` in `DispatchGroup.wait`, and the blocking `flock` of `secondLockWaitsForFirst` in `Task.detached`), so the measured wait is the deadline plus scheduling delay. The old bound `heldLockWaitLimit + deadlineTolerance` (2.3 s) measured machine load.
      - Change: `lockWaitEndsAtDeadline` asserts `!isReleased`, `waited >= heldLockWaitLimit`, and `waited < hangLimit` (new private `hangLimit`, 30 s, from `hangLimitSeconds`), and has `.timeLimit(.minutes(1))`. `deadlineTolerance` and `deadlineToleranceSeconds` are removed. New private `runOnOwnThread(_:)` runs blocking work on a new `Thread` and awaits a continuation; `secondLockWaitsForFirst` uses it for the blocking second lock, so that test no longer blocks a pool thread.
      - RED (temporary, then restored): with the loop condition changed to `ContinuousClock.now < deadline || true` (no deadline), `swift test --skip-build --filter EventLogTests/lockWaitEndsAtDeadline` failed: "Time limit was exceeded: 60.000 seconds", failed after 60.004 s with 1 issue. No hang.
      - GREEN: `--filter EventLogTests`: 18 tests passed in 0.304 s (deadline test 0.304 s).
      - `swift build --build-tests`: only the accepted `missing creator` warning. swiftlint `no_magic_numbers` (allowed 0, 1, -1, 100) and `line_length` 120: 0 findings. Default swiftlint `file_length`, `type_body_length`, `trailing_comma` warnings were already in the file at HEAD.
      - 5 full runs, `timeout 120 swift test --skip-build`: each 961 tests in 67 suites passed, 0 issues. Times: 8.018 s, 7.889 s, 8.144 s, 8.294 s, 8.221 s. Deadline test (300 ms deadline): 2.040 s, 2.032 s, 1.824 s, 1.896 s, 2.201 s. These numbers show 1.5 s to 1.9 s of pool delay after the deadline in a normal full run, so the old 2.3 s bound was close to the edge.
    - discovered: new task ^jkr7qm8 (Git.run blocks a Swift cooperative thread while git runs). That is the source of most pool load, in production and in tests.
    - next: /review
  timestamp: 2026-10-08T12:32:52.789311+00:00
- actor: wballard
  id: 01m4dr7g8yq43eqwhdvcy81c5q
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (24c5e9c). 0 findings, 0 confirmed, 0 refuted. 1 file reviewed. 6 .kanban files not reviewed (.reviewignore).
    - next: none. The task is in done.
  timestamp: 2026-10-08T12:36:21.918558+00:00
- actor: wballard
  id: 01m4dr7pdnny19603rex6c2c8j
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 1 file (Events/EventLogTests.swift); cause = Task.sleep wake-up waits for a free cooperative-pool thread
    - test: green — swift test 3 runs, 961 passed each (8.2 s, 7.9 s, 8.3 s); deadline test 1.8 to 2.0 s; build warnings only the 2 accepted kinds
    - commit: 24c5e9c
    - review: clean — 0 findings
  timestamp: 2026-10-08T12:36:28.213506+00:00
position_column: done
position_ordinal: b880
title: 'Flaky: EventLogTests held-lock wait exceeds deadline tolerance under load'
---
## What
In a full root `swift test --skip-build` run on 2026-10-08 (during ^7j3aar6), the test "The wait for a released lock ends at its deadline while a different descriptor holds the lock" in `Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift` failed:

`Expectation failed: waited < Self.heldLockWaitLimit + Self.deadlineTolerance` — `waited` was 3.21 s, the limit is 2.3 s (300 ms wait limit + 2 s tolerance).

The next two full runs passed with no code change. The failure is a timing flake under parallel load. No source change of ^7j3aar6 touches the root package.

## Acceptance Criteria
- [x] Find why the bounded wait of `isLockReleased(of:within:)` can take more than 3 s under a parallel full-suite run.
- [x] The test does not fail under a full parallel `swift test` run, and it still fails when the wait does not end at its deadline.

## Tests
- [x] Run the full root `swift test` 5 times; expect all pass.