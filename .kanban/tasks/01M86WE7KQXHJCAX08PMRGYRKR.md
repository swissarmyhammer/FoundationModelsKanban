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
- actor: wballard
  id: 01m86y6awwwyb7d7wdkxjxgypp
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (d13f2ec); 6 findings — Sources/FoundationModelsKanban/GraphQL/Schema.swift:128, Sources/FoundationModelsKanban/Observe/ChangeRound.swift:162 (2), Sources/FoundationModelsKanban/Tool/Commit.swift:1023, Sources/FoundationModelsKanban/Tool/Commit.swift:1024, Sources/FoundationModelsKanban/Tool/KanbanHost.swift:186
    - next: implement the open items of the Review Findings (2026-11-24 08:03) section; the task stays in review
  timestamp: 2026-11-24T14:08:41.372908+00:00
- actor: wballard
  id: 01m86y7hd875s9zwawm06p44tj
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — Snapshot/BoardSnapshot.swift, KanbanHost.readBoard(inFolder:), KeyedBoard rename in 9 files
    - test: green — swift test, 1949 passed
    - commit: d13f2ec
    - review: findings — GraphQL/Schema.swift:128, Observe/ChangeRound.swift:162 (2), Tool/Commit.swift:1023, Tool/Commit.swift:1024, Tool/KanbanHost.swift:186
  timestamp: 2026-11-24T14:09:20.808540+00:00
- actor: wballard
  id: 01m86yj6rqb1a9r5qaep6xrexq
  text: |-
    Fixes of the 6 findings of Review Findings (2026-11-24 08:03). No behavior changed.
    - KeyedBoard construction: new CommitSession.snapshot(with:) (Tool/Commit.swift) makes the board from the key and the source of the session and a graph. CommitSession.snapshot, RelatedWork.snapshot and ChangeRound (5 calls) use it. The static ChangeRound.snapshot(of:graph:) is deleted.
    - GraphQL/Schema.swift: new private BoardStore.snapshot(of: MutationTarget) holds the only KeyedBoard construction of the file. The current board uses the key and source of the store (the store has no session); a related board uses session.snapshot(with:). BoardStore.snapshot and view(of:) call it. Thus the two copies of the file (snapshot and the related case of view(of:)) are now one.
    - Tool/KanbanHost.swift: new private nonisolated(nonsending) static mappingCallFailure(_:) holds the KanbanError(callFailure:) ?? error mapping. session(workingDirectory:actor:) and readBoard(inFolder:) use it. nonisolated(nonsending) lets the actor-isolated session call pass its closure with no sending check.
    - Not changed: GraphQL/CollectBoardsField.swift also has the same error mapping and GraphQL/CheckLinksField.swift and CollectBoardsField.swift make a KeyedBoard from a BoardView or a merged graph. These files are not in the findings and were not changed.
  timestamp: 2026-11-24T14:15:10.359748+00:00
- actor: wballard
  id: 01m86yjcm1g7s7tn6qh96ezwpf
  text: |-
    ### implement — changed
    - evidence: swift test (root, headless): 1949 tests in 170 suites passed, 0 failures; the only warning is the accepted mlx-swift_Cmlx.bundle one. swift test --filter (BoardSnapshotTests, ChangeRound, RelatedBoard, KanbanHost): 58 tests passed. Files: Sources/FoundationModelsKanban/Tool/Commit.swift, Sources/FoundationModelsKanban/Observe/ChangeRound.swift, Sources/FoundationModelsKanban/GraphQL/Schema.swift, Sources/FoundationModelsKanban/Tool/KanbanHost.swift. All 6 findings of Review Findings (2026-11-24 08:03) are checked.
    - next: /review. Not committed.
  timestamp: 2026-11-24T14:15:16.353583+00:00
- actor: wballard
  id: 01m86ym84pqt3an5tz36pm3qaq
  text: |-
    ### test - green
    - evidence: swift test at package root - 1949 tests in 170 suites passed, 0 failures, 0 skipped; only the accepted mlx-swift_Cmlx.bundle warning
    - next: review
  timestamp: 2026-11-24T14:16:17.302284+00:00
