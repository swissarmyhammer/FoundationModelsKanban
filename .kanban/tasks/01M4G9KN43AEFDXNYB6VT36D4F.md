---
assignees:
- claude-code
depends_on:
- 01M4G9K73ZBYJ3Y9KSXYEW2ZEB
position_column: todo
position_ordinal: '9280'
title: 'Test: history after a union merge that the watcher applies'
---
## What
plan.md §11 (live graph): "A `union` merge that adds lines to a task log updates the task and adds its events to `history`." No test checks `history` after a watcher apply. `Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift:324` checks only the change feed, and the merge tests check only replay.

- Add a test: open a `KanbanGraph`, add a task, then append lines from a different transaction to the task log file on disk (as a merge does). Wait for the watcher batch (use the batch observer hook of the test `init`). Then query `history(filter:"^<id>")` and the task.
- If the test fails, fix the code in `Sources/FoundationModelsKanban/Observe/LiveGraph.swift` or the history resolver.

## Acceptance Criteria
- [ ] After the watcher applies the batch, the task has the new values, and `history` has the transaction of the appended lines.

## Tests
- [ ] The test above in `Tests/FoundationModelsKanbanTests/Observe/BoardWatcherTests.swift` or `LiveGraphApplyTests.swift`.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.