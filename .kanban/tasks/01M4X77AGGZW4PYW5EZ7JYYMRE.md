---
assignees:
- claude-code
depends_on:
- 01M4X6ZBTA66TCPVYM41QR0ACD
position_column: todo
position_ordinal: a380
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
- [ ] `moveTask(id: X, board: "<other repo>")` makes the task on the other board and tombstones `X` on the old board, in one transaction.
- [ ] The old task body has a line with the new task URI.
- [ ] `copyTask(id: X, board: "<other repo>")` makes a copy and keeps `X`.
- [ ] Dependencies of the moved task on the old board still resolve (as full URIs).
- [ ] Missing tags are made on the target board.
- [ ] `undo` of a move restores both boards.

## Tests
- [ ] Move and copy across two repos.
- [ ] Dependencies still resolve after a move.
- [ ] Dependents on the old board (they find the pointer line; the old task is a tombstone, so it is ignored for readiness).
- [ ] Undo of a move across boards.
- [ ] A tag that the target board does not have is made there (edge tag and marker tag).
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.