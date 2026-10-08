---
position_column: todo
position_ordinal: b380
title: 'Change.actor: resolve the actor in the board of the change'
---
## What
`Change.actor` (Observe/Change.swift) resolves `actorRef` in `context.store.view`: the current board of the call. Two cases give the wrong board:
- `board(id: <related>) { history { actor { name } } }`: the change is of the related board, and its actor ref is local to that board.
- A `DERIVED`-only change of the change feed (plan.md §6.7, derived updates across boards): the subscriber observes board A, and the transaction is of board B. The actor ref is local to B.
When board A has no actor with that slug, the field gives `NOT_FOUND`, and `actor: Actor!` makes the full change `null`.

Found while implementing ^3ahg2ct. Resolve the actor in the board whose key is `Change.boards[0]` (the board of the change), for example through the related boards of the view.

## Acceptance Criteria
- [ ] `history { actor { name } }` of a related board gives the actor of that board.
- [ ] A `DERIVED`-only change of a subscription gives the actor of the board of the transaction.

## Tests
- [ ] A test in `Tests/FoundationModelsKanbanTests/Undo/HistoryTests.swift` or `CrossRepo` with an actor that only the related board has.