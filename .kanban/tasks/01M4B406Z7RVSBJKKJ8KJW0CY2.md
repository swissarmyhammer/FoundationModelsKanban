---
depends_on:
- 01M4B4002GZV6E43G5CQ74BJNZ
- 01M4B3W0VAAWGYQ8F9621807Z9
- 01M4B4AQ1Z7DFQ4NP52RYF7RN1
position_column: todo
position_ordinal: '9980'
title: 'Mutations: move, complete, assign, tag, delete tasks'
---
## What
The other task mutations. The basis is plan.md §4.2, §6 (moveTask, completeTask), and §6.1.
- `moveTask(id!, column!, ordinal, before, after)`: ordinal priority is an explicit `ordinal`, then `before`/`after` a neighbor, then append at the end. A missing column is created (name = slug in title case).
- `completeTask(id!)`: move to the terminal column, after the last ordinal there.
- `assignTask` / `unassignTask(id!, actor!)`: `add`/`remove` on `assignees`.
- `tagTask` / `untagTask(id!, tags!)`: `add`/`remove` on the tag edges; an unknown tag in `tagTask` writes a tag `set` patch; `untagTask` also removes a matching `#marker` from the body with an `edit` patch.
- `deleteTask` / `undeleteTask(id!)`: `delete: true`/`false`. An undelete of a live task writes nothing.

## Acceptance Criteria
- [ ] Each move rule puts the task at the expected position.
- [ ] `untagTask` on a marker tag removes the marker; a tag on an edge and in a marker stays until both are removed.
- [ ] `deleteTask` hides the task in lists, and `undeleteTask` brings it back.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Mutations/TaskOperationTests.swift`: port the Rust move, complete, assign, tag, and archive dispatch tests (archive mapped to delete).
- [ ] Run `swift test --filter TaskOperationTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.