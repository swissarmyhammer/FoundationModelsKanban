---
assignees:
- claude-code
position_column: todo
position_ordinal: 8b80
title: 'Add Task.timeline: the history of one task with no full replay (KANBAN-13)'
---
## What

The full card of KanbanViewKit and the Task inspector of Testudo show the history of a task. The definition is KANBAN-13 in `../TestudoApp/features/packages/foundationmodels-kanban.md` (D45, D56).

Today `Board.history(filter:)` gives the changes of the board, and the filter tests each node update. There is no field on the task, and the call reads the history of the whole board.

## Work

- Add `Task.timeline(first:, after:)`: the entries of the history of the task, newest first, with paging.
- Each entry gives: the time, the actor, the `txn`, and the kind: a column move (from, to), a field change (name, before, after), or a comment (added, changed, removed, with the comment).
- Read only the log of the task and the logs of its comments. Do not replay the full event log of the board for each call.
- An undone transaction shows as undone, in the same way as `Change.undone`.
- Use the existing types of `S/Observe/Change.swift` (`FieldChange`, the actor resolve) where they fit. Do not make a second set of change types.
- Add schema descriptions, update the tool description, and record the shape in `divergence.md`.

## Acceptance criteria

- [ ] `Task.timeline` gives the moves, the field changes and the comments of the task, with the actor of each.
- [ ] Paging works with `first` and `after`.
- [ ] The call reads only the logs of the task and of its comments (a test with a board of many tasks checks it, for example with a counting log reader).
- [ ] An undone change shows as undone.

## Tests

- Unit tests in `T/` for each criterion.
- `swift test` passes with no new warnings. #kanbanviewkit