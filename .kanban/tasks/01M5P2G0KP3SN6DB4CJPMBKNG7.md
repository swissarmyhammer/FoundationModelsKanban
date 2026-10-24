---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5pk0ykxt2y4ra9vt1v9178h
  text: |-
    ### decision (user, 2026-10-24)
    Option 2: the name check accepts the slug of the caller actor, also when the caller is not yet an actor of the board. Then "my tasks" is a valid filter that selects no task. Record this in divergence.md §17.
  timestamp: 2026-10-24T09:14:16.061319+00:00
depends_on:
- 01M5MQTKNM12VRRJW516RXDA32
position_column: todo
position_ordinal: 8d80
title: 'Filter agent: decide "me" when the caller actor is not an actor of the board'
---
## What

The vocabulary (card ^j48gsq3, `FilterVocabulary.text(of:for:)`) tells the model to write `@<slug>` of the session actor for "me". The session actor becomes a node of the board only on its first write (plan §6). Thus a caller that did not write to the board yet gets `@<slug>`, and the name check (`FilterNameCheck`) gives `INVALID_FILTER` for it: "no actor named ...", with the nearest actor as the example. The loop (card ^6rxda32) then sends that message back, and the model can change "me" to a different actor.

A person must decide the behavior. Options:

1. Keep it. "My tasks" of a caller with no tasks fails after 3 attempts with `filter: null`.
2. The name check accepts the slug of the session actor, so `@<caller>` passes and selects no task.
3. The vocabulary tells that the caller actor is not an actor of the board, and that "me" selects no task.

Record the decision in divergence.md §17.

## Acceptance criteria

- [ ] divergence.md §17 records the decision.
- [ ] A unit test covers "my tasks" for a caller that is not an actor of the board.

## Tests

- `swift test` passes with no new warnings. #kanbanviewkit #filter-agent