- actor: wballard
  id: 01m86ymrx3c5zrrt4fct9ta087
  text: |-
    ### commit — changed
    - evidence: one local commit holds the source changes, the review findings and the .kanban task files
    - next: none. The commit is local. Do not push.
  timestamp: 2026-11-24T14:16:34.467701+00:00
- actor: wballard
  id: 01m86yt63251qsaevav1qc9r3g
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (d13f2ec..7c6783f), 4 files reviewed, 2 .kanban/ files ignored. counts: findings 1, confirmed 1, refuted 5. Sources/FoundationModelsKanban/GraphQL/Schema.swift:518 duplication/duplication. All 6 items of the 2026-11-24 08:03 section are checked.
    - next: implement the unchecked item of the 2026-11-24 08:17 section (one KeyedBoard construction also for the .current case of BoardStore), then commit and review again.
  timestamp: 2026-11-24T14:19:31.810335+00:00
- actor: wballard
  id: 01m86ytt4vh8ky2s2a6vb61ycp
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 4 files (CommitSession.snapshot(with:), BoardStore.snapshot(of:), mappingCallFailure(_:)); 6 prior findings checked
    - test: green — swift test, 1949 passed
    - commit: 7c6783f
    - review: findings — GraphQL/Schema.swift:518
  timestamp: 2026-11-24T14:19:52.347966+00:00
- actor: wballard
  id: 01m86z4s8byrdp689jsqperc1d
  text: |-
    Fix of the finding of Review Findings (2026-11-24 08:17). No behavior changed.
    - KeyedBoard (CrossRepo/RelatedBoards.swift) has a new static make(key:graph:source:). The init is now private, so the compiler makes sure that each site uses make. Thus the construction of a board is written one time.
    - The 4 sites of the module call KeyedBoard.make: CommitSession.snapshot(with:) (Tool/Commit.swift), the .current case of BoardStore.snapshot(of:) (GraphQL/Schema.swift), the link check of a read view (GraphQL/CheckLinksField.swift), and the merged board of collectBoards (GraphQL/CollectBoardsField.swift).
    - The arguments are different at each site (the key and source of a session, of the store, or of a view; collectBoards gives no source). These are data of each case, not copied logic.
    - Note: a full swift test run with a grep pipe lost the summary line, because the output was not saved. The second run saved the log to a file.
  timestamp: 2026-11-24T14:25:19.115987+00:00
- actor: wballard
  id: 01m86z4smfhbt3sfkw6h1nrcj4
  text: |-
    ### implement — changed
    - evidence: swift test (root, headless): 1949 tests in 170 suites passed, 0 failures; the only warning is the accepted mlx-swift_Cmlx.bundle one. swift test --filter CheckLinks|CollectBoards|RelatedBoard: 50 tests in 9 suites passed. Files: Sources/FoundationModelsKanban/CrossRepo/RelatedBoards.swift, Sources/FoundationModelsKanban/Tool/Commit.swift, Sources/FoundationModelsKanban/GraphQL/Schema.swift, Sources/FoundationModelsKanban/GraphQL/CheckLinksField.swift, Sources/FoundationModelsKanban/GraphQL/CollectBoardsField.swift. The finding of Review Findings (2026-11-24 08:17) is checked.
    - next: /review. Not committed.
  timestamp: 2026-11-24T14:25:19.503825+00:00
- actor: wballard
  id: 01m86z78bz6qywdfnep850gqg7
  text: |-
    ### test — green
    - evidence: swift test at the package root, one run: 1949 tests in 170 suites passed, 0 failed, 0 skipped. Only warning: the accepted mlx-swift_Cmlx.bundle warning.
    - next: review
  timestamp: 2026-11-24T14:26:40.127958+00:00
