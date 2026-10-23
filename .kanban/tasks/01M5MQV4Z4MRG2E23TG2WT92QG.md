---
assignees:
- claude-code
position_column: todo
position_ordinal: '8780'
title: Give the txn of the call in each mutation result
---
## What

KanbanViewKit sends `undoChange(txn:)` and `redoChange(txn:)` for one transaction of the user (its plan §3.4, §6.4). Today `undoChange` and `redoChange` give a `Change` with its `txn`, but an ordinary mutation (for example `addTask`, `updateTask`, `moveTask`) gives only the node. The client then must read `Board.history` to find the `txn`.

- Make the `txn` of the call available in the result of each mutation, with no second read.
- Choose one form, and record it in `divergence.md`. Options:
  - a response `extensions` key (`extensions.txn`), with no schema change; or
  - a `txn` field on each mutation result type.
- A call that writes nothing (a refusal, a `dryRun`, a no-op) gives no `txn`.
- A document with many mutation fields is one transaction: each field gives the same `txn`.

## Acceptance criteria

- [ ] The result of each mutation that writes gives the `txn`.
- [ ] `undoChange(input: {txn: <that txn>})` reverses that call.
- [ ] A refused call gives no `txn`.

## Tests

- Unit tests in `T/` for each criterion, with at least `addTask`, `updateTask`, `moveTask` and `deleteTask`.
- `swift test` passes with no new warnings. #kanbanviewkit