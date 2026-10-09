---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gcdfbjcpw596njp08acnyp
  text: |-
    Research:
    - `UndoLog.target(of:named:by:)` with a `txn` text checks only that the log has the transaction. It does not read `undoneState`.
    - `BoardStore.reverse` gives the target to `WorkingCopy.reverse`, which reverses the target transaction. Thus, today `redo(txn:)` takes the undo transaction U, not the original T.
    - `CrossRepoUndoTests.redoWithBoardReachesBoardThatIsNotLoaded` sends `redo(txn: U)` and has a comment that says "The `txn` of `redo` names the undo transaction". The card changes this rule: `redo(txn: T)` takes the original T. This test must change to send T.
    - Chosen rule for `redo(txn: T)` when T is undone: the target is the newest transaction after T whose `undoes` = T and that is not undone. The redo reverses that undo. This keeps `Change.undoes` of a redo = the undo transaction, the same as a redo with no `txn`.
    - `undoes` on the undo of T: `UndoneState` holds only a set. `UndoLog` has the transactions, so the lookup goes in `UndoLog`.
  timestamp: 2026-10-09T13:07:37.970277+00:00
- actor: claude-code
  id: 01m4gcq5v1xb22xheqqe9ex7sz
  text: |-
    Implementation:
    - `UndoLog.target(of:named:by:)` with a `txn` now calls the new private `target(of:naming:)`. For `undo`, a transaction that is already undone gives `NOTHING_TO_UNDO`. For `redo`, the `txn` names the original transaction T. The target is `currentUndo(of: T)`: the newest later transaction with `undoes` = T that is not undone. When T is not undone, there is no such transaction, and the call gives `NOTHING_TO_UNDO`. The check is before the force check in `WorkingCopy.reverse`, so `force: true` does not override it.
    - Choice (the card leaves this open): `redo(txn: T)` reverses the current undo of T. Thus the `Change.undoes` of the redo is the undo transaction, the same as a redo with no `txn`.
    - `CrossRepoUndoTests.redoWithBoardReachesBoardThatIsNotLoaded` now sends the original transaction to `redo`, and its comment says so. Before, it sent the undo transaction.
    - `UndoInput.txn` doc comment and plan.md §6.5 (`undo` and `redo` bullets) state the new rules. No new error code.
    - What did not work: the first RED test for the forced case used two title calls with no later change. A forced second undo there writes nothing (the inverse sets the value that is already there), so the old code also gave `NOTHING_TO_UNDO`. The body fixture has the same result. The final test adds a later title call after the undo, so a forced second undo would write a real patch.
  timestamp: 2026-10-09T13:12:55.905861+00:00
- actor: claude-code
  id: 01m4gcq8qd82wbrph300hmfkp0
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/Undo/UndoLog.swift, Sources/FoundationModelsKanban/GraphQL/UndoMutations.swift, Tests/FoundationModelsKanbanTests/Undo/UndoTests.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoUndoTests.swift, plan.md. RED then GREEN on 4 tests (6 cases). `swift test`: 1044 tests in 73 suites passed. Only warning: SwiftPM "missing creator for mutated node" (accepted).
    - next: /review
  timestamp: 2026-10-09T13:12:58.861267+00:00
depends_on:
- 01M4G9HG2TPCN1FH38714D8XF6
position_column: doing
position_ordinal: '80'
title: undo(txn:) on a transaction that is already undone
---
## What
`target(of:named:by:)` in `Sources/FoundationModelsKanban/Undo/UndoLog.swift` does not check `isUndone`. In the conflict check, the earlier undo `U` of `T` counts as a later change. Thus `undo(txn: T)` after `T` is undone gives `UNDO_CONFLICT` that names `U`, and with `force: true` it writes a second undo of `T`.

Final rules:
- `undo(txn: T)` when `T` is already undone gives the existing `NOTHING_TO_UNDO` code. This is also true with `force: true`. `force: true` does not override this error.
- `redo(txn: T)` takes the original transaction `T`. When `T` is not undone, it gives the existing `NOTHING_TO_UNDO` code. (`Sources/FoundationModelsKanban/GraphQL/Errors.swift` has no redo error code now.)
- Do not add a new error code.
- Do the check in `target(of:named:by:)`.
- Update plan.md §6.5.

## Acceptance Criteria
- [x] `undo(txn: T)` two times: the second call gives `NOTHING_TO_UNDO` and writes nothing, also with `force: true`.
- [x] `redo(txn: T)` when `T` is not undone gives `NOTHING_TO_UNDO` and writes nothing.
- [x] No new error code is in `Sources/FoundationModelsKanban/GraphQL/Errors.swift` or plan.md §4.4.

## Tests
- [x] Tests in `Tests/FoundationModelsKanbanTests/Undo/` for each acceptance criterion, with and without `force: true`.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.