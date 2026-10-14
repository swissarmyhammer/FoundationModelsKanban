---
assignees:
- claude-code
position_column: todo
position_ordinal: ac80
title: Send unresolvedDependsOn changes in the change feed
---
## What
Task ^d8r4c92 added the public field `Task.unresolvedDependsOn: [ID!]!` (divergence.md Q2). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

`TaskObject.trackedFields` in S/Observe/ChangeBuilder.swift lists the public Task fields that the change feed and `Board.history` compare. The list does not have `unresolvedDependsOn`. Thus no `FieldChange` shows when the list of unresolved targets of a task changes, for example when a related board becomes readable again, or when a URI with a typo is corrected.

## Acceptance Criteria
- [ ] `trackedFields` has `unresolvedDependsOn` as a list field, with `added` and `removed`.
- [ ] A change that adds a dependency on a missing task gives a `FieldChange` for `unresolvedDependsOn`.
- [ ] A change that removes that dependency gives a `FieldChange` for `unresolvedDependsOn` with `removed`.

## Tests
- [ ] Add `unresolvedDependsOn` to `ChangeBuilderTests.listFields` and the selection table, and add the cases above.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.