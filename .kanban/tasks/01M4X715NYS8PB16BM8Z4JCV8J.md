---
assignees:
- claude-code
depends_on:
- 01M4X6X6PS5P524DW45RBSSWN2
- 01M4X6ZBTA66TCPVYM41QR0ACD
position_column: todo
position_ordinal: 8c80
title: Keep the call and the change feed working when a related board cannot be read
---
## What
divergence.md Q7 (DECIDED: yes), X9, X12, and §11 "Q7". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

- X9: one related board that cannot be read makes every call fail. `EventLogError` is not a `KanbanError`, so `execute` throws. This occurs also for `{ board { name } }`.
- X12: `publishLiveChanges` loads the dependency boards again. If one board fails, it logs the error, returns, and sends nothing (S/Tool/KanbanGraph.swift:433-446). Subscribers then lose all changes of the current board.

Decided behavior:
- The call continues. Each dependency on that board counts as not done (the task stays blocked). When `Task.unresolvedDependsOn` exists (task Q2), the target shows there.
- The response has a warning in `extensions.warnings` that names the board (key and path) and the reason.
- The change feed keeps sending the changes of the boards that load.
- Exception: an incompatible (Rust) related board still stops the call with `INCOMPATIBLE_BOARD` (Q6). This task does not change that.

Change the code at S/Tool/KanbanGraph.swift:761-775 (`loadRelatedBoard`) and :433-446 (`publishLiveChanges`), and S/Tool/Commit.swift:409-410 (after the KanbanHost task, these are in the host or engine load path). Catch the error for each board, mark the board as not loadable, and add a warning to the response. When the watcher sees that the board changes, try the load again.

## Acceptance Criteria
- [ ] A related board with no read permission does not fail the call; the response has a warning that names it.
- [ ] A related board with a broken log does not fail the call; the response has a warning.
- [ ] A task that depends on a task on that board is not READY.
- [ ] A subscriber still gets the changes of the current board.
- [ ] A related Rust board still gives `INCOMPATIBLE_BOARD`.

## Tests
- [ ] A related board with no read permission.
- [ ] A related board with a broken log.
- [ ] A subscriber that still gets changes of the current board.
- [ ] `{ board { name } }` works with a broken related board.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.