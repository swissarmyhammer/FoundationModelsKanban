---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4xhwn5ymtjv5dmwa1h1yjnv
  text: |-
    Research done.
    - Each board load goes through KanbanGraph.loadSession: loadedBoard (current board) and loadRelatedBoard (each related board, also for a `board:` mutation and for Query.boards). An error that loadSession throws goes out of runCall, so the whole call fails.
    - runSchemaCall turns only a KanbanError into the error response. An EventLogError makes execute throw. So the Rust-board error must become KanbanError at that point.
    - EventLog.prepareDirectory runs before each append and in BoardLock (lock of a commit). It makes `.kanban/` and the git files. A real Rust board has `.gitignore` but no `.gitattributes`, so without a check Swift writes `.gitattributes` into the Rust board.
    - The watcher of the current board starts before loadSession, but it applies nothing while the board is not loaded.
    - Plan: EventLog gets the Rust-only path check (one function that the host can call). EventLogError gets a new case for an incompatible board. loadSession and prepareDirectory call the check. runSchemaCall maps the EventLogError case to the new KanbanError.incompatibleBoard (code INCOMPATIBLE_BOARD).
  timestamp: 2026-10-14T15:53:25.950644+00:00
- actor: claude-code
  id: 01m4xjfy93k3vdh1entaqv8064
  text: |-
    Implementation landed (TDD: the new tests failed first for the correct reason, then passed).
    - New `EventLog.checkCompatibility()` in Sources/FoundationModelsKanban/Events/IncompatibleBoard.swift. It reads only names: the top of `.kanban/` (boards, perspectives, views, projects, .gitconfig, search-cache.sqlite3, undo_stack.yaml, mcp*.log) and `*.yaml` / `*.md` files in each node directory. The KanbanHost task can call it when it loads a board.
    - New `EventLogError.incompatibleBoard(directory:)` and `KanbanError.incompatibleBoard(directory:)` (code INCOMPATIBLE_BOARD, message "There is an incompatible board at `<path>/.kanban`. Remove it, then try again.").
    - `KanbanGraph.loadSession` runs the check before the loader reads a file. This one path loads the current board and each related board.
    - `EventLog.prepareDirectory` runs the check first, so no auto-init and no commit lock writes into a Rust `.kanban/` (a real Rust board has `.gitignore` but no `.gitattributes`, so before this change Swift wrote `.gitattributes` into it).
    - `runSchemaCall` maps the error through new `KanbanError(callFailure:)`, so the call gives one INCOMPATIBLE_BOARD error response and writes nothing.
    - `EventLog.items(in:)` is a new shared directory listing; `nodeRefs` now uses it too.
    - README: one bullet about INCOMPATIBLE_BOARD.
    Discoveries for the next agent:
    - `moveTask(board:)` and `copyTask` do not exist yet (task ^7zw4yre). They will go through loadRelatedBoard, so the check covers them; add their tests in that task.
    - `Query.boards` loads each copy that the scan finds. A sibling repo with a Rust `.kanban/` now stops the `boards` call with INCOMPATIBLE_BOARD. This follows Q6, but the default scan looks in the parent folder, where many repos of the user still have Rust boards. Recorded as a new task for a decision.
    - divergence.md Q6 says plan.md §12 item 11 must change. I did not edit plan.md (rule).
    - `swift test`: 1169 tests in 85 suites passed. `swift build --build-tests` shows only the accepted mlx warnings.
  timestamp: 2026-10-14T16:03:57.859200+00:00
- actor: claude-code
  id: 01m4xjgqgknz8w2h33ft96ngyx
  text: |-
    Correction to the comment above: the moveTask(board:)/copyTask task is ^7jyymre (not ^7zw4yre). Its card already asks for an INCOMPATIBLE_BOARD test. New task for the boards-listing decision: ^nxrqcgn.

    ### implement — changed
    - evidence: 8 files — Sources/FoundationModelsKanban/Events/IncompatibleBoard.swift (new), Sources/FoundationModelsKanban/Events/EventLog.swift, Sources/FoundationModelsKanban/GraphQL/Errors.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Tests/FoundationModelsKanbanTests/Tool/IncompatibleBoardTests.swift (new), Tests/FoundationModelsKanbanTests/GraphQL/KanbanErrorTests.swift, README.md; `swift test` 1169 tests in 85 suites passed, no new build warnings.
    - next: /review
  timestamp: 2026-10-14T16:04:23.699840+00:00
depends_on:
- 01M4X6XKP0Y832GDRHQ1MG22VF
position_column: doing
position_ordinal: '80'
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
- [x] A current board with any Rust-only path gives `INCOMPATIBLE_BOARD` with the exact message, and changes no file.
- [x] A related board with Rust files gives `INCOMPATIBLE_BOARD` and the call stops.
- [x] A mutation with `board:` that names a Rust board gives the error and writes nothing.
- [x] Swift does not make a new board in a `.kanban/` with Rust files.
- [x] A clean Swift `.kanban/` opens as before.

## Tests
- [x] A Rust board as the current board gives the error and changes no file (compare a listing with sizes and modification times before and after).
- [x] A related Rust board gives the error.
- [x] Swift does not make a new board in a `.kanban/` with Rust files.
- [x] One test for each Rust-only path in the list above.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.