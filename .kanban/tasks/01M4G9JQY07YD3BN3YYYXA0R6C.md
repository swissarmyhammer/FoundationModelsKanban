---
assignees:
- claude-code
position_column: todo
position_ordinal: 8c80
title: 'Tool arguments: empty operationName, mixed documents, and the description examples'
---
## What
Three small defects in the tool layer (plan.md §7.1).

1. `Sources/FoundationModelsKanban/Tool/KanbanArguments.swift:121-125`: an `operationName` of `""` goes to the engine, and GraphQLSwift gives `Unknown operation named ""`. Change an empty or whitespace-only `operationName` to `nil` (maximally forgiving input).
2. `Sources/FoundationModelsKanban/Tool/KanbanTool.swift:91-100`: with `operationName == nil`, a document that has a query and a subscription returns `SUBSCRIPTION_NOT_IN_TOOL`. Give that error only when the selected operation is a subscription. When no operation can be selected, give the normal "Must provide operation name" error.
3. `KanbanTool.swift:32-39`: the description has two examples (`exampleQuery`, `historyExample`). plan.md §7.1 and §12 item 10 say "one example query". Both examples are tested. Update plan.md §7.1 and §12 item 10 to say "tested examples" (keep the two).

## Acceptance Criteria
- [ ] `{"query":"{ board { name } }","operationName":""}` returns the board name.
- [ ] A document with a query and a subscription and no `operationName` gives the operation-name error, not `SUBSCRIPTION_NOT_IN_TOOL`.
- [ ] plan.md agrees with the description.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Tool/KanbanArgumentsTests.swift`: `""` and `"  "` decode to `nil`.
- [ ] `Tests/FoundationModelsKanbanTests/Tool/KanbanToolTests.swift`: the mixed-document case.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.