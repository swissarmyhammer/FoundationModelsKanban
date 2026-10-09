---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4h1ahsrt28xjmrwx5t7q237
  text: |-
    Research:
    - ChangeFilter.test returns `{ _ in true }` with no filter. History (Undo/History.swift) and ChangeFeed.send both call ChangeFilter.applied, so one fix covers both. Change.updates with no filter returns nodeUpdates before ChangeFilter runs; this stays, because `history(filter:"#DELETED") { updates }` must keep the tombstone updates that the outer filter kept.
    - TaskFilter.matches(nodeAt:) hides a tombstoned task for each update, also the DELETED update. Thus the no-filter path through TaskFilter needs one exemption: with no filter, a DELETED update passes (the node was live before the update).
    - A filter that does not name #DELETED keeps the current rule (HistoryTests.historyTagFilterLeavesOutDeletedTask expects `#bug` to drop the delete of a bug task). This is the rule closest to plan.md §6.7 ("A tombstoned task matches only a filter that names #DELETED").
    - ChangeBuilder makes no derived update for a tombstone. A later update of a tombstone comes from a patch line on the tombstone (a different process). The tests write that line with GitGraphFixture.secondEngineIDs, so its txn sorts after the engine mutations, and wait for the watcher batch (BatchRecorder) before the next mutation.
    - history reads the graph now, so with no filter it also drops the earlier updates of a task that is a tombstone now.
  timestamp: 2026-10-09T19:13:02.264437+00:00
- actor: claude-code
  id: 01m4h1j8jc9gd9c52yyxvak0rr
  text: |-
    Implementation landed.
    - TDD: the new parameterized test ChangeFilterTests.changesEqualHistory failed first (with no filter, the second event was the TASK UPDATED of the tombstone, not the addColumn change). After the fix it passed.
    - Fix: ChangeFilter.test always makes a TaskFilter (also for no filter) and calls the new TaskFilter.matches(updateOfNodeAt:isDelete:). With no filter, a DELETED update passes. Each other update goes through matches(nodeAt:), so a tombstoned task is hidden unless the filter names #DELETED, ^id, or ~task.
    - Choice for the open behavior: a filter that does not name #DELETED (for example #bug) still drops the DELETED update of a tombstoned task. This keeps HistoryTests.historyTagFilterLeavesOutDeletedTask and the plan.md §6.7 sentence "A tombstoned task matches only a filter that names #DELETED". Change.updates with no filter still gives each update of its Change.
    - Discovery: an added column after the fixture column `todo` makes the fixture task open, so addColumn and deleteColumn on the fixture board also give BOARD UPDATED and TASK UPDATED.
    - plan.md §3.3 rule 3 and §6.7 (new bullet "Tombstones with no filter") are updated.

    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/Observe/ChangeFilter.swift, Sources/FoundationModelsKanban/Filter/TaskFilter.swift, Tests/FoundationModelsKanbanTests/Observe/ChangeFilterTests.swift (new), plan.md. `swift test --filter ChangeFilterTests`: 1 test, 3 cases, passed. `swift test`: 1094 tests in 80 suites passed; the only build warning is the accepted SwiftPM "missing creator for mutated node".
    - next: /review
  timestamp: 2026-10-09T19:17:14.956909+00:00
position_column: doing
position_ordinal: '80'
title: Change feed with no filter hides tombstones, the same as a task list
---
## What
`Sources/FoundationModelsKanban/Observe/ChangeFilter.swift:57-59`: with no filter, the code returns `{ _ in true }` before `TaskFilter` runs. Thus the "hidden unless named" rule (plan.md §3.3, §6.7) does not apply to `history` and `Subscription.changes`. A task list with no filter hides a tombstone, but the feed shows its updates.

Final rule:
- With no filter, `history` and `Subscription.changes` keep the update that deletes a node (the change from live to tombstone), for each node type (task, column, tag, actor, comment and the others).
- With no filter, `history` and `Subscription.changes` drop the later updates of a tombstone task (for example a derived change).
- A filter that names `#DELETED`, `^<id>`, or `~task` keeps all tombstone updates.
- `history` and `Subscription.changes` use the same rule and the same code path.

- Run the no-filter case through the same `TaskFilter` path.
- Update plan.md:
  - §3.3: write the "hidden unless named" rule as one rule for task lists, `history`, and `Subscription.changes`.
  - §6.7: write the exact rule for the delete update and for the later updates of a tombstone.

## Acceptance Criteria
- [x] `history` with no filter shows the delete of a task, but not later updates of the tombstone (for example a derived change).
- [x] `history` with no filter shows the delete of a column and the delete of a tag.
- [x] `history(filter:"#DELETED")` shows all updates of tombstones.
- [x] `Subscription.changes` gives the same results as `history` for each case above.

## Tests
- [x] Tests in `Tests/FoundationModelsKanbanTests/Observe/` (`ChangeFilterTests.swift` or the history tests) for each acceptance criterion.
- [x] A subscription test that runs the same cases with `changes` and compares the result with `history`.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.