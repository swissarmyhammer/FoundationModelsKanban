---
position_column: todo
position_ordinal: b580
title: Git.run blocks a Swift cooperative thread while git runs
---
## What
`Git.run` (Sources/FoundationModelsKanban/Identity/BoardKey.swift) starts git and then blocks its thread in `DispatchGroup.wait` until git ends. The engine calls it synchronously from async code: `BoardKey.read(fromRepoAt:)` is the `readingKeyWith` reader of `KanbanGraph` and of `BoardLocator.scan`. Many tests also call it through `GitSandbox.runGit` and `BoardKey.read` from async test functions.

Each call blocks one thread of the Swift cooperative pool, which has about one thread for each processor. In a full parallel `swift test` run, these blocked threads make other async waits late (found in ^aazpa67: a 300 ms deadline wait ended 3.21 s after its start, because its `Task.sleep` wake-ups had no free pool thread).

## Approach
Give `Git.run` an async form that waits for the end of git with no blocked thread (for example a continuation that `terminationHandler` and the two pipe reads resume), and make `BoardKey.read`, the `readingKeyWith` closure type, `BoardLocator.scan`, and the `KanbanGraph` set-up async. Keep the named time limit and `BoardKeyError.gitTimedOut`.

## Acceptance Criteria
- [ ] No production path blocks a cooperative thread while git runs.
- [ ] The test helpers that run git (`GitSandbox.runGit`) do not block a cooperative thread.
- [ ] `BoardKeyTests.parallelCommandsAllEnd` and the time-out tests still pass.

## Tests
- [ ] A test that runs many git commands at the same time as a `Task.sleep` wait shows that the sleep wakes near its deadline.
- [ ] Run the full root `swift test` 5 times; expect all pass.