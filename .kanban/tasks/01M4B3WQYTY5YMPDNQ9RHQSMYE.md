---
depends_on:
- 01M4B3VF41P7FCKEC4MFT9GWA0
position_column: todo
position_ordinal: 8a80
title: 'Graph store: node table with stable slots'
---
## What
The in-memory graph. The basis is plan.md §3.1, §3.3, and §5.3 (Join).
- `Sources/FoundationModelsKanban/Model/Graph.swift`: a Swift value type (copy-on-write). A node table where each node has a stable integer slot. A map `LocalRef → slot`. A slot keeps its number for the life of the graph.
- Node state types in `Model/`: `BoardNode`, `ColumnNode`, `ActorNode`, `TagNode`, `TaskNode`, `CommentNode`. Each has `body`, a tombstone flag, and the time values `created`, `updated`, `deleted`. A task also has its list of column moves (time, column).
- Edges hold `EdgeTarget`: `.slot(Int)` or `.unresolved(StoredRef)`.
- Operations: insert or replace the state in a slot, remove a node from its slot (its edges become unresolved), resolve unresolved edges when a new slot comes.

## Acceptance Criteria
- [ ] A replace of one node keeps the edges of other nodes correct.
- [ ] A copy of the graph and a change to the copy does not change the original.
- [ ] A remove makes the edges to that node unresolved; a later insert resolves them again.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Model/GraphTests.swift`.
- [ ] Run `swift test --filter GraphTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.