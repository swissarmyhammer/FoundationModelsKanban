---
position_column: todo
position_ordinal: b380
title: 'Event board of a related-board subscription: `.current` reads the wrong board'
---
## What
Found while implementing ^0ahzwrz. Two related gaps:

1. A subscriber that observes a RELATED board B (`changes(board: B)`) gets events whose store holds B (`BoardStore.replace(with:)`). The `related` value of the event is `round.after` (`KanbanGraph.publishLiveChanges`). In that value, the key of the engine current board C resolves to `.current`. But `BoardStore.reading` does `related.with(current: snapshot)`, and the snapshot is B. Thus each read of the key of C in the event resolvers reads B:
   - `Change.actor` of a `DERIVED`-only change for a transaction of C looks up the actor in B (NOT_FOUND, or the actor of B with the same slug).
   - The cross-board readiness of a task of B that depends on a task of C reads B as C.
2. `NodeUpdate.node` (Observe/Change.swift) reads `context.store.view`. For `board(id: <related>) { history { updates { node { id } } } }` the node is of the related board, but the store view is the current board of the call.

## Acceptance Criteria
- [ ] A subscription on a related board B that depends on a task of the engine current board C gives, for a transaction of C, the actor of C and the correct `ready` value of the task of B.
- [ ] `history { updates { node { id } } }` of a related board gives the nodes of that board.

## Tests
- [ ] Tests in `Tests/FoundationModelsKanbanTests/CrossRepo/` for both criteria.