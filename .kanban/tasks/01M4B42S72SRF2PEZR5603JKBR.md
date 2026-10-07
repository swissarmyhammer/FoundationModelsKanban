---
depends_on:
- 01M4B3YYXT069TKADQ93CBAA93
- 01M4B4AWDXHER3J8MZKEB7W39N
- 01M4B40PAP9R6NP87BZASW5155
position_column: todo
position_ordinal: a580
title: KanbanTool and forgiving KanbanArguments
---
## What
The `FoundationModels.Tool`. The basis is plan.md §7.1, §7.2, and §12 items 8 and 10.
- `Sources/FoundationModelsKanban/Tool/KanbanArguments.swift`: `query`, `variables: [String: Map]`, `variablesError`, `operationName`. A custom `init(_ content: GeneratedContent)`: an object converts directly; a string is parsed as JSON (remove a code fence and white space first); `null`, empty string, or no key = no variables; any other kind sets `variablesError` (no throw). `init` throws only when `query` is missing. JSON types are kept.
- `generationSchema`: `variables` is `DynamicGenerationSchema(name:anyOf:)` of a string schema (guide: "the variables as one JSON object in text") and an object schema with no properties, so the encoded JSON Schema has `anyOf` and no top-level `type`.
- `Tool/KanbanTool.swift`: `public struct KanbanTool: Tool`, `init(graph:)`, name `kanban`. It decodes the arguments and calls `execute`. `variablesError` gives `INVALID_VARIABLES` with the two correct forms. A `subscription` document gives `SUBSCRIPTION_NOT_IN_TOOL` and the message names `history(since:)`.
- A short tool description: purpose, the root fields, and one example query. The example is a test case.

## Acceptance Criteria
- [ ] `variables` as an object, a JSON string, JSON in a code fence, `null`, and no key give the same result; a non-object string gives `INVALID_VARIABLES`.
- [ ] The encoded `generationSchema` has `anyOf` and no `type` for `variables`.
- [ ] The example query of the description runs and returns data.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Tool/KanbanArgumentsTests.swift` and `KanbanToolTests.swift` (call the `Tool` with `GeneratedContent`; compare the JSON output).
- [ ] Run `swift test --filter KanbanArgumentsTests` and `--filter KanbanToolTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.