- actor: wballard
  id: 01m86z7q0xbkrn1mfq720gxgsn
  text: |-
    ### commit — changed
    - evidence: one commit holds the KeyedBoard.make change and the kanban task files
    - next: review
  timestamp: 2026-11-24T14:26:55.133673+00:00
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

## Review Findings (2026-11-24 08:03)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 12 file(s) reviewed, 12 not reviewed.

> 12 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 12 file(s)

- [x] `Sources/FoundationModelsKanban/GraphQL/Schema.swift:128` `reuse/reuse` — The new BoardStore.snapshot property repeats the KeyedBoard construction that CommitSession.snapshot and RelatedWork.snapshot already do. Three near-identical copies now exist for one pattern. Add one shared initializer or helper that makes a KeyedBoard from a board key, a graph, and a source. Use it in all three properties, and in ChangeRound, so the construction is written once.
- [x] `Sources/FoundationModelsKanban/Observe/ChangeRound.swift:162` `duplication/duplication` — The static `snapshot(of:graph:)` builds `KeyedBoard(key: session.key.description, graph: graph, source: session.source)`. The same construction is written in RelatedWork (Commit.swift:1024) and in CommitSession (Commit.swift:527) with different arguments. Three places must be kept in step. Make `ChangeRound.snapshot(of:graph:)` call the shared `KeyedBoard` initializer, or delete it and call that initializer directly from the `place` and `view` helpers. Then remove the copies that repeat the same construction.
- [x] `Sources/FoundationModelsKanban/Observe/ChangeRound.swift:162` `reuse/reuse` — The new static snapshot(of:graph:) builds a KeyedBoard from a CommitSession's key and source. This is the same construction that CommitSession.snapshot already does, with the graph as the only difference. The logic is copied instead of extended. Add a CommitSession method that takes a graph, for example func snapshot(graph: Graph) -> KeyedBoard, and have CommitSession.snapshot call it with displayGraph. Then ChangeRound calls session.snapshot(graph:) and the copy is removed.
- [x] `Sources/FoundationModelsKanban/Tool/Commit.swift:1023` `reuse/reuse` — The new RelatedWork.snapshot property repeats the KeyedBoard construction that CommitSession.snapshot already does. The only difference is the source of the graph and the key. The logic is copied instead of shared. Add a shared helper that makes a KeyedBoard from a session and a graph. Call it from RelatedWork.snapshot, CommitSession.snapshot, and the other copies, passing the graph that each one uses.
- [x] `Sources/FoundationModelsKanban/Tool/Commit.swift:1024` `duplication/duplication` — The `snapshot` property of `RelatedWork` builds `KeyedBoard(key: session.key.description, graph: work.graph, source: session.source)`. This is the same constructor call as the `snapshot` copies in ChangeRound.swift:162 and Commit.swift:527. It differs only in its arguments. Call the shared `KeyedBoard` initializer that takes the session and a graph, with `work.graph` as the graph argument. Delete the inline construction.
- [x] `Sources/FoundationModelsKanban/Tool/KanbanHost.swift:186` `reuse/reuse` — The new readBoard catch block maps errors with KanbanError(callFailure: error) ?? error. The same mapping is already written in session(workingDirectory:actor:). The copy repeats the error-mapping logic instead of sharing one helper. Move the mapping into one private helper, for example a func mapped<T>(_ body: () async throws(EventLogError) -> T) async throws -> T that applies the KanbanError(callFailure:) rule. Use it in readBoard and session(workingDirectory:actor:).

## Review Findings (2026-11-24 08:17)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Sources/FoundationModelsKanban/GraphQL/Schema.swift:518` `duplication/duplication` — The `.current` case builds a `KeyedBoard(key:graph:source:)` inline. That is the same construction that the new `CommitSession.snapshot(with:)` now owns. The commit states that it makes one KeyedBoard construction, but this site still builds the value by hand, so a change to the construction must be made in two places. Add a `BoardStore`-level helper, or pass the key in explicitly, so that both sites call one function that wraps `KeyedBoard(key:graph:source:)`. Alternatively, document why the store's current board is not a CommitSession, and keep the single construction in one helper.