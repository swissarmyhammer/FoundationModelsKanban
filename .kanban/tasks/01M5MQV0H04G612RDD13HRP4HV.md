---
assignees:
- claude-code
position_column: todo
position_ordinal: '8680'
title: Add ifVersion to updateTask and refuse a stale write with STALE_WRITE
---
## What

KanbanViewKit edits the title and the description of a task in place (its plan §3.4). Two editors can edit the same task. The second write must not overwrite the first write with no warning.

- Add a `version` field to `Task` (and to the other node types if it is cheap). The version changes on each write of the node. Use a value that the event log already holds, for example the event id of the last event of the node. Do not add a stored counter.
- Add an optional `ifVersion` to the input of `updateTask`. When it is set and it is not the current version of the task, refuse the call with the new error code `STALE_WRITE`, and write nothing. The error gives the current version.
- With no `ifVersion`, the call works as today.
- `moveTask` takes no `ifVersion`: a move is never refused (KanbanViewKit D100).
- Add the code to `S/GraphQL/Errors.swift` and describe it in the schema description and the tool description.
- Record the decision in `divergence.md`.

## Acceptance criteria

- [ ] `Task.version` is in the schema, and it changes after each write of the task.
- [ ] `updateTask(input: {id, title, ifVersion: <current>})` writes.
- [ ] `updateTask(input: {id, title, ifVersion: <old>})` gives `STALE_WRITE` with the current version, and writes nothing (no event, no undo entry).
- [ ] With no `ifVersion`, the behavior does not change.

## Tests

- Unit tests in `T/` for each criterion.
- `swift test` passes with no new warnings. #kanbanviewkit