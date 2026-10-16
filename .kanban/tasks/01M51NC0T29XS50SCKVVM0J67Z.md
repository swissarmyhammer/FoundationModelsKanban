---
assignees:
- claude-code
position_column: todo
position_ordinal: ba80
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
- [ ] A test that holds the lock of a temporary board with a file descriptor of the test, starts 2 x `activeProcessorCount` tasks that call `await log.lock()`, and expects that each task starts before a thread of the test releases the lock. With the blocking wait, the tasks start only after the release, so the test fails (and does not hang).
- [ ] `swift test` passes.