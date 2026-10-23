---
assignees:
- claude-code
position_column: todo
position_ordinal: 8c80
title: Add the live state of an actor for sessions (KANBAN-15, Step 3)
---
## What

KanbanViewKit shows the live state of each actor on its cards (its plan §3.2, §3.5). The definition is KANBAN-15 in `../TestudoApp/features/packages/foundationmodels-kanban.md` (D50, D57). It is in Step 3 of TestudoApp, because it needs agents.

- Each session that works on a board is an `Actor` of the board. The task of a subagent is assigned to the actor of its session.
- The actor has a live `state` field: `working`, `needsInput`, `done`, `error` (or null when there is no live session).
- The server host sets the state. It is live state, not board content: decide whether it goes into the event log or stays in memory, and record the decision in `divergence.md`. (Live state in a git log can give many merge lines.)
- The state goes to clients in the same `changes` stream as the other board changes, as a node update of the actor.

## Work

- Add `Actor.state` and the enum to the schema.
- Add a host API to set the state of an actor (for example `KanbanGraph.setActorState(_:for:)`), for the server host only. A client mutation through the tunnel does not set it.
- Each set gives one `changes` event with the actor node.
- Add schema descriptions and record the decision in `divergence.md`.

## Acceptance criteria

- [ ] `Actor.state` reads the last state that the host set.
- [ ] A set gives one `changes` event that holds the actor node with the new state.
- [ ] A client through the tunnel cannot set the state.
- [ ] `divergence.md` records where the state is stored.

## Tests

- Unit tests in `T/` for each criterion.
- `swift test` passes with no new warnings. #kanbanviewkit