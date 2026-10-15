---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4zcsqjd6cy3w161t5w7j2jr
  text: 'Research: the one source of the task tag order is `Graph.tagSlots(of:)` in S/Tags/TagMarkers.swift. `TaskObject.tags` (S/GraphQL/QueryResolvers.swift) calls it, and the change feed (`TaskObject.trackedFields` in S/Observe/ChangeBuilder.swift) reads `TaskObject.tags`. `TaskSearchItem.tagNames` also reads `TaskObject.tags`. The filter (`FilterEvaluator`) uses only `contains`, so the order does not change it. Plan: sort the live tag slots by the slug of the tag node in `tagSlots(of:)`. Test to change: TagResolveTests "The edges come first, then the markers, in text order".'
  timestamp: 2026-10-15T09:02:56.077510+00:00
- actor: claude-code
  id: 01m4zd6ndx5msdvrtsg1z6wvfs
  text: |-
    ### implement — changed
    - evidence: S/Tags/TagMarkers.swift (`Graph.tagSlots(of:)` sorts the live tag slots by the slug of the tag at the end of the rename redirect), S/GraphQL/QueryResolvers.swift (doc of `TaskObject.tags`). Tests: TagResolveTests (old test "The edges come first, then the markers, in text order" replaced by 3 sort tests), AddUpdateTaskTests (addTask with edge `zeta` and marker `#alpha` gives `[alpha, zeta]`), ChangeBuilderTests (the `tags` field change gives `added` in slug order), TaskOperationTests (tagTaskWithTwoTags now expects `[bug, feature]`). RED: 5 new tests failed with the old edge-first order. GREEN: 5 passed. Full `swift test`: 1391 tests, 1 failure (tagTaskWithTwoTags, old order); fixed and that test passed alone. Only the accepted "missing creator" SwiftPM warning.
    - discovery: the change feed and TaskSearchItem read `TaskObject.tags`, so the one change in `tagSlots(of:)` covers queries, the change feed, and search. The filter only uses `contains`, so the order does not change it.
    - next: /review
  timestamp: 2026-10-15T09:09:59.869569+00:00
position_column: doing
position_ordinal: '80'
title: Sort Task.tags by slug
---
## What
divergence.md F9 (§8; §15 "F9: fix"; §11). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem: tag order. Rust sorts the tags. Swift gives the edges first, then the markers in text order.

Change: `Task.tags` returns the tags (from edges and from body markers, without duplicates) sorted by slug, as Rust does. Apply the same order everywhere the task tags are returned (queries and change-feed payloads).

## Acceptance Criteria
- [x] A task with the edge tag `zeta` and the body marker `#alpha` returns `[alpha, zeta]`.
- [x] A tag that is both an edge and a marker shows one time.

## Tests
- [x] A test with edge and marker tags in a mixed order.
- [x] Update existing tests that depend on the old order.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.