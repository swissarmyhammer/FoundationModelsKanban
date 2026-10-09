---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4h39d5qfsg05qgg89cym6v5
  text: |-
    Research done.
    - The watcher tests are in BoardWatcherTests. `BatchRecorder` is the batch observer hook of `KanbanGraphTests.makeGraph(at:observingBatchesWith:)`. `BoardWatcherTests.query(_:reaches:on:recordedBy:)` runs a query again after each applied batch, so the test waits on batches and not on a sleep.
    - Helpers to reuse: `SubscriptionTests.nextTxn(of:)`, `SubscriptionTests.latestTxn(on:)`, `SubscriptionTests.writeDoneMove(of:mintingFrom:in:)` (uses `ReplayTests.movePatch`), `BoardWatcherTests.writeLaterTitle` (uses `ReplayTests.titlePatch`), `ChangeFilterTests.history(filteredBy:count:on:)` with `ChangeRow`/`UpdateRow` for exact compare, `CommentTests.taskQuery(of:selecting:)`, `CrossRepoFixture.addTask(with:on:)`, `AddUpdateTaskTests.doneColumn`.
    - Plan: add the task with `addTask` on the engine, then append two lines of a second process (`GitGraphFixture.secondEngineIDs`): a title line and a move to `done`. Each line has its own transaction. Wait until the task query gives the new title and column. Then compare `history(filter: "^id")` with the exact list: the addTask transaction (CREATED), then the two appended transactions (UPDATED).
  timestamp: 2026-10-09T19:47:21.911516+00:00
- actor: claude-code
  id: 01m4h3e74s8qtekbcw782qjneb
  text: |-
    Implementation landed: test `mergedLinesUpdateTaskAndHistory` in BoardWatcherTests.
    - The test passed on its first run, so the production code already does this. No change in LiveGraph.swift or in the history resolver was necessary.
    - To prove that the test can fail, a temporary mutation in `LiveGraph.reload(filesOf:)` kept the old event list (the graph still got the new state). The task query still passed and the `history` compare failed. The mutation is reverted; LiveGraph.swift has no diff.
    - Choice: the card says "add a task". The test adds the task with `addTask` on the engine, so `history(filter: "^id")` must give the CREATED transaction of the engine and then the two UPDATED transactions of the other process (a title line and a move to `done`, each in its own transaction). The compare is exact and reads up to 10 changes, so an extra change also fails.
    - Stability: 20 repetitions of the new test passed (`--maximum-repetitions 20 --repeat-until fail`).
  timestamp: 2026-10-09T19:49:59.577583+00:00
- actor: claude-code
  id: 01m4h3e8j2q0h5pqck5adbzpcz
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/Observe/BoardWatcherTests.swift. `swift test`: 1098 tests in 80 suites passed, 0 failures; only the accepted SwiftPM "missing creator for mutated node" warning. New test: 20 of 20 repetitions passed.
    - next: /review
  timestamp: 2026-10-09T19:50:01.026840+00:00
depends_on:
- 01M4G9K73ZBYJ3Y9KSXYEW2ZEB
position_column: doing
position_ordinal: '80'
title: 'Test: history after a union merge that the watcher applies'
---
## What
plan.md §11 (live graph): "A `union` merge that adds lines to a task log updates the task and adds its events to `history`." No test checks `history` after a watcher apply. `Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift:324` checks only the change feed, and the merge tests check only replay.

- Add a test: open a `KanbanGraph`, add a task, then append lines from a different transaction to the task log file on disk (as a merge does). Wait for the watcher batch (use the batch observer hook of the test `init`). Then query `history(filter:"^<id>")` and the task.
- If the test fails, fix the code in `Sources/FoundationModelsKanban/Observe/LiveGraph.swift` or the history resolver.

## Acceptance Criteria
- [x] After the watcher applies the batch, the task has the new values, and `history` has the transaction of the appended lines.

## Tests
- [x] The test above in `Tests/FoundationModelsKanbanTests/Observe/BoardWatcherTests.swift` or `LiveGraphApplyTests.swift`.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.