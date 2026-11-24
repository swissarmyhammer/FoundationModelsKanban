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
- actor: wballard
  id: 01m872tg1mq2cf3886f762q7b1
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (a669b19), 4 findings (4 confirmed, 0 refuted) — Sources/FoundationModelsKanban/Observe/BoardFolderChanges.swift:272, Sources/FoundationModelsKanban/Observe/BoardFolderChanges.swift:279, Tests/FoundationModelsKanbanTests/Observe/BoardFolderChangesTests.swift:344, Tests/FoundationModelsKanbanTests/Tool/KanbanHostTests.swift:584
    - next: implement the 4 open items of the Review Findings (2026-11-24 09:26) section; the task stays in review
  timestamp: 2026-11-24T15:29:36.308841+00:00
- actor: wballard
  id: 01m872v3bepyd27ras9mv8z4yy
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 7 files (4 Sources, 3 Tests), 6 new tests
    - test: green — swift test, 1982 passed
    - commit: a669b19
    - review: findings — Observe/BoardFolderChanges.swift:272, Observe/BoardFolderChanges.swift:279, BoardFolderChangesTests.swift:344, KanbanHostTests.swift:584
  timestamp: 2026-11-24T15:29:56.078736+00:00
- actor: wballard
  id: 01m8739gwghepxp3yd09ath1rj
  text: 'Findings of 2026-11-24 09:26 fixed. (1, 2) New shared step: EventLog.resolveConflicts(ofFilesAt:addingFiles:scanningBoardDirectory:with:recordingFailureAs:metadata:) in Events/LogVersionMerge.swift. It calls the throwing resolveConflicts, catches the error, and writes one Log.kanban.error with the paths and the error. BoardEngine.resolveConflicts(in:scanningBoardDirectory:) and BoardFolderReader.resolveConflicts(in:scanningBoardDirectory:addingChangedFiles:) now only call it with their own message (the reader also gives the folder metadata). The changed-files addition of the reader goes in as the addingFiles closure, so that an error of changedFiles() is still a failure of the check and the record still holds only the batch paths (no change of the log text). The BoardEngine call site changed in this task, as the orchestrator ordered; the "separate task" text of finding 2 was not followed. 3 new tests in LogVersionMergeTests. (3) runMerge now waits for the first tasksChanged of any ids and uses #require, so a stream that ends first fails the test; MergeRun.change is not optional. conflictVersionGivesTaskID asserts kind == .tasksChanged([taskID]). Other tests of the file: waitsForChange/waitsForRemoval/waits(for:) match the kind and the id in the predicate, and lockFileGivesNoChange asserts first?.kind, so they already assert the contents. (4) HostFixture.makeHost defaults readingVersionsWith to FakeFileVersionSource(conflicts: [:]). makeGitHost goes through makeHost, so it gets the fake; no git test injects versions, so no new parameter. Same cause in KanbanGraphTests.makeGraph: it goes through KanbanGraph.init(root:...), which made a HostConfiguration with ICloudFileVersions(). That init got a readingVersionsWith parameter (default ICloudFileVersions(), no behavior change), and makeGraph gives the fake by default. Not changed: ReadmeExamplesTests uses KanbanHost.shared on purpose (it runs the README code, which has no injection point); BoardSnapshotTests use KanbanHost.shared only for readBoard(inFolder:), which does not read the version store. Mistake: a first description update read a stale desc.md from the scratchpad, because a python step failed; the description was restored from the saved copy at once, and the only difference from the original is the 4 checked boxes.'
  timestamp: 2026-11-24T15:37:48.688292+00:00
- actor: wballard
  id: 01m8739h741jnzyggvmfs7j47m
  text: |-
    ### implement — changed
    - evidence: swift test (one full run): 1985 tests in 172 suites passed, 0 failed; only the accepted mlx-swift_Cmlx.bundle warning. --filter LogVersionMergeTests|BoardFolderChangesTests|KanbanHostTests: 62 passed (3 new). Files: Sources/FoundationModelsKanban/Events/LogVersionMerge.swift, Sources/FoundationModelsKanban/Observe/BoardFolderChanges.swift, Sources/FoundationModelsKanban/Tool/BoardEngine.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Tests/FoundationModelsKanbanTests/Events/LogVersionMergeTests.swift, Tests/FoundationModelsKanbanTests/Observe/BoardFolderChangesTests.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanHostTests.swift
    - next: /test, then commit, then /review. All 4 findings checked.
  timestamp: 2026-11-24T15:37:49.028728+00:00
