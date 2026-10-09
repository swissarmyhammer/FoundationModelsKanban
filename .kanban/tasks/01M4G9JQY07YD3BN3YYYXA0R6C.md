---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4h0p8yzzg39x1ba3fdxg1y4
  text: |-
    Research done.
    - KanbanArguments.init reads operationName as is; "" goes to GraphQLSwift, which gives `Unknown operation named ""`.
    - KanbanTool.selectsSubscription with a nil name returns true when any operation of the document is a subscription.
    - The GraphQLSwift message for a document with more than one operation and no name is "Must provide operation name if query contains multiple operations." (Execute.swift). CodedError.codedAsResultError gives this error GRAPHQL_VALIDATION_FAILED (no path, no original error). Thus the tool must only let the document go to the engine; the code comes from the engine.
    - Test helpers to reuse: KanbanArgumentsTests.argumentsJSON, KanbanToolTests.call and onlyError, KanbanGraphTests.nameQuery and nameResponse.
    - Plan: add an optional operationName parameter to the two helpers; make the operation-name test of KanbanArgumentsTests a case table; add tool tests for the blank name and for the mixed document.
  timestamp: 2026-10-09T19:01:57.855790+00:00
- actor: claude-code
  id: 01m4h0we8rzb8rpe1mqraf6k06
  text: |-
    Implementation done (TDD: the new tests failed first for the expected reasons, then passed).
    - KanbanArguments: new private `operationName(from:)`. A string that is empty or holds only white space gives nil. A name that is not blank stays as the call sent it (no trim); GraphQL names cannot hold white space, so a trim gives no new behavior.
    - KanbanTool.selectsSubscription now selects the operation the same way as the engine: the operation with the name, or the one operation of the document when the name is nil. Only a selected subscription gives SUBSCRIPTION_NOT_IN_TOOL. When no operation can be selected, the document goes to the engine, which gives "Must provide operation name if query contains multiple operations." with GRAPHQL_VALIDATION_FAILED (CodedError gives the code; no new code was necessary).
    - Tests: argumentsJSON and KanbanToolTests.call take an optional operationName (default nil). The operation-name test of KanbanArgumentsTests is now a case table (name, no key, "", "  ", "\n\t"). The SUBSCRIPTION_NOT_IN_TOOL test is a case table (no name, blank names, mixed document by name) and compares the full message. New tests: blank names and the mixed-document query by name return KanbanGraphTests.nameResponse exactly; the mixed document with no name gives GRAPHQL_VALIDATION_FAILED and the full engine message.
    - Note: the mixed document must name both operations. An anonymous operation beside another operation fails validation (LoneAnonymousOperation) with a different message.
    - plan.md: §7.1 has two new bullets (forgiving operationName, the subscription rule) and "tested examples"; §12 item 10 says "tested examples"; §6 "In the tool" says "selected operation".
  timestamp: 2026-10-09T19:05:19.896587+00:00
- actor: claude-code
  id: 01m4h0wgyf7f4007s89mpha1gj
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/Tool/KanbanArguments.swift, Sources/FoundationModelsKanban/Tool/KanbanTool.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanArgumentsTests.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanToolTests.swift, plan.md. `swift test`: 1093 tests in 79 suites passed; the only build warning is the accepted SwiftPM "missing creator for mutated node".
    - next: /review
  timestamp: 2026-10-09T19:05:22.639779+00:00
position_column: doing
position_ordinal: '80'
title: 'Tool arguments: empty operationName, mixed documents, and the description examples'
---
## What
Three small defects in the tool layer (plan.md §7.1).

1. `Sources/FoundationModelsKanban/Tool/KanbanArguments.swift:121-125`: an `operationName` of `""` goes to the engine, and GraphQLSwift gives `Unknown operation named ""`. Change an empty or whitespace-only `operationName` to `nil` (maximally forgiving input).
2. `Sources/FoundationModelsKanban/Tool/KanbanTool.swift:91-100`: with `operationName == nil`, a document that has a query and a subscription returns `SUBSCRIPTION_NOT_IN_TOOL`. Give that error only when the selected operation is a subscription. When no operation can be selected, give the normal "Must provide operation name" error.
3. `KanbanTool.swift:32-39`: the description has two examples (`exampleQuery`, `historyExample`). plan.md §7.1 and §12 item 10 say "one example query". Both examples are tested. Update plan.md §7.1 and §12 item 10 to say "tested examples" (keep the two).

## Acceptance Criteria
- [x] `{"query":"{ board { name } }","operationName":""}` returns the board name.
- [x] A document with a query and a subscription and no `operationName` gives the operation-name error, not `SUBSCRIPTION_NOT_IN_TOOL`.
- [x] plan.md agrees with the description.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Tool/KanbanArgumentsTests.swift`: `""` and `"  "` decode to `nil`.
- [x] `Tests/FoundationModelsKanbanTests/Tool/KanbanToolTests.swift`: the mixed-document case.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.