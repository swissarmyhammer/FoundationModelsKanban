---
assignees:
- claude-code
position_column: todo
position_ordinal: b380
title: Remove the typed throws that the filter evaluator chain can no longer give
---
## What
After ^n9wjgty (divergence.md Q20), `FilterEvaluator.init(evaluating:over:inBoard:)` gives no error: a `^id` value of a shared short id matches each task with it. The init keeps `throws(KanbanError)` only for its callers.

Make the chain honest:
- Sources/FoundationModelsKanban/Filter/FilterEvaluator.swift: remove `throws(KanbanError)` from `init(evaluating:over:inBoard:)`.
- Sources/FoundationModelsKanban/Filter/TaskFilter.swift: `init(filtering:over:inBoard:)` then has no error.
- Sources/FoundationModelsKanban/Observe/ChangeFilter.swift: `applied`, `updates(of:)`, `check(against:)`, `test(over:)` then have no error; remove `check(against:)` if it has no use.
- Sources/FoundationModelsKanban/Observe/ChangeFeed.swift `send(...)`: remove the `do`/`catch` that ends the stream when the filter fails.
- Sources/FoundationModelsKanban/Observe/ChangeSubscription.swift, Observe/Change.swift, GraphQL/TaskSelection.swift, GraphQL/QueryResolvers.swift: remove each `try` that then has no throwing call, and fix the doc comments.
- Tests/FoundationModelsKanbanTests/Filter/FilterEvaluatorTests.swift: remove the `try` before `FilterEvaluator(...)`.

## Acceptance Criteria
- [ ] No function of the filter chain declares a typed `throws` that it cannot give.
- [ ] `swift test` passes with no new warning.

## Tests
- [ ] The existing filter, change feed, and subscription tests pass.