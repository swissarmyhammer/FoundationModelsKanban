---
position_column: todo
position_ordinal: b380
title: 'Tests: bound the blocking flock wait in EventLogTests.isLockReleased'
---
## What
One full `swift test` run hung for 30 minutes with no output during the ^emwcz5z work. 65 later runs (normal, suspect suites only, and under CPU load) did not hang, so the cause is not confirmed.

The most probable cause is `isLockReleased` in `Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift`. It calls `flock(descriptor, LOCK_EX)` with no `LOCK_NB`. The call is a blocking system call in a synchronous test, so Swift Testing's `.timeLimit(.minutes(1))` cannot stop it. A child process (for example `git`, started by a parallel test) can hold a copy of the lock file descriptor for a short time. If that copy is held for a long time, the whole run waits with no output.

Change the wait so that it always ends. For example, try `flock(descriptor, LOCK_EX | LOCK_NB)` in a loop with a short pause between tries, and stop at a named deadline. When the deadline passes, the test fails with a clear message and does not hang. Check the other tests for blocking calls that `.timeLimit` cannot stop (for example in `BoardWatcherTests`, `BoardLocatorTests`, `PortabilityTests`, and `BoardKey.run`), and bound them the same way.

## Acceptance Criteria
- [ ] No test helper calls a blocking system call that can wait with no end.
- [ ] When a lock stays held, the test fails within its deadline with a message that names the lock file.

## Tests
- [ ] Add a test in `Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift`: hold the lock on a second descriptor for longer than the deadline, and check that the bounded wait returns "not released" within the deadline.
- [ ] Run the full `swift test --skip-build` 10 times in a row with a 120 s limit on each run; expect all pass and no hang.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.