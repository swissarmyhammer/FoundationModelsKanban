---
depends_on:
- 01M4B41N13P82QC4H6BBQRZ2PF
- 01M4B406Z7RVSBJKKJ8KJW0CY2
- 01M4B40CFSF002B4DKM3T8J6GV
- 01M4B4B57JFX8HA0B45MMDQ1SQ
- 01M4B4B1G28KK1NVCXHK9GDAYR
position_column: todo
position_ordinal: a380
title: Undo and redo in one board
---
## What
Reverse a transaction by appending inverse patches. The basis is plan.md §6.5 and §12 items 12 and 27.
- `Sources/FoundationModelsKanban/Undo/Inverse.swift`: the inverse table: `set` → `set` old or `unset`; `unset` → `set` old; `add` ↔ `remove`; `delete: true` ↔ `delete: false`; `edit body` → the reversed diff; first patch of a node that a mutation made explicitly → `delete: true`; a node made as a side effect (unknown tag, new actor, new column in `moveTask`, auto-init board, a tag made live by a marker) → no inverse.
- `undo(txn, force)` and `redo(txn, force)` mutations. No `txn`: `undo` takes the newest transaction of the session actor that is not undone and has no `undoes`; `redo` takes the newest `undo` of the session actor that is not reversed. Search only the boards that are loaded. The written patches have `undoes` = the reversed `txn`.
- Conflict: a later transaction that is not undone changed the same property (or set member), or made an edge to a node that the transaction made → `UNDO_CONFLICT` with the later transactions. For a body, a conflict only if the reversed diff does not apply. `force: true` writes the inverse anyway. Graph rules still apply. Nothing to undo → `NOTHING_TO_UNDO`.
- Result: the `Change` that `undo`/`redo` wrote.

## Acceptance Criteria
- [ ] For each public mutation, `undo` gives the same projection as before the call (except side-effect nodes), and `redo` gives the projection after it.
- [ ] Two `undo` calls in a row reverse the two newest original calls.
- [ ] Undo of a body change after a later change to other lines works; a conflict gives `UNDO_CONFLICT`, and `force` writes anyway.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Undo/UndoTests.swift`: all cases of plan.md §11 that name undo in one board (including `deleteTask` → `undo` → `redo`, and the side-effect tag case).
- [ ] Run `swift test --filter UndoTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.