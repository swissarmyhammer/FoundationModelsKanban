---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gj2k7296a9qtqa45azbrd0
  text: |-
    Research:
    - `PublicSchema.respond` (GraphQL/Schema.swift) has three error paths with no code: (1) `errorResponse` for a parse error (the rewriter parse in `rewriting`, and the engine parse in `result(of:)`); (2) the validation errors that `graphql()` returns in `GraphQLResult.errors` (no path, no original error); (3) the ties of `RewriteWalk.canonicalName` (NameRewrite.swift), which `result(of:)` returns as they are. `codedError` only codes a `KanbanError`.
    - The engine (`locatedError`) wraps a resolver error that is not a GraphQLError with the path and `originalError`. So an `EventError` has a path and a non-Kanban original error.
    - Errors with no path and no original error come from the request phase: validation, variable coercion, operation choice. These get `GRAPHQL_VALIDATION_FAILED`.
    - The subscription path codes its errors through `codedCallerResult`, so the same rule covers it.
    - `KanbanError.code` is a computed property over the cases. The new codes become new cases: `graphQLParseFailed(detail:)`, `graphQLValidationFailed(detail:)`, `ambiguousName(name:matches:)`, `internalFailure(detail:)`. The message of the parse, validation and internal cases is the engine text as it is, so the "did you mean" text does not change.
  timestamp: 2026-10-09T14:46:32.930114+00:00
- actor: claude-code
  id: 01m4gjf5zr2yhk56rc8cnkv4yq
  text: |-
    Implementation landed (TDD: RED seen for the 3 execute tests and the INTERNAL unit test, then GREEN).
    - New file `GraphQL/CodedError.swift`: `GraphQLError.coded(as:)`, `codedAsParseFailure()`, `codedAsResultError()`. It replaces the private `codedError` in Schema.swift.
    - Rule chosen (closest to plan.md §4.4): a `KanbanError` keeps its code; an error with no path and no original error is a request error (validation, variable values, operation choice) and gets `GRAPHQL_VALIDATION_FAILED`; each other error gets `INTERNAL`. The parse, validation and internal errors keep the message of the engine, so the "did you mean" text does not change.
    - `errorResponse` (the parse path) codes its error as `GRAPHQL_PARSE_FAILED`. The rewrite ties are made coded as `AMBIGUOUS_NAME` in `RewriteWalk.canonicalName`; the tie message moved into `KanbanError.ambiguousName`.
    - Discovery: `PatchSchema().respond` shares this path, so the `GraphQLEngineTests` test for a patch with a bad node ref now expects `extensions.code == "INTERNAL"`. I changed that expected JSON.
    - plan.md §4.4 lists the four new codes.
  timestamp: 2026-10-09T14:53:25.368303+00:00
- actor: claude-code
  id: 01m4gjf818qmdfhj8h7kfw7jzk
  text: |-
    ### implement — changed
    - evidence: 8 files — Sources/FoundationModelsKanban/GraphQL/CodedError.swift (new), GraphQL/Errors.swift, GraphQL/Schema.swift, GraphQL/NameRewrite.swift, plan.md, Tests/.../GraphQL/ErrorCoverageTests.swift, Tests/.../GraphQL/KanbanErrorTests.swift, Tests/.../GraphQLEngineTests.swift. `swift test`: 1064 tests in 74 suites passed, 0 failures; only the accepted SwiftPM "missing creator" warning.
    - next: /review
  timestamp: 2026-10-09T14:53:27.464398+00:00
position_column: doing
position_ordinal: '80'
title: Each GraphQL error has extensions.code
---
## What
plan.md §4.4: "Each error has `message`, `path`, and `extensions.code`." Now `Sources/FoundationModelsKanban/GraphQL/Schema.swift:1244-1247` (`codedError`) adds a code only for a `KanbanError`. These errors have no code: parse errors, validation errors, the tie errors of the name rewrite (`GraphQL/NameRewrite.swift:516`), and `EventError`.

- Add codes to the §4.4 list in plan.md and to the `KanbanError` code enum: `GRAPHQL_PARSE_FAILED` (syntax error), `GRAPHQL_VALIDATION_FAILED` (unknown field, wrong argument type, and others), `AMBIGUOUS_NAME` (rewrite tie), and `INTERNAL` (an `EventError` or other error that is not a `KanbanError`).
- Set the code in `codedError` and in the parse, validation and rewrite error paths.

## Acceptance Criteria
- [x] A document with a syntax error gives one error with `extensions.code == "GRAPHQL_PARSE_FAILED"`.
- [x] A document with an unknown field gives `GRAPHQL_VALIDATION_FAILED`.
- [x] A name that ties in the rewrite gives `AMBIGUOUS_NAME`.
- [x] No response from the tool has an error with no `extensions.code`.

## Tests
- [x] Tests in `Tests/FoundationModelsKanbanTests/GraphQL/` (the error coverage tests) for each case.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.