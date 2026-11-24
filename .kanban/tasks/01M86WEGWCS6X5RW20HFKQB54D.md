---
comments:
- actor: wballard
  id: 01m86zhxn7m94ycktd35gpjdks
  text: |-
    Research done.
    - FileStamp (CrossRepo/ScanMarks.swift) uses stat only. It is the base of each entry.
    - The lock (LockedFile.lock) makes .lock, and prepareDirectory can make .gitattributes and .gitignore, in .kanban/. These new entries change the modification time of the .kanban/ directory. Thus the digest uses only the identity (device, inode) of each directory. The list of file entries already shows an added, a removed or a renamed log file. The full FileStamp of each directory stays in BoardStamp.entries(ofBoardAt:).
    - The guard of BoardRead.init (existingBoardDirectory plus isFolder) has the same result as a FileStamp of .kanban/ that is a directory. The new code uses the stamp for that guard.
    - Test fixtures: KanbanGraphTests.writeFixture(inRepoAt:) gives a board, a todo column and one task. KanbanGraphTests.writeTask(titled:mintingFrom:to:) adds a task file. BoardWatcherTests.writeLaterTitle appends one line.
  timestamp: 2026-11-24T14:32:29.607584+00:00
- actor: wballard
  id: 01m86zswk1pd42wdd2rd6w83rg
  text: |-
    Implementation landed (TDD: the new tests failed to compile first, because BoardStamp, KanbanHost.boardStamp(ofFolder:) and BoardSnapshot.stamp did not exist).
    - Public API: BoardStamp (Hashable, Sendable, Codable, value: String, SHA-256 hex), KanbanHost.boardStamp(ofFolder:) -> BoardStamp?, BoardSnapshot.stamp.
    - Internal: BoardStamp(ofBoardAt:), BoardStamp(digesting:), BoardStamp.entries(ofBoardAt:) -> [String: FileStamp]? keyed by the path relative to .kanban/ ('.' for the directory, for example tasks/<ULID>.jsonl).
    - A directory adds only its device and inode to the digest. Its times change when the lock or a git file appears, and the file list already shows an added or a removed log file. The entries keep the full FileStamp of each directory, so the change stream must also ignore directory times if it must ignore the lock.
    - BoardRead.init now uses the stamp as its no-board guard (a .kanban that is not a directory gives nil), and reads the stamp before the loader. The private isFolder helper is removed.
    - Limit (documented on BoardStamp): a same-size rewrite in place in one time tick does not show on a file system with coarse times (HFS+, FAT, some network shares). On APFS the times have nanoseconds, and a test proves a same-size rewrite in place changes the stamp. A new device number after a mount again gives one extra read.
    - BoardSnapshotTests: expectedSnapshot(from:in:) now adds the stamp; the BoardRead.snapshot test helper is internal so BoardStampTests can use it.
  timestamp: 2026-11-24T14:36:50.657641+00:00
- actor: wballard
  id: 01m86zswxz19eg7pb8pafdzgj7
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/Snapshot/BoardStamp.swift (new), Sources/FoundationModelsKanban/Snapshot/BoardSnapshot.swift, Sources/FoundationModelsKanban/Tool/KanbanHost.swift, Tests/FoundationModelsKanbanTests/Snapshot/BoardStampTests.swift (new, 11 tests), Tests/FoundationModelsKanbanTests/Snapshot/BoardSnapshotTests.swift. swift test: 1960 tests in 171 suites passed, 0 failures, 0 warnings.
    - next: /review, then /double-check as the card asks. After the commit, send the API names and the commit to the FoundationModelsACPAgent session and the TestudoApp session.
  timestamp: 2026-11-24T14:36:51.007424+00:00
- actor: wballard
  id: 01m86zy682r8k3t96v5ndwcfsm
  text: |-
    ### test — green
    - evidence: swift test at the package root, one run, 1960 tests in 171 suites passed, 0 failed, 0 skipped. The only build warning is the accepted mlx-swift_Cmlx.bundle warning.
    - next: review
  timestamp: 2026-11-24T14:39:11.618956+00:00
