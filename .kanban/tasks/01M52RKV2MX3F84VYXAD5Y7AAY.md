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
- actor: claude-code
  id: 01m5akadqzvyz1sgxc2k4r5jca
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (4b9f488). 2 findings, 2 confirmed, 0 refuted. Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift:248, Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift:424
    - next: Move the bare-folder key reader to one shared test helper. Both tests must call it. Then run the review again.
  timestamp: 2026-10-19T17:28:33.279137+00:00
- actor: claude-code
  id: 01m5akavezhz9f1acce3mbw296
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 3 new files, 13 Sources files, 11 test files, 2 docs
    - test: green — swift test, 1629 passed
    - commit: 4b9f488
    - review: findings — BoardLocatorTests.swift:248, BoardLocatorTests.swift:424
  timestamp: 2026-10-19T17:28:47.327521+00:00
- actor: claude-code
  id: 01m5akfnnf0j9mzyxagazpp583
  text: |-
    Fixed the 2 `reuse/reuse` findings in BoardLocatorTests.swift. A new test helper `BoardLocatorTests.bareFolderKeyReader(giving:)` holds the one do/catch closure. It reads the key from git, and gives the fixed bare key on `.notARepo`. `folderWithBoardAndNoGitIsCopy` and `pathOutsideGitResolvesToBareBoard` both call it. No other `catch .notARepo` closure stays in the file. I did not use the production `boardKeyReader`: `HostConfiguration.bareBoardIDs` has a fixed `SystemULIDSource`, and it reads the board ID from the log first, so the fixture log of the scan test can give a key that is not the fixed key. Production code did not change.

    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift. `swift test`: 1629 tests in 134 suites pass. The only warning is the accepted SwiftPM "missing creator" warning.
    - next: review
  timestamp: 2026-10-19T17:31:25.231898+00:00
- actor: claude-code
  id: 01m5akn682rgcd2jpqz07kv5dj
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (fe04806). 1 finding (1 confirmed, 1 refuted). Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift:263 reuse/reuse. The 2 prior findings are checked.
    - next: Add a key reader parameter with a default value to Self.scan, and call Self.scan at the call site. Then run the review again.
  timestamp: 2026-10-19T17:34:26.050822+00:00
- actor: claude-code
  id: 01m5aknkxnz9crcqfmy2rkd8vw
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 1 file (BoardLocatorTests.swift)
    - test: green — swift test, 1629 passed
    - commit: fe04806
    - review: findings — BoardLocatorTests.swift:263
  timestamp: 2026-10-19T17:34:40.053340+00:00
- actor: claude-code
  id: 01m5akrmng6pft7bb4mj8f04cw
  text: |-
    Fixed the `reuse/reuse` finding at BoardLocatorTests.swift:263. The test helper `BoardLocatorTests.scan` now has two more parameters with default values: `reusing earlier: BoardIndex? = nil` and `readingKeysWith keyReader: BoardKeyReader = BoardKey.read(fromRepoAt:)`. I removed the same cause from the whole file: all 5 direct `BoardLocator.default.scan` calls now use `Self.scan` (in `folderWithBoardAndNoGitIsCopy`, `rescanReadsKeyOfNewRepoOnly` (2 calls), and `rescanSkipsUnreadableRepo` (2 calls)). The `reusing` parameter is necessary because the rescan tests give the earlier index. No direct `BoardLocator.default.scan` call stays in the file. Production code did not change.

    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift. `swift test --filter BoardLocatorTests`: 26 tests in 1 suite pass. The only warning is the accepted SwiftPM "missing creator" warning.
    - next: test, then review
  timestamp: 2026-10-19T17:36:19.120230+00:00
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

## Review Findings (2026-10-19 12:24)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 28 file(s) reviewed, 8 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `Documentation/kanban/SKILL.md` — no validator matches this file
> - `README.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift:248` `reuse/reuse` — The test makes its own key reader for bare folders. It uses the same do/catch pattern as the other bare-folder test. It does not use one shared helper. If the rule for bare-folder keys changes, the two tests can drift apart. Move the closure to one test helper that takes the bare key as a parameter. Call it from both tests. Or build the reader once from the production `boardKeyReader` with a fixed bare-ID source.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift:424` `reuse/reuse` — The bare-folder key reader in this test repeats the closure in `folderWithBoardAndNoGitIsCopy` (line 248). The same logic is in two places in the file. Use one shared helper for the bare-folder key reader, as in the finding at line 248. Then both tests call the helper.

## Review Findings (2026-10-19 12:33)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 1 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift:263` `reuse/reuse` — The new call in folderWithBoardAndNoGitIsCopy calls BoardLocator.default.scan directly, not through the test's own scan helper. The helper Self.scan(around:with:) is a near-match that already wraps this call, but it has no key reader parameter. The test therefore builds a parallel call instead of extending the helper. Add a defaulted `readingKeysWith keyReader: BoardKeyReader = BoardKey.read(fromRepoAt:)` parameter to Self.scan, and call Self.scan(around: app, readingKeysWith: Self.bareFolderKeyReader(giving: bareKey)) at the call site.
