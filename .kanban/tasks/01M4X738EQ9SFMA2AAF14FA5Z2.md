---
assignees:
- claude-code
depends_on:
- 01M4X6ZBTA66TCPVYM41QR0ACD
position_column: todo
position_ordinal: '9480'
title: Make cross-board undo write nothing when it cannot reach each board, also on a second copy
---
## What
divergence.md X5 and S8 (§1.1, §7, §11 bugs; K6 stays as work). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem:
- X5: undo across boards can reverse part of a transaction, with no error. `boards(of:)` changes each key to the first copy in scan order (S/GraphQL/UndoMutations.swift:192-201). Then the undo field drops each board where the reverse wrote no events (:119). Example: a write to a second worktree of `lib`. The undo looks at the first copy, finds nothing, and reverses only the current board.
- S8: the `boards` list cannot name a second copy of the same repo. An undo reverses only one copy.

Each worktree has its own board with the same key (M6 final), so this case is normal now.

Change:
- Undo (and redo) of a transaction finds each board that the transaction wrote by the events themselves, not only by key: look in each loaded copy with that key (the host table), and use the copy that holds events of that `txn`.
- When undo cannot reach a board that the transaction wrote (no loaded copy has its events), undo writes nothing on any board and gives a clear error that names the board key. It does not reverse part of the transaction.
- Let the `boards` input of undo name a copy by path, so that an agent can name a second copy.

## Acceptance Criteria
- [ ] A transaction that wrote the current board and the second copy of `lib` is reversed on both by `undo`.
- [ ] When one board of the transaction is not reachable, undo writes nothing and gives an error that names that board.
- [ ] `undo(boards: ["<path of second copy>"])` reaches that copy.

## Tests
- [ ] Undo on a second copy (worktree) of the same repo (this is also in the K14 missing tests).
- [ ] Undo with one board missing: no events written on any board.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.