---
assignees:
- claude-code
position_column: todo
position_ordinal: '8e80'
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
- [ ] `history` with no filter shows the delete of a task, but not later updates of the tombstone (for example a derived change).
- [ ] `history` with no filter shows the delete of a column and the delete of a tag.
- [ ] `history(filter:"#DELETED")` shows all updates of tombstones.
- [ ] `Subscription.changes` gives the same results as `history` for each case above.

## Tests
- [ ] Tests in `Tests/FoundationModelsKanbanTests/Observe/` (`ChangeFilterTests.swift` or the history tests) for each acceptance criterion.
- [ ] A subscription test that runs the same cases with `changes` and compares the result with `history`.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.