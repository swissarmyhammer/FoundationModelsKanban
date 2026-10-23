---
assignees:
- claude-code
position_column: todo
position_ordinal: '8880'
title: Accept a list of task ids in moveTask, deleteTask and undeleteTask
---
## What

In KanbanViewKit, a drag of many selected cards is one call, and the user can delete or archive many selected tasks (its plan §3.4). Today `moveTask`, `deleteTask` and `undeleteTask` take one task id. (`archive` is an alias of `deleteTask`, `unarchive` of `undeleteTask`.)

- Let `id` in the input of these mutations take one id or a list of ids, in the forgiving style of the other list inputs (very forgiving tool inputs).
- `moveTask` with a list puts the tasks at the placement in the order of the list, as one block (for example, all before the `before` task).
- The call is one transaction: one `undoChange` reverses all of it.
- When one id names nothing, refuse the whole call and write nothing. The error names each bad id.
- The result gives each changed task.
- A move is never refused for a version conflict (KanbanViewKit D100).
- Record the decision in `divergence.md`, and update the tool description.

## Acceptance criteria

- [ ] `moveTask(input: {id: [a, b, c], column: "doing", before: x})` puts a, b, c before x in that order, in one transaction.
- [ ] `deleteTask` and `undeleteTask` with a list work in one transaction.
- [ ] One `undoChange` reverses each of these calls.
- [ ] A list with an unknown id writes nothing and names the id.
- [ ] One id (not a list) works as today.

## Tests

- Unit tests in `T/` for each criterion.
- `swift test` passes with no new warnings. #kanbanviewkit