- actor: wballard
  id: 01m86zynb9fc2nrq9hdj51d03x
  text: |-
    ### commit - changed
    - evidence: the commit adds BoardStamp, KanbanHost.boardStamp(ofFolder:) and BoardSnapshot.stamp, with tests
    - next: review
  timestamp: 2026-11-24T14:39:27.081409+00:00
depends_on:
- 01M86WE7KQXHJCAX08PMRGYRKR
position_column: doing
position_ordinal: '80'
title: Add a cheap stamp of the board of a folder that reads no task file
---
## Problem
TestudoApp (D214) must know cheaply if the board of a folder changed, so that it reads the board again only after a change. Brief: `/Users/wballard/github/swissarmyhammer/.briefs/FoundationModelsKanban-spotlight-board-reads-2026-11-24.md`, item 2.

No public stamp exists now. The internal parts are not correct for this use:
- `FileSignature` (Sources/FoundationModelsKanban/Events/EventLog.swift) reads the last line of each file (`lastEventID`). Thus it reads each task file.
- `Board.cursor` and `Query.cursor` are cursors of the change log in memory of a session. They need a session, and they do not survive a restart.
- `FileStamp` (Sources/FoundationModelsKanban/CrossRepo/ScanMarks.swift) uses `stat` only (device, inode, size, modification and status times). This is the correct base.

The modification date of a directory changes when a file is added, removed, or renamed. It does not change when a line is appended to a file that is there. Thus the stamp must `stat` each log file. A `stat` opens and reads no file.

## What
- New file `Sources/FoundationModelsKanban/Snapshot/BoardStamp.swift`: `public struct BoardStamp: Hashable, Sendable, Codable` with `public let value: String`.
- The value is a SHA-256 hex digest (CryptoKit) of the sorted list of (relative path, `FileStamp`) for: the `.kanban/` directory, `board.jsonl`, the directories `columns/`, `tasks/`, `comments/`, `tags/`, `actors/`, and each `*.jsonl` file in them. Do not use `Hasher`: its seed changes for each process, and TestudoApp can keep the stamp after a restart.
- Leave out `.lock` and each file that is not a node log (`EventLog.ref(ofFileAt:)`), so that a lock of a session does not change the stamp.
- Public entry point: `nonisolated func boardStamp(ofFolder folder: URL) -> BoardStamp?` on `KanbanHost`. `nil` means no `.kanban/` (no board).
- Add `public let stamp: BoardStamp` to `BoardSnapshot`. `readBoard(inFolder:)` reads the stamp before it reads the files, the same as `LiveGraph.join(using:)` reads the signatures first (Sources/FoundationModelsKanban/Observe/LiveGraph.swift). Thus a write during the read gives a different stamp at the next check, and no change is lost.
- Keep the per-file stamp list internal and available (for example `BoardStamp.entries(ofBoardAt:) -> [String: FileStamp]`), because the change stream uses it.

## Acceptance Criteria
- [x] `boardStamp(ofFolder:)` gives `nil` for a folder with no `.kanban/`.
- [x] The stamp is equal before and after a read with no change.
- [x] The stamp is different after a change of one task, of one column, after a new task file, and after the removal of a task file.
- [x] A test proves that the stamp opens no log file (for example a task file with no read permission still gives a stamp).

## Tests (write them first)
New file `Tests/FoundationModelsKanbanTests/Snapshot/BoardStampTests.swift`.
- [x] The stamp is the same after a read with no change. (Brief test: take the stamp, run `readBoard(inFolder:)`, take the stamp again.)
- [x] The stamp is different after a change of one task (append one line with `BoardWatcherTests.writeLaterTitle(to:mintingFrom:in:)`). (Brief test.)
- [x] The stamp is different after a change of one column, after a new task file, and after a delete of a task file.
- [x] A folder with no `.kanban/` folder gives "no board" (`nil`). (Brief test.)
- [x] A `.lock` file that a session makes does not change the stamp.
- [x] `snapshot.stamp` equals `boardStamp(ofFolder:)` when nothing changed after the read.
- [x] `swift test` passes. Run the headless root `swift test` one time only.

## Workflow
- Use `/tdd`: write the failing tests first, then make them pass.
- Run `/double-check` before review.

## Note
This work is for TestudoApp D214. When it is done, send the public API names and the commit to the FoundationModelsACPAgent session and to the TestudoApp session. #testudo