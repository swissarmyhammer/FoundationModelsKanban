---
depends_on:
- 01M4B3YQSXZCGCB08FVP8QCSF3
position_column: todo
position_ordinal: ad80
title: 'Queries: node, nodes, and tombstones'
---
## What
Direct access by id, and the read rules for deleted nodes. The basis is plan.md §4.1 (`Query.node`, `Query.nodes`) and §3.3 rule 3.
- `Sources/FoundationModelsKanban/GraphQL/QueryResolvers.swift` (node part): `Query.node(id:)` and `Query.nodes(ids:)` accept any short form or full URI and return the `Node` interface (all six types).
- Tombstones: lists and edges ignore a tombstone; `node` and `nodes` return it with `deleted` set; `Board.tasks(deleted: true)` lists only deleted tasks.
- `Comment.author` returns a deleted author as the tombstone.

## Acceptance Criteria
- [ ] `node(id:)` returns each of the six node types by full URI and by short form.
- [ ] A deleted task is not in `tasks`, and `node(id:)` returns it with `deleted` set; `tasks(deleted: true)` lists it.
- [ ] `nodes(ids:)` returns `null` at the position of an unknown id.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/GraphQL/NodeQueryTests.swift`.
- [ ] Run `swift test --filter NodeQueryTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.