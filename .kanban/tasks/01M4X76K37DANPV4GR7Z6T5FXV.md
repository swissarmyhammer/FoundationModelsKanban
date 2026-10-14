---
assignees:
- claude-code
position_column: todo
position_ordinal: a080
title: Ignore null on a required text field in update mutations
---
## What
divergence.md Q17 (DECIDED: ignore it, as Rust does), O4, and §11 "Q17". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem (O4): `null` clears `title` and the column `name`, and they then read as `""`. The same path also clears the actor `name` (S/GraphQL/ColumnActorMutations.swift:114) and the tag `name` (S/GraphQL/TagMutations.swift:53,130-132).

Decided behavior: `null` on a required text field means "no change". The call works, and the field keeps its value. The required text fields are: task `title`, column `name`, actor `name`, tag `name`. Other optional fields keep the rule "`null` clears the field".

Change the update mutations in S/GraphQL/TaskMutations.swift, S/GraphQL/ColumnActorMutations.swift (column and actor `name`), and S/GraphQL/TagMutations.swift (tag `name`).

## Acceptance Criteria
- [ ] `updateTask(input: {id: ..., title: null})` works and the title does not change.
- [ ] The same for column `name`, actor `name`, and tag `name`.
- [ ] `null` on an optional field (for example `body`) still clears it.

## Tests
- [ ] Change the tests T/Mutations/AddUpdateTaskTests.swift:651-660 and T/Mutations/ColumnActorTests.swift:382-390 to the new rule.
- [ ] Add tests for actor `name` and tag `name`.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.