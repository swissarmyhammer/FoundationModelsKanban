---
depends_on:
- 01M4B412DB2BSB0FAQEA72WN8T
- 01M4B3Z67TC96REJGDHD2DFH0R
position_column: todo
position_ordinal: a080
title: History query and undone state
---
## What
List the transactions of a board. The basis is plan.md §6.5 (history, undone state) and §6.7 (Arguments).
- `Sources/FoundationModelsKanban/Undo/UndoneState.swift`: a transaction is undone when a later transaction has `undoes` = its `txn` and that later transaction is not itself undone. Derived from the global event list; no stored stack.
- `Undo/History.swift`: group the global event list by `txn`; build each `Change` with `ChangeBuilder` (projection before and after the transaction).
- `Board.history(type, node, actor, filter, derived, since, first)`: newest first; `since` = only the transactions after that `txn`; `filter` keeps updates of matching tasks and of their comments; a `Change` with no update after the filters is not returned.

## Acceptance Criteria
- [ ] `history` lists the transactions newest first, with `ops`, `actor`, and `updates`.
- [ ] `history(since: <txn>)` returns only the later transactions.
- [ ] After a `union` merge of two branches, the undone state is correct for transactions from both branches.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Undo/HistoryTests.swift` and `UndoneStateTests.swift`.
- [ ] Run `swift test --filter HistoryTests` and `--filter UndoneStateTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.