---
assignees:
- claude-code
position_column: todo
position_ordinal: '9580'
title: Add the undo conflict check across boards
---
## What
divergence.md X6 and R13 (§1.1, §11 bugs; K7 stays as work). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem: undo has no conflict check across boards. The rule (§6.5 of the design): a later edge to a node that the undo would tombstone is a conflict. Now this check is for the same board only (S/GraphQL/UndoMutations.swift:260-271). Example: call 1 adds `lib#X`. Call 2 adds `app#Y`, which depends on `X`. `undo(call1)` gives no `UNDO_CONFLICT`. It tombstones `X`, and `Y` becomes READY with no warning.

Change: when an undo would tombstone a node, also look for later edges to that node from tasks on the other loaded boards (edges and body markers with the full URI of the node). If one exists, give `UNDO_CONFLICT` (the same error as in one board) and write nothing.

## Acceptance Criteria
- [ ] In the example, `undo(call1)` gives `UNDO_CONFLICT` and writes nothing.
- [ ] The same with a body marker in `app#Y` in place of the edge.
- [ ] An undo with no cross-board edge to the node works as before.

## Tests
- [ ] The example with an edge (this is also in the K14 missing tests).
- [ ] The example with a body marker.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.