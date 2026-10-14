---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4y3zps1ajd30248rr9hhq9j
  text: |-
    Research done. The line numbers on the card are stale after the KanbanHost task. The current sites:
    - KanbanGraph.loadRelatedBoard calls host.engine(ofBoardAt:knownKey:). Each related load goes through it: a board ref, a dependency URI, and each copy of Query.boards. An EventLogError or a BoardWatcherError of the load goes up through answer/relatedBoards to CommitSession.run (the `load` closure, Commit.swift run and runReading) and execute throws (X9).
    - KanbanGraph.publish catches the error of relatedBoards, logs it, and returns (X12).
    - The host table keeps no failed load: a failed load leaves no slot, so each call loads again.
    - Warnings: each KanbanContext has its own ResponseWarnings. The store of the last run holds the RelatedBoards of that run, so the warnings of the unreadable boards can go into the context of that run.
    - Danger found: BoardStore.target(of:) gives .current for each resolution that is not .copy. A new resolution case must not fall into that branch, or a write with `board:` goes to the current board.
    Plan: a new BoardResolution case `.unreadable(UnreadableBoard)` (copy + reason). board(resolvedAs:) gives nil, so a dependency on that board is not done. The host marks a board whose related load failed (not INCOMPATIBLE_BOARD, not a cancel) and keeps a file watcher on it; the first batch of that watcher clears the mark, and the next call loads again. Each call adds one warning (code BOARD_UNREADABLE) for each unreadable board in its run. INCOMPATIBLE_BOARD still stops the call.
  timestamp: 2026-10-14T21:09:40.257434+00:00
- actor: claude-code
  id: 01m4y5105kgc4z700wer7fhch7
  text: |-
    Implementation landed (TDD: each new test failed first, then passed).
    - New `BoardResolution.unreadable(UnreadableBoard)` (copy, reason, callFailure). `RelatedBoards.board(resolvedAs:)` gives nil for it, so a dependency on that board is not done (READY is false). `RelatedBoards.unreadableBoards` lists each one (from board refs, dependencies, and the Query.boards list).
    - `KanbanGraph.loadRelatedBoard` uses the new `KanbanHost.relatedEngine(ofBoardAt:knownKey:)` and returns `.unreadable` for each load error. Only a cancel still throws. An INCOMPATIBLE_BOARD error stays in `callFailure`, and `checkUnreadableBoards` (in the run closure of `runCall`) throws it, so a related Rust board still stops each call with the same response as before. Else each unreadable board adds one warning with code `BOARD_UNREADABLE`, the key, the `.kanban/` path, and the reason.
    - Change feed (X12): `publish` no longer fails for an unreadable board, also not for a Rust board (the decided exception is for calls only). A test covers a different process that adds a dependency on a related Rust board while a subscriber waits.
    - Host mark: `relatedEngine` keeps the error of a failed related load and starts a file watcher on the board (`.kanban/`, else the repo dir). Later related loads give the kept error with no file read. The first batch of that watcher clears the mark (`BoardLoadObserver.unreadableBoardDidChange(at:)` tells tests). A later successful load and `close()` end the watch. INCOMPATIBLE_BOARD and cancels are not marked.
    - `BoardStore.target(of:)` now throws NOT_FOUND for a write with `board:` that names an unreadable board (before, any non-copy resolution went to the current board). `Query.board(id:)` gives null plus the warning. A subscription with `board:` on an unreadable board now gives NOT_FOUND and ends (it ended with no response before).
    - Refactor: `BoardWatch.init(of:sendingBatchesTo:)` is the one shape of the engine watch, the scan-place watch, and the new unloadable watch.
    - Discovery: the error text in the warning is `String(describing:)` of the error, for example `fileSystem(path: ..., detail: ...)`.
    - Plan follow-up for a person: plan.md §4.4 does not list the new warning code `BOARD_UNREADABLE` (I did not edit plan.md).
  timestamp: 2026-10-14T21:27:51.219856+00:00
- actor: claude-code
  id: 01m4y512v4t1sqsvv03zxyamhw
  text: |-
    ### implement — changed
    - evidence: `swift test` 1244 tests in 93 suites passed, 0 failures; only the accepted SwiftPM "missing creator" warning. Files: Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift, CrossRepo/RelatedBoards.swift, GraphQL/Schema.swift, Observe/ChangeSubscription.swift, Tool/BoardEngine.swift, Tool/KanbanGraph.swift, Tool/KanbanHost.swift; new Tests/FoundationModelsKanbanTests/CrossRepo/UnreadableRelatedBoardTests.swift (10 test cases, `.watcherBudget`, temporary git sandboxes only).
    - next: /review
  timestamp: 2026-10-14T21:27:53.956137+00:00
depends_on:
- 01M4X6X6PS5P524DW45RBSSWN2
- 01M4X6ZBTA66TCPVYM41QR0ACD
position_column: doing
position_ordinal: '80'
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
- [x] A related board with no read permission does not fail the call; the response has a warning that names it.
- [x] A related board with a broken log does not fail the call; the response has a warning.
- [x] A task that depends on a task on that board is not READY.
- [x] A subscriber still gets the changes of the current board.
- [x] A related Rust board still gives `INCOMPATIBLE_BOARD`.

## Tests
- [x] A related board with no read permission.
- [x] A related board with a broken log.
- [x] A subscriber that still gets changes of the current board.
- [x] `{ board { name } }` works with a broken related board.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.