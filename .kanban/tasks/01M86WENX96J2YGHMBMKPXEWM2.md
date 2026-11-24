---
comments:
- actor: wballard
  id: 01m870j7dch2vcjykbv6epxpv9
  text: 'Research done. Plan: new file Observe/BoardFolderChanges.swift holds the public enum BoardFolderChange, an internal BoardFolderFeed (the stream, the BoardWatcher on the folder, and the consumer task), and an internal BoardFolderReader (a LiveGraph or no board). The reader keeps only the paths that are a node log (EventLog.ref(ofFileAt:)), the .kanban directory, a node directory, or the watched folder (lost events). Thus a batch with only the lock file changes nothing and reads no file. A batch with a directory compares each file (LiveGraph.changedRefs()), else LiveGraph.changedRefs(among:). Then LiveGraph.apply(changedPaths:) and Graph.changedRefs(since:). The reader calls LiveGraph.takeChanges() after each apply, because the feed does not use the pending changes and they must not grow. KanbanHost keeps a weak list of the feed watchers and stops them in close(). A closed host gives a stream that ends at once. Discovery: BoardStamp.entries(ofBoardAt:) states that the change stream compares the entries, but the card says to use LiveGraph signatures; the LiveGraph signatures give the same file compare, so the feed uses them and does not call the stamp. The feed uses FileStamp(ofItemAt:) of .kanban to tell if the board is there, the same check as BoardStamp.'
  timestamp: 2026-11-24T14:50:08.172496+00:00
- actor: wballard
  id: 01m8711fa150mhdsxht3eyzz12
  text: 'Implementation landed. Added requirement from the FoundationModelsACPAgent consumer (sent by the coordinator): each event gives the folder and the BoardStamp after the change. Thus BoardFolderChange is a public struct with folder: URL, stamp: BoardStamp?, kind: Kind, and Kind is the enum tasksChanged, tasksRemoved, boardChanged, boardRemoved. The reader reads the stamp first, before it reads a log file (the same rule as BoardSnapshot.stamp), and a nil stamp tells that .kanban/ is gone. A new .kanban/ gives boardChanged and tasksChanged with each task id. A full reload (Graph.changedRefs(since:) gives nil) gives boardChanged and each live task as changed. Not verified: whether a caller that drops the stream with no cancel ends the watcher; the doc states only the cancel and the host close as ends.'
  timestamp: 2026-11-24T14:58:27.777054+00:00
- actor: wballard
  id: 01m8711ft77khzs004fm5xbn35
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/Observe/BoardFolderChanges.swift (new), Sources/FoundationModelsKanban/Tool/KanbanHost.swift, Tests/FoundationModelsKanbanTests/Observe/BoardFolderChangesTests.swift (new, 16 tests). swift test --filter BoardFolderChangesTests: 16 passed. Full swift test: 1976 tests in 172 suites passed, 0 warnings.
    - next: /review
  timestamp: 2026-11-24T14:58:28.295892+00:00
- actor: wballard
  id: 01m871gc2afzhyhknas2mvc4vz
  text: |-
    ### test - green
    - found: the first run failed 1 test of 1976. The test waited 60 seconds for boardRemoved in BoardFolderChangesTests (a different one of the remove tests failed on each run).
    - cause: EventLog.isBoardDirectory compared paths with resolvingSymlinksInPath. For a removed path, that call keeps /private for the path of an FSEvents event, and not for the path of the log. So each FSEvents batch of a removed .kanban was dropped as no board path. The test passed only when the first compare batch ran after the remove.
    - fix: EventLog.isBoardDirectory now compares canonicalPath, which gives the same answer before and after a removal.
    - evidence: swift test, 1976 tests in 172 suites passed, 0 failed, 0 skipped. The only warning is the accepted mlx-swift_Cmlx.bundle warning.
    - next: review
  timestamp: 2026-11-24T15:06:35.978254+00:00
