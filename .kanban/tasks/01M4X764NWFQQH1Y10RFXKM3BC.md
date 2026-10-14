---
assignees:
- claude-code
position_column: todo
position_ordinal: '9e80'
title: Add back avatar, model, summary counts, percent, and virtual tag color and description
---
## What
divergence.md Q19 (DECIDED: add all of them back; K2 not cut), G5, F12, and §11 "Q19". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Add back these fields from the Rust kanban:
- The actor `avatar` (a text field, for example a URL or an emoji). Read it on `Actor`, and set it on `addActor` and `updateActor`. Code: S/Model/ActorNode.swift and the actor mutations.
- The board `model` (a text field). Read it on `Board`, and set it on `initBoard`/`updateBoard` (`BoardInput`). Code: S/Model/BoardNode.swift and `BoardInput`.
- In the board summary: `totalActors`. For each column: `taskCount` and `readyCount`. Code: S/Derived/Summary.swift.
- In `Progress`: `percent` (0–100), next to `fraction`. Code: S/Derived/Progress.swift.
- A `color` and a `description` for each virtual tag. Code: S/Derived/VirtualTags.swift. Use the Rust colors where Rust has them: READY `0e8a16`, BLOCKED `e36209`. Choose colors for CONFLICT, DELETED, DONE, HIGH, MEDIUM, LOW. There is no BLOCKING (Q1 removes it). Write each description as one short sentence.
- Update S/GraphQL/Schema.swift for all these fields.

## Acceptance Criteria
- [ ] `addActor(input: {id: "x", avatar: "..."})` stores the avatar, and `Actor.avatar` reads it.
- [ ] `Board.model` can be set and read.
- [ ] `summary { totalActors }` and each column `taskCount`, `readyCount` give correct counts.
- [ ] `Progress.percent` equals `fraction * 100`.
- [ ] Each virtual tag has a `color` and a `description` in the schema.

## Tests
- [ ] A test for each new field.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.