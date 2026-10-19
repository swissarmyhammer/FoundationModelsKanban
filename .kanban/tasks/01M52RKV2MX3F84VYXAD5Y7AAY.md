---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5ahpx47ck74rcc93a9fa41g
  text: |-
    Research done. Findings:
    - The session board comes from `KanbanGraph.resolveBoard()`: `topReader` gives the worktree top; `BoardKeyError.notARepo` now gives `ResolvedBoard.notARepo` and `KanbanError.notARepo` on each call.
    - The engine key comes from `EngineLoad.key()` -> `configuration.keyReader` (git). A bare folder has no git key, so the key must be the board ULID (primary ID of the board log). A bare folder with no board ID yet needs an ID before the first write, and the first write must record that same ID. `recordBoardNames(currentKey:at:)` mints a new ID today; it must use the key when the key is a board ID.
    - The scan (`BoardLocator.scan`) accepts only folders with a `.git` entry (`isCandidate`). `BoardLocator.board(ofFolderAt:)` gives `FolderBoard.notARepo` for a path ref outside git.
    - `RepoMark` needs a `.git` entry. For a bare folder it is nil, so a change of a bare board log or a new `.kanban/` in a sibling bare folder does not expire the scan index. RepoMark must accept a folder with a `.kanban/` and no `.git`.
    - Warnings go into `context.warnings` in `KanbanGraph.runCall` (the same path as `checkUnreadableBoards`).
    - Test folders are in `/tmp/fmk-tests/<run>/...`, not in a git repo, so bare-folder tests with real git readers work there.
    Plan: a key reader in `HostConfiguration` that gives the board ID key when git says notARepo (with a per-host record of minted IDs for boards with no ID); search up for `.kanban/` outside git; scan candidates with `.kanban/` and no `.git`; remove `NOT_A_REPO`; a subfolder-board warning and a shared-board-ID warning.
  timestamp: 2026-10-19T17:00:25.095681+00:00
- actor: claude-code
  id: 01m5ak0yhs3km1gh7hv3bpbd7f
  text: |-
    Progress: implemented, and all acceptance criteria have passing tests.

    - New: `BareBoard` and `BareBoardIDs` (CrossRepo/BareBoard.swift) find the board outside git with search up, and give a stable board ID key before the first write. New: `SubfolderBoard` (`BOARD_IN_SUBFOLDER`) and `SharedBoardID` (`BOARD_ID_SHARED`) in CrossRepo/BoardPlaceWarnings.swift.
    - Removed `KanbanError.notARepo`, `BoardResolution.notARepo`, and `FolderBoard.notARepo`. `BoardKeyError.notARepo` stays as an internal signal that `HostConfiguration.boardKeyReader` changes to the board ID key.
    - The scan finds sibling folders that have a `.kanban/` and no `.git`. A folder with no `.git` whose key is a git key is a subfolder of a repo, so it is not a copy.
    - Tests: Tests/FoundationModelsKanbanTests/Tool/BareFolderBoardTests.swift (5 tests), and updated tests in RepoBoardTests, BoardLocatorTests, CrossRepoReadTests, CrossRepoWriteTests, PathRefCacheTests, PathRefRecordTests, ScanCacheTests, KanbanErrorTests, BoardKeyTests, KanbanHostTests, and KanbanGraphTests.
    - Docs: README.md, Documentation/kanban/SKILL.md, the KanbanTool description, and the doc comments.
    - Full `swift test`: 1629 tests in 134 suites pass. The only warning is the accepted SwiftPM "missing creator" warning.

    A thing that I did not expect: after `git init` in a loaded bare folder, the engine keeps its board ID key until a restart. That is outside this task. I added the follow-up task ^cggdpve for it.

    step: implement
    outcome: changed
    task: ^d5y7aay
  timestamp: 2026-10-19T17:23:22.809157+00:00
depends_on:
- 01M52RKMDD8RJ7TNTQVE65466D
position_column: doing
position_ordinal: '80'
title: Put back boards in bare folders, with search up outside git
---
## What
divergence.md M9 "where the board is". A board can be in a folder that is not in a git repo. This replaces the M5 rule "a board exists only in a git repo". The old code in commits `afca516` (^fv1dcq3) and `107ffed` (^8dy1xz2) can be a start.

## Do
- In a git repo: the board stays at `<repo top>/.kanban/` (no change).
- Outside git: use the nearest folder, from the working directory up, that has a `.kanban/`. When none has one, use `<working dir>/.kanban/` (made on the first write). The key is the board ULID (^e65466d).
- Remove `NOT_A_REPO` for a folder outside git. A `board:` path to a bare folder names its board.
- `Query.boards` and the related-board scan also find sibling folders with a `.kanban/` and no `.git`.
- Two folders with the same board ULID (a copied folder): calls work, with a warning that names both paths.
- A `.kanban/` in a subfolder below a repo top: calls use the repo board, with a warning that names the subfolder board and tells the user to run `collectBoards`.

## Acceptance Criteria
- [x] A session in a bare folder, and in a subfolder of it, uses the nearest `.kanban/` above.
- [x] A session in a bare folder with no `.kanban/` above makes one in the working dir on the first write.
- [x] `boards` lists a sibling bare-folder board.
- [x] The copied-folder warning and the subfolder-in-repo warning are given.
- [x] Tests use temporary folders and temporary git repos only.