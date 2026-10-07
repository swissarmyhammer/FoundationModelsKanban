---
comments:
- actor: wballard
  id: 01m4b847vwq34sfa1a58j737v0
  text: |-
    Research done.
    - No ARCHITECTURE.md. Identity code is in Sources/FoundationModelsKanban/Identity (ShortID, ULIDSource). The node type enum `PatchNodeType` (GraphQL/PatchSchema.swift) has the six types with raw values `Board`, `Task`, and so on. The URI segment is the raw value in lowercase, so the new code uses `PatchNodeType` and does not add a second type enum.
    - `KanbanError` has a fixed code list (plan.md §4.4). No code fits a malformed URI or local ref, and the plan does not add one. Thus the parse errors are a separate typed enum `NodeRefError`. The RefResolver task (^cd36vb0) changes a parse failure to `NOT_FOUND`.
    - No `BoardKey` type exists yet. Task ^h6wn5vq owns Identity/BoardKey.swift. This task uses `String` for the board key, and does not make that file.
    - The ULID package (`ULID(ulidString:)`) accepts lowercase and the Crockford aliases, and `ulidString` gives uppercase. A task or comment local ref holds a `ULID` value, so a ref that is not a ULID is a typed error.
    - Parse rule for a URI: the scheme compare ignores case (RFC 3986). The parser looks at the end of the path. When the second-to-last segment is a node type other than `board`, the last two segments are the local ref. Else, when the last segment is `board`, it is the board ref. The rest is the board key, which must not be empty or have an empty segment. Thus a column with the slug `board` parses as a column.
  timestamp: 2026-10-07T13:16:28.924371+00:00
- actor: wballard
  id: 01m4b88wdwd87t672w1sz73wea
  text: |-
    Implementation landed (TDD).
    - RED: the two new test files did not compile, because `NodeURI`, `LocalRef`, `StoredRef`, and `NodeRefError` did not exist.
    - GREEN: `swift test --filter "NodeURITests|LocalRefTests"` gives 29 tests in 2 suites passed, with no warning.
    - API: `LocalRef(parsing:)`, `.description`, `.nodeType`, `.localID`. `NodeURI(boardKey:ref:)` (memberwise), `NodeURI(parsing:)`, `NodeURI.hasScheme(_:)`, `uri.localRef(inBoard:)` (nil for a different key). `StoredRef(parsing:)`, `StoredRef(_:inBoard:)`, `stored.uri(inBoard:)`. Errors: `NodeRefError.missingScheme`, `.invalidBoardKey`, `.invalidLocalRef`, `.invalidULID`.
    - A file outside Identity changed: `PatchNodeType` (GraphQL/PatchSchema.swift) now conforms to `CaseIterable`. The new `PatchNodeType.init?(pathSegment:)` and `pathSegment` need it. Swift synthesizes `CaseIterable` only on the declaration, so an extension in LocalRef.swift cannot add it.
    - Board keys compare exactly. Key normalization (lowercase host) belongs to ^h6wn5vq.
    - `KanbanError.noun(for:)` also uses `rawValue.lowercased()`. It can use the new `pathSegment`. I did not change it, because that is outside this task.
  timestamp: 2026-10-07T13:19:01.052140+00:00
- actor: wballard
  id: 01m4b89007mjyp8nqjdmh9ppne
  text: |-
    ### implement — changed
    - evidence: 5 files. New: Sources/FoundationModelsKanban/Identity/NodeURI.swift, Sources/FoundationModelsKanban/Identity/LocalRef.swift, Tests/FoundationModelsKanbanTests/Identity/NodeURITests.swift, Tests/FoundationModelsKanbanTests/Identity/LocalRefTests.swift. Changed: Sources/FoundationModelsKanban/GraphQL/PatchSchema.swift (`CaseIterable` on `PatchNodeType`). `swift test --filter "NodeURITests|LocalRefTests"` gives 29 tests in 2 suites passed. `swift test` gives 121 tests in 8 suites passed, with 0 warnings.
    - next: /review
  timestamp: 2026-10-07T13:19:04.711950+00:00
depends_on:
- 01M4B3V22A3PCQRESESTYBQ2FH
position_column: doing
position_ordinal: '80'
title: 'Identity: NodeURI and LocalRef'
---
## What
The two forms of a node identifier. The basis is plan.md §3.2 and §12 item 18.
- `Sources/FoundationModelsKanban/Identity/NodeURI.swift`: parse and format `kanban://<board-key>/<type>/<local-id>` and `kanban://<board-key>/board`. The board key has slashes (`host/owner/repo`), so the parser finds the type segment from the end.
- `Sources/FoundationModelsKanban/Identity/LocalRef.swift`: `LocalRef` (`board`, `column/doing`, `actor/x`, `task/<ULID>`, `tag/x`, `comment/<ULID>`). Conversion `NodeURI` ↔ `LocalRef` with a given current board key.
- `StoredRef` enum: `.local(LocalRef)` or `.remote(NodeURI)`. The rule: a stored string that starts with `kanban://` is remote; all others are local.
- A full URI whose key is the current key converts to `.local`.

## Acceptance Criteria
- [x] Each of the six node types round-trips URI → LocalRef → URI.
- [x] A URI with the current key gives `.local`; a URI with a different key gives `.remote`.
- [x] A malformed URI gives a typed error.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Identity/NodeURITests.swift` and `LocalRefTests.swift`.
- [x] Run `swift test --filter NodeURITests` and `--filter LocalRefTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.