- actor: wballard
  id: 01m871gy2m5e01mbytybaa0n5b
  text: |-
    ### commit - changed
    - evidence: local commit of KanbanHost.boardChanges(inFolder:), BoardFolderChange, and the EventLog.isBoardDirectory(at:) canonical path fix
    - next: review
  timestamp: 2026-11-24T15:06:54.420415+00:00
- actor: wballard
  id: 01m871ppa02c22mde09jc3ra7c
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (a10c21f), 0 findings (confirmed 0, refuted 2, attempted 7, failed 0); 4 files reviewed; 2 .kanban files not reviewed (.reviewignore)
    - next: the task is in done. Send the public API names and the commit a10c21f to the FoundationModelsACPAgent session and to the TestudoApp session.
  timestamp: 2026-11-24T15:10:03.072349+00:00
- actor: wballard
  id: 01m871qdzc22j4nzytf4dm87gc
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — Observe/BoardFolderChanges.swift, KanbanHost.boardChanges(inFolder:), 16 tests
    - test: green — swift test, 1976 passed; the test step fixed EventLog.isBoardDirectory(at:) (canonical path)
    - commit: a10c21f
    - review: clean — 0 findings
  timestamp: 2026-11-24T15:10:27.308864+00:00
depends_on:
- 01M86WEGWCS6X5RW20HFKQB54D
position_column: done
position_ordinal: ffd080
title: Add a change stream of the board of a folder that opens no session
---
## Problem
TestudoApp (D214) must follow the board of a folder that has no open session: the tasks that changed, the task ids that went away, and the board that went away. The changes come from a session of this process, from a different process (the `sah` tools), and from iCloud. Brief: `/Users/wballard/github/swissarmyhammer/.briefs/FoundationModelsKanban-spotlight-board-reads-2026-11-24.md`, item 3.

Now the only stream is `KanbanGraph.subscribe(query:variables:operationName:)` with `subscription { changes(board:, filter:, after:) { added changed removed } }` (Sources/FoundationModelsKanban/Tool/KanbanGraph.swift). It gets the writes of other processes through the file watcher of the engine. But:
- It needs a session, with the costs of card "read with no session".
- A removed task file sends no `Change`. `LiveGraph.apply(changedPaths:)` records a `LiveGraphChange` only when the apply added events (`LiveGraph.record(_:)`, Sources/FoundationModelsKanban/Observe/LiveGraph.swift). The test `removedFileUnresolvesEdge` (Tests/FoundationModelsKanbanTests/Observe/LiveGraphApplyTests.swift) expects no new event ids for a removed file.
- No event tells that `.kanban/` went away.

## What
- New file `Sources/FoundationModelsKanban/Observe/BoardFolderChanges.swift`.
- `public enum BoardFolderChange: Hashable, Sendable`:
  - `tasksChanged(Set<String>)`: the ids of the tasks that are new or changed, also when a comment of the task changed.
  - `tasksRemoved(Set<String>)`: the ids of the tasks whose file went away, or that a `deleteTask` made a tombstone.
  - `boardChanged`: a column, tag, actor, or the board node changed. Read the board again.
  - `boardRemoved`: `.kanban/` went away.
- Public entry point: `func boardChanges(inFolder folder: URL) async throws -> AsyncStream<BoardFolderChange>` on `KanbanHost` (Sources/FoundationModelsKanban/Tool/KanbanHost.swift).
- Code to use again:
  - Watch the folder (not `.kanban/`) with `BoardWatcher(watching:in:)` (Sources/FoundationModelsKanban/Observe/BoardWatcher.swift) on the one `folderStreams` of the host. Do not start an FSEvents stream of your own: the system gives few streams (`FolderStreams`, Sources/FoundationModelsKanban/Observe/FolderStreams.swift). Use only the paths in `.kanban/` and the path of `.kanban/` itself.
  - Keep a `LiveGraph` (`LiveGraph.load(using:)`, `apply(changedPaths:)`). Compare the graph before and after each batch with `Graph.changedRefs(since:)` (Sources/FoundationModelsKanban/Model/Graph.swift). When it gives `nil` (a full reload), compare all task refs.
  - Map each changed ref: a task ref gives its id; a comment ref gives the id of its task (`CommentNode.task`); a task that is gone or deleted (`NodeFields.isDeleted`) goes to `tasksRemoved`; a column, tag, actor, or board ref gives `boardChanged`.
  - A batch that holds the watched folder (lost events, `BoardWatcher.compareEachFile()`) compares each file. Call `compareEachFile()` one time after the start, as `BoardEngine` does after its load, so that a change between the load and the start is not lost.
  - When `.kanban/` goes away, send `boardRemoved` and keep the watch. When `.kanban/` comes back, load again and send `tasksChanged` with each task id.
