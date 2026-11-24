---
depends_on:
- 01M86WEGWCS6X5RW20HFKQB54D
position_column: todo
position_ordinal: '8280'
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

## Acceptance Criteria
- [ ] A task that a second engine on the same folder adds shows in `tasksChanged` of the stream.
- [ ] A delete of a task file gives its id in `tasksRemoved`.
- [ ] A `deleteTask` mutation gives the id in `tasksRemoved`. A new comment gives the id of its task in `tasksChanged`.
- [ ] A remove of `.kanban/` gives `boardRemoved`. A new `.kanban/` later gives `tasksChanged` with each task id.
- [ ] The stream adds no folder to the FSEvents stream other than the watched folder, and makes no engine in the host.

## Tests (write them first)
New file `Tests/FoundationModelsKanbanTests/Observe/BoardFolderChangesTests.swift`. Use `TemporaryDirectory`, `FolderEventWait` (Tests/FoundationModelsKanbanTests/Observe/FolderEventWait.swift), and the patterns of `SubscriptionTests.appendedLineSendsOneChange` (Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift).
- [ ] A task that a second engine on the same folder adds shows in the stream of the first reader. (Brief test. The second engine is a session view with its own host: `KanbanGraphTests.makeGraph(at:)`. It runs `addTask`.)
- [ ] A delete of a task file gives the id in the stream (`tasksRemoved`). (Brief test. Use `FileManager.removeItem(at:)` on `EventLog.fileURL(for:)`.)
- [ ] A line that a different writer appends to a task file (`BoardWatcherTests.writeLaterTitle(to:mintingFrom:in:)`) gives the id in `tasksChanged`.
- [ ] `deleteTask` gives `tasksRemoved`; `addComment` gives `tasksChanged` with the task id; a column rename gives `boardChanged`.
- [ ] A remove of `.kanban/` gives `boardRemoved`.
- [ ] A cancel of the loop stops the watcher (`BoardWatcher.isRunning` is `false`).
- [ ] `swift test` passes. Run the headless root `swift test` one time only.

## Workflow
- Use `/tdd`: write the failing tests first, then make them pass.
- Run `/double-check` before review.

## Note
This work is for TestudoApp D214. When it is done, send the public API names and the commit to the FoundationModelsACPAgent session and to the TestudoApp session. #testudo