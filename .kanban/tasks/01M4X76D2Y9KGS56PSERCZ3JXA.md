---
assignees:
- claude-code
depends_on:
- 01M4X6X6PS5P524DW45RBSSWN2
- 01M4X764NWFQQH1Y10RFXKM3BC
position_column: todo
position_ordinal: 9f80
title: Keep the Rust behavior for addActor ensure, empty tag lists, and unknown before/after refs
---
## What
divergence.md Q16 with its third rule replaced by P1 (DECIDED), O1, O2, O3, and §11 "Q16". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Decided behavior (three rules):
1. `addActor(ensure: true)` updates the name, the color, and the `avatar` when they are different, and makes a deleted (tombstoned) actor live again. Now Swift writes nothing (S/GraphQL/ColumnActorMutations.swift:242-244) and returns a tombstoned actor as it is. The `avatar` field comes from the Q19 task.
2. `tagTask` and `untagTask` with an empty list write nothing and return the task. There is no error. (This is the current Swift behavior; keep it and keep its test.)
3. (P1, replaces the first Q16 rule) An unknown `before` or `after` ref on `moveTask` (a ref that names no task) puts the task at the end of the column. The response gets a warning in `extensions.warnings` that names the ref. Now Swift gives `NOT_FOUND`.

## Acceptance Criteria
- [ ] `addActor(input: {id: "a", name: "New"}, ensure: true)` on an existing actor `a` with a different name updates the name.
- [ ] The same for `color` and `avatar`.
- [ ] `addActor(ensure: true)` on a deleted actor makes it live again.
- [ ] `addActor(ensure: true)` with the same values writes no event.
- [ ] `tagTask(tags: [])` and `untagTask(tags: [])` write nothing and return the task.
- [ ] `moveTask(id: ..., before: "zzzzzzz")` puts the task at the end of the column and gives a warning that names `zzzzzzz`.

## Tests
- [ ] Tests for each part of rule 1 (name, color, avatar, undelete, no change).
- [ ] The existing empty-list test for rule 2.
- [ ] A test for rule 3 with `before` and with `after`.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.