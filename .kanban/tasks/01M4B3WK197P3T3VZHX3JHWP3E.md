---
comments:
- actor: wballard
  id: 01m4bbhx3phpdpa0f3c0cm5295
  text: |-
    Research done.
    - `PatchInput` (GraphQL/PatchSchema.swift) is the Graphiti input of the internal `patch` mutation. It holds `node: String` and `Map` parts. Graphiti `InputField(_:at:)` ignores the key path at run time; it uses only the field type for the SDL. The argument decode uses the `Decodable` conformance (MapDecoder). Thus `PatchInput` can hold typed refs (`LocalRef`, `StoredRef`) with a custom `Codable`, and the schema can name wire-typed computed properties for the SDL.
    - `Map` encodes `.number` as `Double` and `.dictionary` as a keyed container, so `JSONEncoder` with `.sortedKeys` gives sorted keys. `.undefined` cannot encode.
    - `ULID` and `DateTime` are `Codable` as text. `LocalRef` and `StoredRef` are not `Codable` yet.
    - Stored ref edges (plan.md §3.1): single `column`, `task`, `author`, tag `renamedTo`; set-valued `assignees`, `tags`, `dependsOn` (all refs).
    - The plan.md §5.1 example has elided ULIDs (`01K6Z4...`). The test fills in full ULIDs.
    - The existing GraphQLEngineTests patch tests use `task/01K6Z3`, which is not a valid ULID. With a typed `node`, these tests need a full ULID.
  timestamp: 2026-10-07T14:16:22.390272+00:00
- actor: wballard
  id: 01m4bbz73yj4hxh60gb8byz2ty
  text: |-
    Implementation done (TDD: EventTests failed to compile first, then passed).
    - `PatchInput` moved from GraphQL/PatchSchema.swift to Events/PatchInput.swift and is now typed: `node: LocalRef`, `type` derived from the node, `set: [String: PatchValue]` (`.ref(StoredRef)` or `.json(Map)`), `add`/`remove: [String: [StoredRef]]`, `edit: PatchEdit?`. The name of a property decides the kind of value: `PatchInput.refProperties` = column, task, author, renamedTo. `set` refuses the five time names (`EventError.timeProperty`) and a value of the wrong kind (`EventError.refMismatch`).
    - The `Encodable` form of `PatchInput` is its `map`, so the line and the resolver output have one shape. The internal `patch` schema keeps its SDL: the Graphiti `InputField` key paths point at the wire-typed parts (`nodeText`, `setMap`, `unsetList`, `addMap`, `removeMap`, `editMap`).
    - Behavior change: the `patch` mutation now refuses a node or a ref that does not parse. The two old GraphQLEngineTests used `task/01K6Z3` (not a ULID); they now use a full ULID, and a new test asserts the error for the short id.
    - `LocalRef` and `StoredRef` are `Codable` as their text through the new `TextCodable` protocol (Identity/LocalRef.swift).
    - `Event` (Events/Event.swift): synthesized `Codable`, `variables` = `{"p": PatchInput}`, `init(parsing:) throws(EventError)` and `encodedLine() throws(EventError)` with `.sortedKeys` and `.withoutEscapingSlashes`. JSONEncoder writes a whole `Double` as `3`, so number values round-trip.
    - `KanbanError` is not used: a bad line is skipped by the loader, and the catalog has no code for it. `EventError` is the typed error.
  timestamp: 2026-10-07T14:23:38.622680+00:00
- actor: wballard
  id: 01m4bbza5tr6y82fx2zmfdfqnf
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsKanban/Events/Event.swift (new), Sources/FoundationModelsKanban/Events/PatchInput.swift (new), Sources/FoundationModelsKanban/GraphQL/PatchSchema.swift, Sources/FoundationModelsKanban/Identity/LocalRef.swift, Tests/FoundationModelsKanbanTests/Events/EventTests.swift (new), Tests/FoundationModelsKanbanTests/GraphQLEngineTests.swift. `swift test`: 238 tests in 14 suites passed, 0 failures, 0 warnings. `swift test --filter EventTests`: 21 tests (29 cases) pass.
    - next: /review
  timestamp: 2026-10-07T14:23:41.754583+00:00
- actor: wballard
  id: 01m4bbzeg2qk5rvcfqgsrwk578
  text: 'Correction to the step record: the EventTests suite has 19 tests (27 cases with the two 5-argument tests), not 21 (29). All pass.'
  timestamp: 2026-10-07T14:23:46.178166+00:00
depends_on:
- 01M4B3VF41P7FCKEC4MFT9GWA0
- 01M4B3VR0CTZWWGMDJBT7YF4W0
position_column: doing
position_ordinal: '80'
title: 'Event model: envelope and PatchInput lines'
---
## What
The format of one log line. The basis is plan.md §5.1 and §12 item 28.
- `Sources/FoundationModelsKanban/Events/Event.swift`: `Event` with envelope fields `id`, `txn`, `ops`, `at`, `actor` (a local ref), `boards` (optional; the keys of the other boards only), `undoes` (optional), and `query` + `variables` (the full GraphQL request to the internal `patch` mutation).
- `PatchInput`: `node` (local ref), `type`, `set`, `unset`, `add`, `remove`, `delete`, `edit` (`{"body": "<unified diff>"}`). All refs in the stored form (`StoredRef`).
- Encode one event as one JSON line with sorted keys. Decode a line. A line that does not decode gives a typed error (the loader skips it later).
- No time value in a patch: `set` refuses the names `created`, `updated`, `deleted`, `started`, `completed`.

## Acceptance Criteria
- [x] An event round-trips line → `Event` → line with the same bytes.
- [x] The example line of plan.md §5.1 decodes.
- [x] A line never holds the key of its own board (the encoder works only with `StoredRef`).

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Events/EventTests.swift`: round trip, the plan example, bad lines, the refused `set` names.
- [x] Run `swift test --filter EventTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.