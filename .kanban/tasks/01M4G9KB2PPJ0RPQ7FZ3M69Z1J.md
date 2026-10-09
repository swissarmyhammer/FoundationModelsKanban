---
assignees:
- claude-code
depends_on:
- 01M4G9HG2TPCN1FH38714D8XF6
position_column: todo
position_ordinal: '9080'
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
- [ ] `undo(txn: T)` two times: the second call gives `NOTHING_TO_UNDO` and writes nothing, also with `force: true`.
- [ ] `redo(txn: T)` when `T` is not undone gives `NOTHING_TO_UNDO` and writes nothing.
- [ ] No new error code is in `Sources/FoundationModelsKanban/GraphQL/Errors.swift` or plan.md §4.4.

## Tests
- [ ] Tests in `Tests/FoundationModelsKanbanTests/Undo/` for each acceptance criterion, with and without `force: true`.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.