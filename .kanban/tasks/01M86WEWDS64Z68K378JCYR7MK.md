---
depends_on:
- 01M86WENX96J2YGHMBMKPXEWM2
position_column: todo
position_ordinal: '8380'
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
- [ ] A task log with a conflict version that holds a new title gives the task id in `tasksChanged`, and a later `readBoard(inFolder:)` shows the merged title.
- [ ] The conflict versions are marked resolved (`FileVersionSource.markResolved(_:of:)` gets the call).
- [ ] A board with no conflict takes no lock (no `.lock` file is made by the stream).
- [ ] `BoardEngine` uses the same injected source, and its tests still pass.

## Tests (write them first)
Add to `Tests/FoundationModelsKanbanTests/Observe/BoardFolderChangesTests.swift`. Use `FakeFileVersionSource` (Tests/FoundationModelsKanbanTests/Events/LogVersionMergeTests.swift) through the new `HostConfiguration` value.
- [ ] A conflict version of a task log that adds a title line gives the task id in the stream, and the merged log holds the lines of both versions.
- [ ] The fake source records that the versions are resolved.
- [ ] A board with no conflict version makes no `.lock` file.
- [ ] `swift test` passes. Run the headless root `swift test` one time only.

## Workflow
- Use `/tdd`: write the failing tests first, then make them pass.
- Run `/double-check` before review.

## Note
This work is for TestudoApp D214 (and D179). When it is done, send the public API names and the commit to the FoundationModelsACPAgent session and to the TestudoApp session. #testudo