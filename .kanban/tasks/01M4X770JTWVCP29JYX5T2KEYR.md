---
assignees:
- claude-code
position_column: todo
position_ordinal: a280
title: Sort Task.tags by slug
---
## What
divergence.md F9 (§8; §15 "F9: fix"; §11). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem: tag order. Rust sorts the tags. Swift gives the edges first, then the markers in text order.

Change: `Task.tags` returns the tags (from edges and from body markers, without duplicates) sorted by slug, as Rust does. Apply the same order everywhere the task tags are returned (queries and change-feed payloads).

## Acceptance Criteria
- [ ] A task with the edge tag `zeta` and the body marker `#alpha` returns `[alpha, zeta]`.
- [ ] A tag that is both an edge and a marker shows one time.

## Tests
- [ ] A test with edge and marker tags in a mixed order.
- [ ] Update existing tests that depend on the old order.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.