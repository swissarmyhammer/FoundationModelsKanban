---
depends_on:
- 01M4B3V22A3PCQRESESTYBQ2FH
position_column: todo
position_ordinal: '8280'
title: 'Identity: NodeURI and LocalRef'
---
## What
The two forms of a node identifier. The basis is plan.md §3.2 and §12 item 18.
- `Sources/FoundationModelsKanban/Identity/NodeURI.swift`: parse and format `kanban://<board-key>/<type>/<local-id>` and `kanban://<board-key>/board`. The board key has slashes (`host/owner/repo`), so the parser finds the type segment from the end.
- `Sources/FoundationModelsKanban/Identity/LocalRef.swift`: `LocalRef` (`board`, `column/doing`, `actor/x`, `task/<ULID>`, `tag/x`, `comment/<ULID>`). Conversion `NodeURI` ↔ `LocalRef` with a given current board key.
- `StoredRef` enum: `.local(LocalRef)` or `.remote(NodeURI)`. The rule: a stored string that starts with `kanban://` is remote; all others are local.
- A full URI whose key is the current key converts to `.local`.

## Acceptance Criteria
- [ ] Each of the six node types round-trips URI → LocalRef → URI.
- [ ] A URI with the current key gives `.local`; a URI with a different key gives `.remote`.
- [ ] A malformed URI gives a typed error.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Identity/NodeURITests.swift` and `LocalRefTests.swift`.
- [ ] Run `swift test --filter NodeURITests` and `--filter LocalRefTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.