---
assignees:
- claude-code
position_column: todo
position_ordinal: 8a80
title: Define and add the trigger of a column
---
## What

KanbanViewKit holds a `trigger` for each column and has the verb "set the trigger of a column" (its plan §3.2, §3.4). The kanban schema and the code have no column trigger. The meaning is not defined yet.

## First: get the definition

Before code, get the meaning from the user or the KanbanViewKit session, and record it in `divergence.md`. Questions:

- What is a trigger? For example: a prompt or a command that the host runs when a task comes into the column, or a column role (`todo`, `doing`, `review`, `done`).
- Its type: a string, an enum, or an object.
- Does the engine run it, or does it only store it for the host?

## Then

- Add `trigger` to `Column` and to the input of `addColumn` and `updateColumn`. Store it in the column node, so it is in the event log, the undo stack and the `changes` events.
- Add schema descriptions and update the tool description.

## Acceptance criteria

- [ ] `divergence.md` records the definition.
- [ ] `updateColumn(input: {id, trigger})` sets it, and `Column.trigger` reads it.
- [ ] A `changes` event gives the new value. One `undoChange` reverses it.

## Tests

- Unit tests in `T/` for each criterion.
- `swift test` passes with no new warnings. #kanbanviewkit