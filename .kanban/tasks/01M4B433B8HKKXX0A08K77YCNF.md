---
comments:
- actor: wballard
  id: 01m4cxqpsethf2d0afz8c294wx
  text: |-
    Research done. Findings:
    - Each public mutation goes through `BoardStore.runMutation(named:at:_:)` (initBoard, updateBoard) or `BoardStore.changeNode(named:at:_:)` / `KanbanContext.changeNode` (all node mutations, incl. `changeTask` and `changeDeleted`). Undo uses `runMutation` on the current board only (cross-board undo is ^s3e6hrm).
    - `BoardStore` holds one `WorkingCopy` (current board). `RelatedBoards` holds read-only `BoardSnapshot` values that the engine installs from `relatedBoards.mapValues(\.session.snapshot)`. A related board that is not enabled is still loaded (empty live graph), so auto-init in `runMutation` works on a working copy of it.
    - `CommitSession.commit` already locks through `EventLog.lock(sortedByKey:)`, which takes a `[BoardKey: EventLog]` dictionary. Two copies of one repo have the same key, so a dictionary drops one lock.
    - `Event.boards` exists (`[String]?`, nil for one board). `ChangeBuilder` already reads it.
    - `RefResolver` with the key of the target board already gives a local ref for a URI of its own key and `.remote(uri)` for a different key, so the stored-ref rule holds when the resolver of a field uses the key of the board that the field writes to.
    - `BoardStore.knownSessionActor` is computed for the current board only. addTask in a related board needs the value of that board.
    Plan: per-board working copies in `BoardStore`, one shared `EventStamp` (same txn, increasing ids) moved between the working copies, `ops` recorded in the working copy of the current board, and one generalized `CommitSession.commit` that locks, checks, appends and adopts each changed board. The engine gets the committed related sessions back through a second closure.
  timestamp: 2026-10-08T04:53:21.326460+00:00
- actor: wballard
  id: 01m4cypb9m5sk9m1z5fvynsazk
  text: |-
    ### Design choices (not in plan.md)
    - Each related board that a call changes gets its own working copy in `BoardStore.relatedWork`, by the canonical path of its repo. All working copies of a call use one `EventStamp`, so they share one `txn` and the event ids increase across the boards.
    - The `ops` of the call are recorded in the working copy of the current board, and each board writes the same `ops` list.
    - There is one commit path: `CommitSession.commit(_:along:)`. It locks each changed board in key order, then in path order for two copies with the same key. Then it checks each board, appends to each board, and adopts each new live graph.
    - `boards` holds the sorted keys of the other changed boards. It does not hold a key that is the same as the key of the board, and it is `nil` when the call changes one board.
    - The engine gets the new sessions of the related boards through a closure (`RelatedBoardStore`). Thus the file watcher of a related board finds no change for the write of this process.
    - `knownSessionActor` moved from `BoardStore` to `WorkingCopy`, so that the actor rule of `addTask` applies in each board.
    - `renameTag`: a full URI in `from` names its own board. The `board` field applies only when `from` is a name or a slug.
    - `MutationBoard` gives the board of a mutation: `.named(board field)` for a new node, and `.holding(id)` for an existing node (the key of a full URI).
    - The test "A query on a related repo with no .kanban/ writes nothing" passed before the change, because the existing read path already wrote nothing.
  timestamp: 2026-10-08T05:10:05.364565+00:00
- actor: wballard
  id: 01m4cypdas3yw12vk9m0srwj38
  text: |-
    ### implement — changed
    - evidence: new files CrossRepoWriteTests.swift and CrossRepoFixture.swift; changed Commit.swift, Schema.swift, MutationResolvers.swift, ColumnActorMutations.swift, TaskMutations.swift, TaskOperationMutations.swift, TagMutations.swift, CommentMutations.swift, UndoMutations.swift, RelatedBoards.swift, BoardLock.swift, KanbanGraph.swift, CrossRepoReadTests.swift, EventLogTests.swift. `swift build --build-tests`: no new warnings. Periphery: no unused code. Full `swift test --skip-build` 3 times: 932 tests in 61 suites pass each time (about 7 s each).
    - next: /review
  timestamp: 2026-10-08T05:10:07.449378+00:00
depends_on:
- 01M4B421JA8K0E8GAC3EMWCZ5Z
- 01M4B4002GZV6E43G5CQ74BJNZ
position_column: doing
position_ordinal: '8180'
title: 'Cross-repo writes: board field, enable, multi-board commit'
---
## What
Change related boards in one call. The basis is plan.md §6.6 and §5.4 (multi-board locks). The cross-board cycle check and cross-board undo are in a separate task.
- The optional `board` field on `initBoard`, `updateBoard`, `addTask`, `addColumn`, `addActor`, `addTag`, `renameTag`. A mutation on an existing node finds its board from the node.
- Enable a related repo: the first mutation on a repo with no `.kanban/` initializes its board (auto-init). A query on such a repo writes nothing.
- One call, many boards: one `txn`; each patch records the keys of the other boards in `boards`; locks in key order; the session actor rule in each board; a patch in board A that points to board B holds the full URI of the node with the current key of B.

## Acceptance Criteria
- [x] `addTask(board: "<related>")` writes to the related log; a related repo with no `.kanban/` gets a board on its first mutation.
- [x] One call that changes two boards writes one `txn` to both, and each patch has the key of the other board in `boards`.
- [x] A `dependsOn` edge from board A to board B is stored as a full URI with the key of B; no log line has the key of its own board.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoWriteTests.swift`, with two temporary git repos side by side.
- [x] Run `swift test --filter CrossRepoWriteTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.