- The stream takes no lock, runs no git, and writes no file. It does not make a `BoardEngine` and does not touch the engines of the host.
- The stream ends when the caller cancels its loop (`onTermination` stops the watcher) and when the host closes (the internal `KanbanHost.close()` of a test host).
- Out of scope: the session subscription also sends no `Change` for a removed task file. Make a separate card for that if a session client needs it.

- Added requirement (from the FoundationModelsACPAgent consumer): each event gives the folder (the URL that the caller gave to `boardChanges(inFolder:)`) and the new `BoardStamp` of the board after the change. For "board gone", the stamp is `nil`. The design: `public struct BoardFolderChange { folder: URL; stamp: BoardStamp?; kind: Kind }`, and `Kind` is the enum `tasksChanged(Set<String>)`, `tasksRemoved(Set<String>)`, `boardChanged`, `boardRemoved`. The doc comment states both points, and that the stream works for a folder with no open session.

## Acceptance Criteria
- [x] A task that a second engine on the same folder adds shows in `tasksChanged` of the stream.
- [x] A delete of a task file gives its id in `tasksRemoved`.
- [x] A `deleteTask` mutation gives the id in `tasksRemoved`. A new comment gives the id of its task in `tasksChanged`.
- [x] A remove of `.kanban/` gives `boardRemoved`. A new `.kanban/` later gives `tasksChanged` with each task id.
- [x] The stream adds no folder to the FSEvents stream other than the watched folder, and makes no engine in the host.
- [x] Each event gives the folder that the caller gave and the stamp of the board after the change; "board gone" has a `nil` stamp.

## Tests (write them first)
New file `Tests/FoundationModelsKanbanTests/Observe/BoardFolderChangesTests.swift`. Use `TemporaryDirectory`, `FolderEventWait` (Tests/FoundationModelsKanbanTests/Observe/FolderEventWait.swift), and the patterns of `SubscriptionTests.appendedLineSendsOneChange` (Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift).
- [x] A task that a second engine on the same folder adds shows in the stream of the first reader. (Brief test. The second engine is a session view with its own host: `KanbanGraphTests.makeGraph(at:)`. It runs `addTask`.)
- [x] A delete of a task file gives the id in the stream (`tasksRemoved`). (Brief test. Use `FileManager.removeItem(at:)` on `EventLog.fileURL(for:)`.)
- [x] A line that a different writer appends to a task file (`BoardWatcherTests.writeLaterTitle(to:mintingFrom:in:)`) gives the id in `tasksChanged`.
- [x] `deleteTask` gives `tasksRemoved`; `addComment` gives `tasksChanged` with the task id; a column rename gives `boardChanged`.
- [x] A remove of `.kanban/` gives `boardRemoved`.
- [x] A cancel of the loop stops the watcher (`BoardWatcher.isRunning` is `false`).
- [x] The stamp of an event equals `KanbanHost.boardStamp(ofFolder:)` right after the change. The folder of an event is the folder that the caller gave. The `boardRemoved` event has no stamp.
- [x] A lock file alone gives no change.
- [x] `swift test` passes. Run the headless root `swift test` one time only.

## Workflow
- Use `/tdd`: write the failing tests first, then make them pass.
- Run `/double-check` before review.

## Note
This work is for TestudoApp D214. When it is done, send the public API names and the commit to the FoundationModelsACPAgent session and to the TestudoApp session. #testudo