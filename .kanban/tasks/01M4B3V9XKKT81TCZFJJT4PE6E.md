---
depends_on:
- 01M4B3V22A3PCQRESESTYBQ2FH
position_column: todo
position_ordinal: '8180'
title: 'GraphQL engine: Graphiti schema end to end'
---
## What
Prove the GraphQL engine works under Swift 6 strict concurrency. The basis is plan.md §10 step 2 and §12 item 9.
- Add `GraphQLSwift/GraphQL` and `GraphQLSwift/Graphiti` to `Package.swift`.
- `Sources/FoundationModelsKanban/GraphQL/Schema.swift`: a small public Graphiti schema built from Swift types (one query field, one mutation field) with async resolvers.
- `Sources/FoundationModelsKanban/GraphQL/PatchSchema.swift`: a separate internal schema with one `patch(input: PatchInput!)` mutation stub. The public schema must not contain `patch`.
- `Sources/FoundationModelsKanban/GraphQL/Scalars.swift`: the `DateTime` and `JSON` scalars.
- If the library has a Swift 6 concurrency problem, correct it in our wrapper code. Do not change the engine.

## Acceptance Criteria
- [ ] One query and one mutation run end to end and return the expected JSON.
- [ ] The public SDL has no `patch` field; the internal schema has it.
- [ ] `swift build` has zero warnings in strict concurrency mode.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/GraphQLEngineTests.swift`: query, mutation, `DateTime` and `JSON` round trip, SDL check.
- [ ] Run `swift test --filter GraphQLEngineTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.