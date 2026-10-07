---
depends_on:
- 01M4B433B8HKKXX0A08K77YCNF
- 01M4B42D1RWYD5DV5CSMBNXMJ3
position_column: todo
position_ordinal: b180
title: 'Cross-repo: cycle check and cross-board undo'
---
## What
The cross-board rules that need many boards at one time. The basis is plan.md §3.3 rule 6, §6.5 (Scope, Many boards), and §6.6.
- `DEPENDENCY_CYCLE` across boards: the check reads all boards on the path; the commit check of §5.4 covers these boards (lock them and compare signatures).
- `undo`/`redo` of a transaction that spans boards: reverse it in each board, in one call. If one board is not found, write nothing and return `NOT_FOUND` with the board name.
- `undo`/`redo` with no `txn` search the current board and the loaded boards only, and do not load other boards. The `board` input field selects a board for `undo(txn:, board:)` in a board that is not loaded.

## Acceptance Criteria
- [ ] One call that changes two boards is reversed by one `undo`.
- [ ] With one board missing, `undo` gives `NOT_FOUND` and writes nothing.
- [ ] Two processes that add the two halves of a cross-board cycle at the same time: one call gets `DEPENDENCY_CYCLE` after its commit check.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoUndoTests.swift` and `CrossRepoCycleTests.swift`, with two temporary git repos side by side.
- [ ] Run `swift test --filter CrossRepoUndoTests` and `--filter CrossRepoCycleTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.