- actor: wballard
  id: 01m873c5mdjy7t7bgj8jce81sw
  text: |-
    ### test — green
    - evidence: swift test at the package root, 1985 tests in 172 suites passed, 0 failed, 0 skipped. The only warning is the accepted mlx-swift_Cmlx.bundle warning.
    - next: review
  timestamp: 2026-11-24T15:39:15.469033+00:00
- actor: wballard
  id: 01m873cttb2cvej1vw9c8jv9wh
  text: |-
    ### commit — changed
    - evidence: One commit holds the fix of the 4 findings of the 2026-11-24 09:26 review. EventLog.resolveConflicts is the one merge step. BoardEngine and the folder stream call it. The merge test asserts .tasksChanged([taskID]). makeHost and makeGraph use a fake version store by default. KanbanGraph.init(root:...) takes readingVersionsWith. No behavior change.
    - next: review
  timestamp: 2026-11-24T15:39:37.163112+00:00
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

## Review Findings (2026-11-24 09:26)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Sources/FoundationModelsKanban/Observe/BoardFolderChanges.swift:272` `reuse/reuse` — The new private func resolveConflicts(in:scanningBoardDirectory:addingChangedFiles:) in BoardFolderReader repeats the body of the existing BoardEngine.resolveConflicts(in:scanningBoardDirectory:). Both call log.resolveConflicts(ofFilesAt:scanningBoardDirectory:with: fileVersions), both catch the error, both write one Log.kanban.error line with the paths and the error, and both return a Bool. Only the log message, the folder metadata, and the optional changed-files list differ. Two copies of the merge-and-log step must now be kept in step. A fix to one copy, such as a change to the lock or the error policy, does not reach the other. Move the shared step into one function, for example a free function or an extension of EventLog, that takes the log, the file version source, the paths, the scansBoard flag, and a log message. Have BoardEngine and BoardFolderReader both call it. Each caller keeps only its own addingChangedFiles logic and its own log message.
- [x] `Sources/FoundationModelsKanban/Observe/BoardFolderChanges.swift:279` `duplication/duplication` — The private resolveConflicts(in:scanningBoardDirectory:addingChangedFiles:) in BoardFolderReader repeats the body of BoardEngine.resolveConflicts(in:scanningBoardDirectory:). Both call log.resolveConflicts(ofFilesAt:scanningBoardDirectory:with: fileVersions), return true on success, and on failure write a Log.kanban.error with the same shape and return false. Only the log message, the metadata keys, and the optional changed-files list differ. The two copies can drift, for example if the merge call or its error policy changes in one place only. Extract one shared helper that takes the file list, the scansBoard flag, the fileVersions store, and the error message. Call it from both BoardFolderReader and BoardEngine. Keep the optional changed-files addition in the BoardFolderReader caller, so the helper gets the final file list. Because the BoardEngine copy is outside this change, report its call-site change as a separate task rather than editing it here.
- [x] `Tests/FoundationModelsKanbanTests/Observe/BoardFolderChangesTests.swift:344` `test-integrity/no-test-cheating` — The assertion `run.change != nil` may always pass, so it proves little. MergeRun.change is optional, but the value comes from firstChange(...), which returns a non-optional change. If firstChange only returns after it finds a match, this check adds nothing beyond the wait. The test should assert the change's contents (for example, that its kind is tasksChanged with the task id), not just that it exists. Remove the nil check, or replace it with an assertion on the change's kind and id, for example `#expect(run.change?.kind == .tasksChanged([taskID]))`. If firstChange can return nil, make runMerge fail the test in that case instead of passing a nil through.
- [x] `Tests/FoundationModelsKanbanTests/Tool/KanbanHostTests.swift:584` `completeness/invariant-propagation` — The new `readingVersionsWith` parameter of `makeHost` defaults to `ICloudFileVersions()`, the real iCloud Drive store. Every other default in this fixture is a fake or a fixed value (`fakeKey`, `fakeTop`, `mutationIDs`, the fixed clock), and the doc comment at line 554 says the fixture makes a host with the fake readers. Each test that calls `makeHost` without this argument now reads the real iCloud store, so test results can depend on the machine. Default `readingVersionsWith` to a fake or empty `FileVersionSource` in this fixture, so tests stay hermetic. Add a pass-through parameter to `makeGitHost` if a git-backed test needs to inject versions. Keep the real `ICloudFileVersions()` default only in production configuration.