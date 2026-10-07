---
depends_on:
- 01M4B3XHRVFA2YDCJC76MAFQR5
- 01M4B3VX4HPNXHC77F2RKYE37K
position_column: todo
position_ordinal: 8f80
title: 'Tags at read time: markers and rename redirect'
---
## What
Calculate the tags of a task. The basis is plan.md §6.1 and §6.2.
- `Sources/FoundationModelsKanban/Tags/TagMarkers.swift`: parse `#tag` markers in a body (port the parse part of `../swissarmyhammer/crates/swissarmyhammer-kanban/src/tag_parser.rs`), and normalize each to its slug.
- Redirect walk: follow `renamedTo` from tag to tag. A cycle (from a merge) stops at the first slug that repeats, and uses that tag.
- `task.tags` = resolve(tag edges) ∪ resolve(markers in the current body). A resolve that ends at a tombstone drops the tag.
- `Board.tags` lists the live tags with no `renamedTo`, plus the stop tag of a rename cycle.
- Helper to remove a marker from a body (the `untagTask` mutation uses it later).

## Acceptance Criteria
- [ ] `#bug` in the body gives the tag `bug`; an edge and a marker to one tag give it one time.
- [ ] After a redirect `bug → defect`, an edge to `bug` and a marker `#bug` both show `defect`.
- [ ] A rename cycle does not loop, and gives the stop tag.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift` (ported parse tests) and `TagResolveTests.swift` (union, redirect, chain, cycle, tombstone).
- [ ] Run `swift test --filter TagMarkersTests` and `--filter TagResolveTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.