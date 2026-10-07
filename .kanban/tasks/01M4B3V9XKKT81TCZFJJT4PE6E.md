---
comments:
- actor: wballard
  id: 01m4b5419z8g7abnzwed4y9gh2
  text: |-
    Research:
    - Latest tags: GraphQLSwift/GraphQL 4.3.0, Graphiti 3.1.0 (Graphiti 3.x needs GraphQL >= 4.0.0). Both declare Swift 6 language mode and `Sendable` on Schema, Coders, Field resolvers (`AsyncResolve` is `@Sendable`). With the two packages added, `swift build` completes with no warning before any wrapper code.
    - Graphiti adds `extension KeyPath: @retroactive @unchecked Sendable {}` in its own module (Field.swift). It is in the engine; we do not change it.
    - Graphiti needs a `Query` in every schema (it throws "Schema must contain at least 1 query"). Thus the internal patch schema shares the public types and the `board` query, and adds only the `patch` mutation. `SchemaBuilder` lets the two schemas share one set of components.
    - A Graphiti `Scalar<..., T: Codable>` encodes and decodes through `Coders` (MapEncoder/MapDecoder, default date strategy `deferredToDate`). Thus `DateTime` is our own Codable type that encodes as an RFC 3339 string, so the default scalar closures work with no custom date strategy. `JSON` maps to the GraphQL `Map` type.
    - `printSchema(schema:)` in GraphQL gives the SDL. `GraphQLJSONEncoder` keeps the selection order of the response keys.
    - Task p8qcsf3 later replaces the small `Board` type of this step in Schema.swift, and task 3jhwp3e defines the full `PatchInput` in Events/Event.swift.
  timestamp: 2026-10-07T12:23:56.479005+00:00
- actor: wballard
  id: 01m4b59s1g3pyck5rpxqase11m
  text: |-
    Discovery (engine defects, corrected in our wrapper; the engine is not changed):
    - GraphQL 4.3.0 `MapEncoder` changes each `Bool` to a number: `box(Bool)` makes `NSNumber(value:)`, and `MapSerialization.map(with:)` maps each `NSNumber` to `.number`. A `true` in a JSON value came back as `1`. Graphiti's default `Scalar` serialize goes through `MapEncoder`, so a `JSON` scalar with the default closures loses booleans. Correction: the `JSON` scalar has its own serialize/parseValue/parseLiteral closures (no MapEncoder), and the patch stub builds its result `Map` directly.
    - `MapDecoder` goes through `NSDictionary`, so the key order of a JSON object in the arguments is lost. Correction: the `JSON` scalar writes objects in a canonical form with sorted keys, so the output is deterministic.
    - `GraphQLJSONEncoder` escapes `/` as `\/` by default. The response encoder sets `.withoutEscapingSlashes`.
    - `Date.ISO8601FormatStyle` formats a `Date` made from whole milliseconds with float error: `.001` came out as `.000`. Correction: `DateTime` keeps integer milliseconds and writes the millisecond part with integer math.
  timestamp: 2026-10-07T12:27:04.624740+00:00
- actor: wballard
  id: 01m4b5dbazc84ys3t3xzbdcgax
  text: |-
    ### implement — changed
    - evidence: Package.swift (GraphQL 4.3.0, Graphiti 3.1.0, and an explicit swift-collections `OrderedCollections` product; the test target links GraphQL), Package.resolved, Sources/FoundationModelsKanban/GraphQL/Schema.swift, Sources/FoundationModelsKanban/GraphQL/PatchSchema.swift, Sources/FoundationModelsKanban/GraphQL/Scalars.swift, Tests/FoundationModelsKanbanTests/GraphQLEngineTests.swift. `swift package clean && swift build --build-tests`: 0 warnings, 0 errors. `swift test`: 13 tests in 2 suites pass (12 in GraphQLEngineTests).
    - design: the two schemas share one `SchemaBuilder` (scalars, `Board`, `Query.board`), because Graphiti needs a Query in each schema. `PublicSchema` adds `updateBoard`; `PatchSchema` adds `PatchNodeType`, `PatchInput`, and `patch(input: PatchInput!): JSON!`. The stub returns the decoded patch as canonical JSON (sorted keys). `API.respond(to:variables:context:)` returns the response JSON text with no `\/` escape.
    - no Swift 6 concurrency error came from the engine. The wrapper corrects the data defects in the earlier comment (Bool to number in MapEncoder, lost key order in MapDecoder, a lost millisecond in the Date formatter).
    - plan.md §8 does not list swift-collections. It was already a transitive dependency of GraphQL; it is now explicit, because Scalars.swift sorts an `OrderedDictionary`.
    - next: /review
  timestamp: 2026-10-07T12:29:01.663732+00:00
depends_on:
- 01M4B3V22A3PCQRESESTYBQ2FH
position_column: doing
position_ordinal: '80'
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
- [x] One query and one mutation run end to end and return the expected JSON.
- [x] The public SDL has no `patch` field; the internal schema has it.
- [x] `swift build` has zero warnings in strict concurrency mode.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/GraphQLEngineTests.swift`: query, mutation, `DateTime` and `JSON` round trip, SDL check.
- [x] Run `swift test --filter GraphQLEngineTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.