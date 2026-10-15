---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4zdw3makpf1z9bhbkq1cnz7
  text: |-
    Research done. Findings:
    - The multi-board commit already exists. BoardStore (S/GraphQL/Schema.swift) has runField(as:in:) for one target board and runField(as:inEach:) for many boards, with a restore of `work` and `relatedWork` on failure. All patches of one call share one stamp, so one txn. The commit records the keys of the other changed boards in `boards` of each event, so the cross-board undo (UndoMutations.swift) reverses both boards with no new code.
    - Source board: MutationBoard.holding(id). Target board: MutationBoard.named(board). target(of:) gives .current or .related(RelatedWork).
    - A related Rust board stops each call that reaches it with INCOMPATIBLE_BOARD (KanbanGraph.checkUnreadableBoards). The move must write nothing then.
    - TaskMutations.swift `write(_:toTask:inBoard:at:)` makes marker tags, applies the task patch, runs the cycle check, and gives the dependency warnings. It is fileprivate now; the plan is to make it and TaskChange internal for reuse.
    - ensureLiveTag (TagMutations.swift) makes a missing tag with a name and color, or makes a tombstone live.
    - Task.assignees reads only resolved slots, so an assignee stored as a remote URI (the card rule) does not show in Task.assignees on the target board. This is the decided behavior of the card; a follow-up task records the read side.
    Plan: new file S/GraphQL/TaskTransferMutations.swift with copyTask, plus a `board` field on MoveTaskInput. When `board` names the same board as the task, moveTask does the old in-board move (forgiving).
  timestamp: 2026-10-15T09:21:42.538874+00:00
- actor: claude-code
  id: 01m4zew3tazjxytkzzkyg6m5w7
  text: |-
    Implementation landed. Notes for the next agent:
    - New file S/GraphQL/TaskTransferMutations.swift: `copyTask`, `TaskPlacementFields` + `TaskPlacementInput` (shared input fields of MoveTaskInput and CopyTaskInput, with a `board` field), `BoardStore.transfer(_:as:at:)`, `BoardStore.isBoard(_:holdingTask:)`, `TaskCopy`, `StoredRef.carried(from:to:)`, `WorkingCopy.addCopy` and `retire`.
    - `BoardStore.runAtomically(_:)` (Schema.swift) keeps all steps of one field or none; `runField(as:inEach:)` now uses it.
    - `moveTask`: `column` is now optional (no column keeps the column where the task shows). A `board` that names the board of the task does the old in-board move. A different board calls the transfer.
    - The transfer writes the new task first (its URI is needed for the pointer line), then the body line "Moved to <uri>" and the tombstone on the old board. One stamp, so one txn; the commit records `boards`, so the existing cross-board undo reverses both boards with no undo change.
    - `TaskChange` and `WorkingCopy.write` in TaskMutations.swift are now internal, for reuse (marker tags, cycle check, dependency warnings).
    - Alias table: MoveTaskInput and CopyTaskInput share `taskPlacement`, with board aliases toBoard, targetBoard, destination, repo.
    - A related Rust board already stops the call with INCOMPATIBLE_BOARD (KanbanGraph.checkUnreadableBoards); the test shows no log of the current board changes.
    - TDD: CrossRepoTransferTests (15 tests) were RED first (fields missing from the schema), then GREEN. The test `moveTaskWithNoColumnKeepsColumn` was written after the optional-column code, so it did not fail first.
    Follow-up tasks: ^x020t0g (Task.assignees does not show a remote assignee URI), ^yf3bpss (decide what a move does with comments).

    ### implement — changed
    - evidence: `swift test` 1407 tests in 110 suites passed, 0 failures, only the accepted SwiftPM "missing creator" warning. Files: S/GraphQL/TaskTransferMutations.swift (new), S/GraphQL/TaskOperationMutations.swift, S/GraphQL/TaskMutations.swift, S/GraphQL/Schema.swift, S/GraphQL/SchemaDescription.swift, S/GraphQL/FieldAliases.swift, Tests/.../CrossRepo/CrossRepoTransferTests.swift (new), Tests/.../Mutations/TaskOperationTests.swift.
    - next: /review
  timestamp: 2026-10-15T09:39:11.306529+00:00
depends_on:
- 01M4X6ZBTA66TCPVYM41QR0ACD
position_column: doing
position_ordinal: '80'
title: Add moveTask(board:) and copyTask to move or copy a task to a different board
---
## What
divergence.md Q21 (DECIDED: add it now; K1 not cut), E6 (DECIDED), G8, and §11 "Q21". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/). Code: S/GraphQL/TaskOperationMutations.swift.

Decided behavior:
- Add a `board` field on `moveTask` to move a task to a different board, and a new `copyTask` mutation to copy a task to a different board (with an optional target `column` and `before`/`after`, like `moveTask`).
- Write the events on both boards in one transaction, under the locks of both boards (take the locks in the fixed order of the host, so two sessions cannot deadlock).
- In the new task, each local ref (for example a `dependsOn` edge to a task on the old board, or an assignee) becomes a full `kanban://` URI where it points to the old board, so that the dependencies on the old board still resolve. Column refs map to the target board.
- E6: a move or a copy keeps all tags. Swift makes each missing tag on the target board. (This is different from Rust, which drops them.) A tag marker in the body also makes the tag on the target board.
- A move tombstones the old task. E6: a move also adds a line to the old task body that points to the new URI, so that dependents on the old board can find it.
- Undo of a move or a copy reverses both boards.
- A target board that is an incompatible (Rust) board gives `INCOMPATIBLE_BOARD` and writes nothing (see the Q6 task).

## Acceptance Criteria
- [x] `moveTask(id: X, board: "<other repo>")` makes the task on the other board and tombstones `X` on the old board, in one transaction.
- [x] The old task body has a line with the new task URI.
- [x] `copyTask(id: X, board: "<other repo>")` makes a copy and keeps `X`.
- [x] Dependencies of the moved task on the old board still resolve (as full URIs).
- [x] Missing tags are made on the target board.
- [x] `undo` of a move restores both boards.

## Tests
- [x] Move and copy across two repos.
- [x] Dependencies still resolve after a move.
- [x] Dependents on the old board (they find the pointer line; the old task is a tombstone, so it is ignored for readiness).
- [x] Undo of a move across boards.
- [x] A tag that the target board does not have is made there (edge tag and marker tag).
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.