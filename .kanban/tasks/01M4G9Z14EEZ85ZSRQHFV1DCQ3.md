---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4h627q3bsgqjtnmp4f512a5
  text: |-
    Research:
    - `BoardLocator.repos(in:)` accepts a directory only when it has a `.git` entry. This is the only cause of the problem.
    - `Git.run` has two callers in Sources, both in `Identity/BoardKey.swift`: `repoPaths(at:)` and `originURL(ofRepoAt:)`. ^j47qcme already makes `repoPaths(at:)` give `nil` for a folder that is not a git repo, and `read(fromRepoAt:)` then gives `local/<folder-name>` before it calls `originURL`. Thus no `Git.run` caller throws for such a folder. No change is necessary there.
    - `BoardCopy.init(directory:key:)` already uses `EventLog(repositoryAt:).fileURL(for: .board)` for the enabled state. The candidate check will use the same path.
    - Test helpers: `GitSandbox.makeFolder(named:in:)`, `KanbanGraphTests.writeFixture(inRepoAt:)`, `GitGraphFixture.makeGraph(at:)`, `CrossRepoFixture.addTask(with:on:)`.
  timestamp: 2026-10-09T20:35:52.675226+00:00
- actor: claude-code
  id: 01m4h6a4m8m4gjkd6bbv6scp0c
  text: |-
    Implementation landed (TDD).
    - RED: `scanFindsBoardInFolderWithNoGit` failed (no copy for the plain folder), and `nodeReadsRelatedBoard(kind: .plainFolder)` gave `{"data":{"node":null}}`. `folderWithNoGitAndNoBoardIsNotCopy` passed at RED: it guards the rule that a plain folder with no board stays out of the index.
    - GREEN: `BoardLocator.isCandidate(_:)` accepts a directory with a `.git` entry OR `.kanban/board.jsonl`. `BoardCopy.hasBoardLog(at:)` now holds the board-log check, and `BoardCopy.init(directory:key:)` and `isCandidate` both use it. The key path is still only `BoardKey.read(fromRepoAt:)` (^j47qcme). No second key path.
    - `Git.run` callers: no change. `repoPaths(at:)` gives nil for a folder that is not a repo, and `read(fromRepoAt:)` returns `local/<folder-name>` before `originURL` runs.
    - Test fixture: `CrossRepoFixture.FolderKind` (`gitRepo`, `plainFolder`) with `makeFolder(named:origin:in:)`; `SideBySide.make(as:)` defaults to `gitRepo`. The existing `node(id:)` cross-board test now runs for both kinds.
    - Choice: two plain folders with the same name get the same key `local/<folder-name>`. They follow the many-copies rule (first copy in scan order). plan.md §12 item 26 says this.
    - plan.md: §6.6 Scan, §12 items 13 and 26 updated.
  timestamp: 2026-10-09T20:40:11.656519+00:00
- actor: claude-code
  id: 01m4h6a72wdnpsapaq65vy2b7d
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift, Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoFixture.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoReadTests.swift, plan.md. `swift test`: 1104 tests in 80 suites passed, 0 failures; only build warning is the accepted SwiftPM "missing creator for mutated node".
    - next: /review
  timestamp: 2026-10-09T20:40:14.172240+00:00
- actor: claude-code
  id: 01m4h6f9xd8mvvqwpadg31k3yn
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD — 0 findings (4 source and test files reviewed; .kanban/ files are excluded by .reviewignore; no validator matches plan.md). The commit message of afca516 is true for the diff. Each acceptance item and test item is met. The two Git.run callers in BoardKey.swift do not throw for a folder that is not a git repo.
    - next: done
  timestamp: 2026-10-09T20:43:00.909326+00:00
- actor: claude-code
  id: 01m4h6farqgcv0az0hke65e11n
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 5 files
    - test: green — swift test, 1104 tests in 80 suites passed
    - commit: afca516
    - review: clean — 0 findings
  timestamp: 2026-10-09T20:43:01.783190+00:00
depends_on:
- 01M4G9M4WCVGV3X1JAQJ47QCME
position_column: done
position_ordinal: da80
title: BoardLocator finds boards in folders that are not git repos
---
## What
The owner decided that git is not required. The task ^j47qcme gives a board key to a folder that is not a git repo. But `repos(in:)` in `Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift` (about lines 77-93) accepts a directory only when it has a `.git` entry. Thus the locator does not find a related board in a folder that is not a git repo.

- `repos(in:)`: a directory is a candidate when it has a `.git` entry OR a `.kanban/board.jsonl` file.
- Find the other `Git.run` callers (`rg -n "Git.run" Sources`). Make each one work when the folder is not a git repo: skip the git step, or use the `local/<folder-name>` rule of ^j47qcme. Do not throw `gitFailed` for a folder that is not a git repo.
- Update plan.md: §6.6, §12 items 13 and 26. Say that the locator finds a board in a folder with `.kanban/board.jsonl` and no `.git`.

## Acceptance Criteria
- [x] The locator finds a related board in a sibling folder that has `.kanban/board.jsonl` and no `.git`.
- [x] A sibling folder with no `.git` and no `.kanban/board.jsonl` is not a candidate.
- [x] No `Git.run` caller throws for a board in a folder that is not a git repo.
- [x] Each existing locator test still passes.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift`: a sibling board with no `.git`, and a sibling folder with no `.git` and no board.
- [x] A test that runs a cross-board query from a board in a plain temp folder to a sibling board in a plain temp folder.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.