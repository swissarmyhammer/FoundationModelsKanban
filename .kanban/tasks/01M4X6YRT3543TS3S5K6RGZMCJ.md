---
assignees:
- claude-code
depends_on:
- 01M4X6XKP0Y832GDRHQ1MG22VF
position_column: todo
position_ordinal: '8380'
title: Detect an incompatible (Rust) .kanban folder and stop with INCOMPATIBLE_BOARD
---
## What
divergence.md Q6 (final decision; it replaces the first decision and C2, E2, E3), S1, and §11 "Q6". The Swift package (S/ = Sources/FoundationModelsKanban/) uses the same log paths as the old Rust kanban (for example `.kanban/columns/todo.jsonl` and `.kanban/tasks/<ULID>.jsonl`). On a Rust board, Swift now reads each Rust line and fails, and its auto-init appends Swift events into Rust files. The Rust board log is `boards/board.jsonl`, so the locator does not see a Rust board as enabled and auto-inits on it.

Decided behavior (Swift never deletes, imports, or changes a Rust board; it only finds it and reports it):
- Add a new error code `INCOMPATIBLE_BOARD`. The message: "There is an incompatible board at `<path>/.kanban`. Remove it, then try again."
- A `.kanban/` is incompatible when it contains a Rust-only path: `boards/`, `*.yaml` or `*.md` entity files, `perspectives/`, `views/`, `projects/`, `.gitconfig`, `search-cache.sqlite3`, `undo_stack.yaml`, or `mcp*.log`.
- The check runs early, before any read or write of that `.kanban/`. Swift does not try to continue around the board. It changes no file.
- The check applies to each `.kanban/` that Swift opens: the current board and each related board. An incompatible related board stops the call with the error (an exception to Q7, which gives only a warning for other read errors).
- A write that names a related Rust board (a mutation with `board:`, `moveTask(board:)`, `copyTask`) gives the error and changes nothing.
- Swift never makes a new board (auto-init) in a `.kanban/` that has Rust files. Check before `prepareDirectory` in S/Events/EventLog.swift:137-150 and before auto-init in a related repo.
- There is no git check and no check for a running Rust server.
- Put the check in one place: in `loadSession` (S/Tool/KanbanGraph.swift:562), so that it covers the current board and related boards (`loadRelatedBoard`, :761-775). The KanbanHost task will later move this load path; keep the check in a function that the host can call when it loads a board.

IMPORTANT: this repo's own `.kanban/` is a Rust board, and it stays one while we use the old Rust tool to track tasks. Tests must use temporary fixture folders only. Never point a test, or the Swift code, at this repo's `.kanban/`, and never change it.

## Acceptance Criteria
- [ ] A current board with any Rust-only path gives `INCOMPATIBLE_BOARD` with the exact message, and changes no file.
- [ ] A related board with Rust files gives `INCOMPATIBLE_BOARD` and the call stops.
- [ ] A mutation with `board:` that names a Rust board gives the error and writes nothing.
- [ ] Swift does not make a new board in a `.kanban/` with Rust files.
- [ ] A clean Swift `.kanban/` opens as before.

## Tests
- [ ] A Rust board as the current board gives the error and changes no file (compare a listing with sizes and modification times before and after).
- [ ] A related Rust board gives the error.
- [ ] Swift does not make a new board in a `.kanban/` with Rust files.
- [ ] One test for each Rust-only path in the list above.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.