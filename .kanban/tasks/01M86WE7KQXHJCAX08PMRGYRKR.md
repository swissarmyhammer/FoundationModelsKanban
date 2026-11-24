---
comments:
- actor: wballard
  id: 01m86x5rgbct4p69rt30s3tnf6
  text: |-
    Research and implementation notes.
    - Name clash: the module had an internal struct BoardSnapshot (CrossRepo/RelatedBoards.swift: the key, graph and source of a loaded board). The card names the new public type BoardSnapshot, so the internal type is now KeyedBoard. This is a rename only, in 9 source files. No behavior changed.
    - The read uses BoardWatcher.existingBoardDirectory(ofBoardAt:), EventLog.checkCompatibility(), BoardLoader.join() (no merge of the event lists, because the snapshot needs only the graph), and Readiness for the board order, the display column, the done mark and the dependencies (edges and body markers). Tags come from Graph.tagSlots(of:) (edges and #markers), comments from Graph.comments(ofTaskAt:), the comment author from Graph.author(ofCommentAt:). These are the same calls that the GraphQL resolvers use.
    - The board key for the body dependency markers comes from the board log (BoardNode.gitKey, else the lowest board ID). The read runs no git.
    - A Rust board throws KanbanError.incompatibleBoard, through KanbanError(callFailure:), the same as session(workingDirectory:actor:).
    - Extra public type: BoardSnapshot.Actor { id, name } for the assignees and the comment author. Comment.author is optional, because a merged graph can have no actor for the edge. Task.column is optional, because a board with no live column gives no display column.
    - Dates are Foundation Date (from DateTime.date), so a consumer does not need to import FoundationModelsExtras.
  timestamp: 2026-11-24T13:50:53.963375+00:00
- actor: wballard
  id: 01m86xp2049n4d6pm6x3196f2s
  text: |-
    Double-check (verifier agent) gave REVISE with 7 findings. All 7 are done:
    1. taskID(at:in:) gave the local id of a ref that the board does not have. It now gives nil, the same as GraphQL Task.dependsOn. Test: danglingDependencyIsLeftOut (it failed first).
    2, 3, 4. The doc comments of Task.dependsOn, Task.assignees and KanbanHost.readBoard(inFolder:) now state the limits: no related board is loaded (a dependency on another board gives URI text, even when that task is deleted; an assignee of another board is left out), and the marker key is the key that the board log recorded at the last write.
    5. A regular file with the name .kanban gave an I/O error. It now gives .noBoard. Test: kanbanFileGivesNoBoard (it failed first).
    6. New tests: bodyMarkersGiveQueryValues (#tag and dependency markers, compared with the GraphQL query), deletedCommentIsLeftOut, deletedColumnIsLeftOut, crossBoardDependencyGivesURI, danglingDependencyIsLeftOut.
    7. sessionBoardGivesQueryValues now requires the expected values (tag, assignee, comment, done mark, column, dependency, updated after created) before the comparison.
    Note: the sah CLI 'task update --description' hung with no CPU until stdin was closed (< /dev/null).
  timestamp: 2026-11-24T13:59:47.972165+00:00
- actor: wballard
  id: 01m86xp2p997b247vw7g73b45t
  text: |-
    ### implement — changed
    - evidence: swift test (root, headless): 1949 tests in 170 suites passed, 0 failures, 0 warnings. swift test --filter BoardSnapshotTests: 16 tests passed. Files: Sources/FoundationModelsKanban/Snapshot/BoardSnapshot.swift (new), Sources/FoundationModelsKanban/Tool/KanbanHost.swift (readBoard(inFolder:)), Tests/FoundationModelsKanbanTests/Snapshot/BoardSnapshotTests.swift (new), and the rename of the internal BoardSnapshot to KeyedBoard in CrossRepo/RelatedBoards.swift, CrossRepo/LinkCheck.swift, CrossRepo/OldBoardName.swift, Derived/Readiness.swift, Observe/ChangeRound.swift, GraphQL/CheckLinksField.swift, GraphQL/CollectBoardsField.swift, GraphQL/Schema.swift, Tool/Commit.swift.
    - public API: KanbanHost.readBoard(inFolder:) async throws -> BoardRead; enum BoardRead { noBoard, board(BoardSnapshot) }; BoardSnapshot { columns, tasks }; BoardSnapshot.Column { id, name, order }; BoardSnapshot.Task { id, shortID, title, description, column, tags, assignees, dependsOn, comments, created, updated, isDone }; BoardSnapshot.Comment { id, author, text, created }; BoardSnapshot.Actor { id, name }.
    - next: /review. Not committed. After the commit, send the API names and the commit to the FoundationModelsACPAgent and TestudoApp sessions (card note).
  timestamp: 2026-11-24T13:59:48.681106+00:00
- actor: wballard
  id: 01m86xtcmq6earh0jr8fwpn942
  text: |-
    ### test — green
    - evidence: swift test — 1949 tests in 170 suites passed, 0 failed, 0 skipped. The only warning is the accepted mlx-swift_Cmlx.bundle one.
    - next: review
  timestamp: 2026-11-24T14:02:09.943247+00:00
- actor: wballard
  id: 01m86xv85eqm2qmyvae1yc395d
  text: |-
    ### commit - changed
    - evidence: commit feat(snapshot): ^mrgyrkr read the board of a folder with no session
    - next: review
  timestamp: 2026-11-24T14:02:38.126558+00:00
position_column: doing
position_ordinal: '80'
title: Add a read of the board of a folder that opens no session
---
## Problem
TestudoApp (D214) gives each task of each known folder to Spotlight. For this, the agent must read the board of a folder that has no open session. Brief: `/Users/wballard/github/swissarmyhammer/.briefs/FoundationModelsKanban-spotlight-board-reads-2026-11-24.md`, item 1.

Now the only read is a session: `KanbanHost.session(workingDirectory:actor:)` (Sources/FoundationModelsKanban/Tool/KanbanHost.swift) and then `KanbanGraph.execute(query:variables:operationName:)` (Sources/FoundationModelsKanban/Tool/KanbanGraph.swift). The GraphQL `Board` and `Task` types have all the fields. But a session is not correct for this use:
- It keeps a `BoardEngine` in memory until the process ends, with an FSEvents watcher, a search index, and embeddings.
- In a git repo with no commit, the key read makes an empty first commit. Thus the read writes.
- A folder with no `.kanban/` gives an empty board. The brief wants "no board".
- `Board.tasks` pages (`first: 10`). A full read needs many pages.

## What
Add a public read that opens no session, takes no lock, runs no git, and writes no file.

- New file `Sources/FoundationModelsKanban/Snapshot/BoardSnapshot.swift`. Public value types, all `Sendable`, `Hashable`, `Codable`:
  - `BoardSnapshot` { `columns: [BoardSnapshot.Column]`, `tasks: [BoardSnapshot.Task]` }.
  - `BoardSnapshot.Column` { `id` (slug), `name`, `order` }, in board order (`ColumnOrder`, Sources/FoundationModelsKanban/Derived/ColumnOrder.swift).
  - `BoardSnapshot.Task` { `id` (ULID text), `shortID`, `title`, `description` (the body), `column` (column id; use `ColumnOrder.displaySlot(of:)`), `tags` (tag names), `assignees` (actor id and name), `dependsOn` (task ids; a ref to a different board gives its URI text), `comments: [BoardSnapshot.Comment]`, `created`, `updated`, `isDone` (`ColumnOrder.isTerminal(_:)`) }.
  - `BoardSnapshot.Comment` { `id`, `author` (actor id and name), `text` (the body), `created` }, in time order.
  - `public enum BoardRead { case noBoard, board(BoardSnapshot) }`.
- Public entry point on the host: `nonisolated func readBoard(inFolder folder: URL) async throws -> BoardRead` on `KanbanHost` (Sources/FoundationModelsKanban/Tool/KanbanHost.swift). The folder is the folder that holds `.kanban/`. The read does not go up the folders and does not ask git for the worktree top.
- Code to use again:
  - `BoardWatcher.existingBoardDirectory(ofBoardAt:)` (Sources/FoundationModelsKanban/Tool/BoardEngine.swift) to find `.kanban/`. No directory gives `.noBoard`.
  - `EventLog(repositoryAt:)` and `EventLog.checkCompatibility()` (Sources/FoundationModelsKanban/Events/IncompatibleBoard.swift): an old Rust board throws the same error as a session.
  - `BoardLoader(reading:).load()` (Sources/FoundationModelsKanban/Events/Loader.swift). It drops a torn last line, and it holds a transaction that is not complete in all its files (divergence.md Q23). Thus the read is safe while a session writes.
  - `Graph.node(at:as:)` (Sources/FoundationModelsKanban/Model/Graph.swift), `ShortID` (Sources/FoundationModelsKanban/Identity/ShortID.swift).
- Leave out each deleted task, deleted column, and deleted comment (`NodeFields.isDeleted`).

## Acceptance Criteria
- [x] `KanbanHost.shared.readBoard(inFolder:)` gives `.noBoard` for a folder with no `.kanban/`, and does not throw.
- [x] For a board with columns, tasks, tags, assignees, dependencies, and comments, the snapshot holds each field of the brief with the correct values.
- [x] The read makes no file, no `.lock`, and no git commit, and it starts no FSEvents stream and no engine in the host.
- [x] A torn last line and a transaction that is not complete do not show in the snapshot, and the read does not throw.

## Tests (write them first)
New file `Tests/FoundationModelsKanbanTests/Snapshot/BoardSnapshotTests.swift`. Use `TemporaryDirectory` (Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift) and the fixture writers of `KanbanGraphTests` and `LoaderTests`.
- [x] A folder with no `.kanban/` folder gives "no board" (`.noBoard`), not an error. (Brief test.)
- [x] A board written through a session (`KanbanGraphTests.makeGraph(at:)` and `addTask`, `addComment`, `moveTask` mutations) gives a snapshot with the same columns, ids, titles, descriptions, tags, assignees, dependsOn ids, comments (author, text, date), created and updated dates, and done mark as the GraphQL query of the session.
- [x] A deleted task is not in the snapshot.
- [x] The read writes nothing: the list of all paths and their modification dates under the folder (also `.git`) is the same before and after. In a git repo with no commit, the repo still has no commit after the read.
- [x] A task log with a torn last line gives the state before that line.
- [x] `swift test` passes. Run the headless root `swift test` one time only.

## Workflow
- Use `/tdd`: write the failing tests first, then make them pass.
- Run `/double-check` before review.

## Note
This work is for TestudoApp D214. When it is done, send the public API names and the commit to the FoundationModelsACPAgent session and to the TestudoApp session. #testudo