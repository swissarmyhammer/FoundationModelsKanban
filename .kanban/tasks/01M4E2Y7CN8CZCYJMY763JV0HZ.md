---
assignees:
- claude-code
position_column: todo
position_ordinal: '8280'
title: 'moveTask: error when the input gives both before and after'
---
## What
A person said on 2026-10-08: "both before and after at the same time is nonsense". Today `moveTask` takes the first of `ordinal`, `before`, `after`, and ignores the others with no error (`Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift`, `MoveTaskInput` and `TaskPlacement.init(before:after:resolvingWith:)`).

- When a `moveTask` input gives more than one place field (`ordinal`, `before`, `after`), the mutation fails with an error. It writes nothing. The message names the fields that it got, and it tells the caller to give only one.
- Use an existing code of the error catalog (`Errors.swift`, plan.md §4.4) if one fits (for example the code for a bad input). If none fits, add one, and add it to plan.md §4.4.
- Apply the same rule to every other input that has place fields (for example `addTask`, if it takes `ordinal` together with another place field).
- Update plan.md §4.2 (`moveTask`) and the tool description if it shows `before`/`after`.

## Acceptance Criteria
- [ ] `moveTask` with `before` and `after` gives the error and writes no event; the same for `ordinal` with `before` or `after`.
- [ ] `moveTask` with one place field, or none, works as before.

## Tests
- [ ] Add tests in the `moveTask` test suite for each pair of place fields, and check that the log has no new line.
- [ ] Run the full `swift test`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.