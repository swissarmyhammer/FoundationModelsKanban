---
comments:
- actor: wballard
  id: 01m8722n5gd174sxrjjcj64h7m
  text: 'Research: The stream feed (BoardFolderFeed / BoardFolderReader in Observe/BoardFolderChanges.swift) watches the folder that holds .kanban/, not .kanban/ itself. Thus its first compare batch (compareEachFile) holds the watched folder, and EventLog.holdsBoardDirectory does not see it. The stream must map the watched folder to log.directory for the conflict check. EventLog.resolveConflicts already takes the board lock only when a file has a conflict version, so a board with no conflict gets no lock and no write. BoardEngine does its second check (the files that the apply read again) after the apply; the stream can do it before the stamp read, because LiveGraph.changedRefs() only compares file signatures and does not apply. Then the merge always comes before the stamp read, and the event of the merged result holds the stamp after the merge. FileVersionSource must become Sendable to go in HostConfiguration (Sendable). FakeFileVersionSource is a final class with a let and a Mutex, so it can be Sendable.'
  timestamp: 2026-11-24T15:16:35.120358+00:00
- actor: wballard
  id: 01m872gb90ypjak4tmvjp6jshf
  text: 'Implementation landed. BoardFolderReader.changes(after:) now calls resolveConflicts(amongBoardPaths:) before it reads the stamp. The watched folder stands for the board directory, so the first compare after the start checks each file one time (checkedEachFileForConflicts). While no board is in memory, a batch that holds the board checks each file, so that a new .kanban/ folder gets its check before its load. After the first check, a batch that holds the board checks the files that LiveGraph.changedRefs() finds changed (a compare of signatures only, before the apply). Difference from the card text: the card says that the write of the merge gives a new batch and that batch gives the changes. Here the merge comes before the stamp read and the apply of the SAME batch, so that batch gives tasksChanged with the stamp after the merge (the order request of the caller). The write still gives a later FSEvents batch, but its compare finds no change, so no second event comes. BoardEngine now takes the store from HostConfiguration.fileVersions (no ICloudFileVersions() in the engine). FileVersionSource is now Sendable; FakeFileVersionSource is Sendable. RED: the 5 merge tests failed at the time limit (no change came); the no-lock test passed before the change, because the old stream never locked: it is a guard against a lock from the new code. Mistake: I ran the filtered BoardFolderChangesTests two times with no code change between the runs.'
  timestamp: 2026-11-24T15:24:03.744838+00:00
- actor: wballard
  id: 01m872gbn3n2tbf5r2bskvz4n3
  text: |-
    ### implement — changed
    - evidence: swift test: 1982 tests in 172 suites passed (one full run); --filter BoardFolderChangesTests: 22 passed (6 new). Files: Sources/FoundationModelsKanban/Observe/BoardFolderChanges.swift, Sources/FoundationModelsKanban/Tool/KanbanHost.swift, Sources/FoundationModelsKanban/Tool/BoardEngine.swift, Sources/FoundationModelsKanban/Events/LogVersionMerge.swift, Tests/FoundationModelsKanbanTests/Observe/BoardFolderChangesTests.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanHostTests.swift, Tests/FoundationModelsKanbanTests/Events/LogVersionMergeTests.swift
    - next: /review. No commit yet. After the commit, send the API names and the commit to the FoundationModelsACPAgent session and the TestudoApp session (Note of the card).
  timestamp: 2026-11-24T15:24:04.131448+00:00
- actor: wballard
  id: 01m872kc4k519rfsrjq04dpxc9
  text: |-
    ### test - green
    - evidence: swift test at package root, one run: 1982 tests in 172 suites passed, 0 failed, 0 skipped. Only build warning: the accepted mlx-swift_Cmlx.bundle warning. No windowed or UI tests ran.
    - next: review
  timestamp: 2026-11-24T15:25:42.931514+00:00
- actor: wballard
  id: 01m872kw67ehqsf0gj163hzpfv
  text: |-
    ### commit — changed
    - evidence: the commit holds the folder stream change, its tests, and the kanban task files
    - next: review
  timestamp: 2026-11-24T15:25:59.367714+00:00
depends_on:
- 01M86WENX96J2YGHMBMKPXEWM2
position_column: doing
position_ordinal: '80'
title: Merge the iCloud conflict versions in the change stream of a folder
---
## Problem
A board in iCloud Drive can get conflict versions of a log file when two Macs write the same log (TestudoApp D179). The brief (`/Users/wballard/github/swissarmyhammer/.briefs/FoundationModelsKanban-spotlight-board-reads-2026-11-24.md`, item 3) says: a merge of iCloud conflict versions gives the changes of its result in the change stream.

Now only a `BoardEngine` merges the conflict versions: `BoardEngine.receive(_:)` calls `EventLog.resolveConflicts(ofFilesAt:scanningBoardDirectory:with:)` (Sources/FoundationModelsKanban/Events/LogVersionMerge.swift) with `ICloudFileVersions()` before each apply (Sources/FoundationModelsKanban/Tool/BoardEngine.swift). For a folder with no session, no engine runs. Thus the conflict stays, and the stream of card "change stream of a folder" shows only the current version.

## What
- In `Sources/FoundationModelsKanban/Observe/BoardFolderChanges.swift`, before each apply of a batch, call `EventLog.resolveConflicts(ofFilesAt:scanningBoardDirectory:with:)`. Use the same rule as `BoardEngine.receive(_:)`: the first batch that holds the board directory checks each file one time; after that, check only the files that the apply read again (`checkedEachFileForConflicts`).
- The merge writes the merged log under the board lock. The write gives a new batch, and that batch gives the changes of the merged result in `tasksChanged`. This is the only write of the stream. Document it in the doc comment of `KanbanHost.boardChanges(inFolder:)`.
- Make the version source injectable for tests: add a `fileVersions` value (`any FileVersionSource`, default `ICloudFileVersions()`) to `HostConfiguration` (Sources/FoundationModelsKanban/Tool/KanbanHost.swift). Use it in the stream. Also use it in `BoardEngine.resolveConflicts(in:scanningBoardDirectory:)`, so that both paths use one source.
- A merge that fails is logged with `Log.kanban.error`, the same as in `BoardEngine`, and the next batch tries again.

## Acceptance Criteria
- [x] A task log with a conflict version that holds a new title gives the task id in `tasksChanged`, and a later `readBoard(inFolder:)` shows the merged title.
- [x] The conflict versions are marked resolved (`FileVersionSource.markResolved(_:of:)` gets the call).
- [x] A board with no conflict takes no lock (no `.lock` file is made by the stream).
- [x] `BoardEngine` uses the same injected source, and its tests still pass.

## Tests (write them first)
Add to `Tests/FoundationModelsKanbanTests/Observe/BoardFolderChangesTests.swift`. Use `FakeFileVersionSource` (Tests/FoundationModelsKanbanTests/Events/LogVersionMergeTests.swift) through the new `HostConfiguration` value.
- [x] A conflict version of a task log that adds a title line gives the task id in the stream, and the merged log holds the lines of both versions.
- [x] The fake source records that the versions are resolved.
- [x] A board with no conflict version makes no `.lock` file.
- [x] `swift test` passes. Run the headless root `swift test` one time only.

## Workflow
- Use `/tdd`: write the failing tests first, then make them pass.
- Run `/double-check` before review.

## Note
This work is for TestudoApp D214 (and D179). When it is done, send the public API names and the commit to the FoundationModelsACPAgent session and to the TestudoApp session. #testudo