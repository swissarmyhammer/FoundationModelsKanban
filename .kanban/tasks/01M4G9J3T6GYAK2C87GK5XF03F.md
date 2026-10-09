---
assignees:
- claude-code
position_column: todo
position_ordinal: '8880'
title: Each GraphQL error has extensions.code
---
## What
plan.md §4.4: "Each error has `message`, `path`, and `extensions.code`." Now `Sources/FoundationModelsKanban/GraphQL/Schema.swift:1244-1247` (`codedError`) adds a code only for a `KanbanError`. These errors have no code: parse errors, validation errors, the tie errors of the name rewrite (`GraphQL/NameRewrite.swift:516`), and `EventError`.

- Add codes to the §4.4 list in plan.md and to the `KanbanError` code enum: `GRAPHQL_PARSE_FAILED` (syntax error), `GRAPHQL_VALIDATION_FAILED` (unknown field, wrong argument type, and others), `AMBIGUOUS_NAME` (rewrite tie), and `INTERNAL` (an `EventError` or other error that is not a `KanbanError`).
- Set the code in `codedError` and in the parse, validation and rewrite error paths.

## Acceptance Criteria
- [ ] A document with a syntax error gives one error with `extensions.code == "GRAPHQL_PARSE_FAILED"`.
- [ ] A document with an unknown field gives `GRAPHQL_VALIDATION_FAILED`.
- [ ] A name that ties in the rewrite gives `AMBIGUOUS_NAME`.
- [ ] No response from the tool has an error with no `extensions.code`.

## Tests
- [ ] Tests in `Tests/FoundationModelsKanbanTests/GraphQL/` (the error coverage tests) for each case.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.