---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m508djgvw79wbjrhfxd4hyjk
  text: |-
    Research done.
    - `KanbanGraph.resolution(of:current:)` calls `BoardLocator.resolution(ofFolderAt:...)` on each path ref that the scan index does not have. That runs the top reader and the key reader each time, also for a path to a board that `recordPathCopy` already knows.
    - `KanbanHost.pathCopies` is keyed by the top folder of the worktree. It has a watch on the parent folder and forgets the copy on `WatchedPlace.keyChange(ofRepoAt:in:)`.
    - Plan: replace `pathCopies` with one table of path ref results, keyed by the canonical path of the named folder: a board copy, `notARepo`, or a failed key read. Each entry has one watch on the parent folder of the watched repo (the top for a board or a failed key read, the folder itself for notARepo). A change of the repo folder, its `.git`, or its git config forgets the entry. New commits also forget a failed key read, the same as `BoardIndex.isExpired`. `pathCopy(namedBy:)` reads the board entries. Thus one watch serves the key index and the path cache, and a board does not get two watchers.
    - `BoardLocator.resolution(ofFolderAt:)` splits into a folder lookup (no git) and a git read of the folder. The test helper `BoardLocatorTests.resolveFolder` composes the two parts.
    - Known limit: the watch sees only the repo folder of the result. A `git init` in a folder between the named folder and the top, or in a parent folder of a notARepo folder, is not seen.
  timestamp: 2026-10-15T17:05:37.819821+00:00
- actor: claude-code
  id: 01m5095bhe03cqsp96ktca7zfn
  text: |-
    Implementation landed (TDD).
    - RED: the new suite `PathRefCacheTests` (4 tests) failed before the change: the git-call counter went up on each repeated path ref (3 to 6, 4 to 10, 7 to 13), and the `git init` test hit the time limit because no watcher saw the folder.
    - New `S/CrossRepo/FolderBoard.swift`: what git tells about a folder of a path ref (`.board(copy)`, `.notARepo(path:)`, `.unreadableKey(top:)`), its resolution for one call, its watched repo, and `isExpired(by:ofRepoAt:)` (repo, place, and new commits for a failed key read).
    - `BoardLocator.resolution(ofFolderAt:...)` split into `folder(namedBy:currentRoot:)` (no git) and `board(ofFolderAt:readingKeysWith:findingTopsWith:)` (git). The test helper `BoardLocatorTests.resolveFolder` composes them.
    - `KanbanHost`: `pathCopies` replaced by `knownFolders`, keyed by the canonical path of the named folder. One watch on the parent folder of the watched repo serves the path cache and the key index (X4). `recordPathCopy` and `WatchedPlace.keyChange(ofRepoAt:in:)` are gone (no caller left). Observer method renamed `pathCopyDidChange` to `pathRefDidChange`.
    - Test helper `ScanKeyReader.topReader` now throws `notARepo` for a folder with no `.git` entry, so the fake reader can model a plain folder.
    - GREEN: `swift test --filter PathRefCacheTests` 4/4. Full `swift test`: 1510 tests in 120 suites passed, only the accepted mlx "missing creator" warning.
    - Known limit (documented in `recordBoard`): the watch sees only the watched repo folder. A new repo in a folder between the named folder and the top of its worktree, or in a parent folder of a notARepo folder, does not show. The watcher also starts after the git read, the same as the old `recordPathCopy`.
  timestamp: 2026-10-15T17:18:37.102247+00:00
- actor: claude-code
  id: 01m5095fv5aa9t6qvzssyw7j6w
  text: |-
    ### implement — changed
    - evidence: 7 files — S/CrossRepo/FolderBoard.swift (new), S/CrossRepo/BoardLocator.swift, S/CrossRepo/ScanChange.swift, S/Tool/KanbanHost.swift, S/Tool/KanbanGraph.swift, Tests/.../CrossRepo/PathRefCacheTests.swift (new), Tests/.../CrossRepo/ScanCacheTests.swift, Tests/.../CrossRepo/BoardLocatorTests.swift (8 with the test helper). `swift test`: 1510 tests in 120 suites passed.
    - next: /review
  timestamp: 2026-10-15T17:18:41.509227+00:00
- actor: claude-code
  id: 01m509tnh34kh8ysp9k002rv3j
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 8 files
    - test: green — swift test, 1510 passed, 0 failed, 0 skipped; IntegrationTests 3 passed
    - commit: f927525
    - review: findings — Tests/FoundationModelsKanbanTests/CrossRepo/PathRefCacheTests.swift:66, Tests/FoundationModelsKanbanTests/CrossRepo/PathRefCacheTests.swift:94
  timestamp: 2026-10-15T17:30:15.459008+00:00
- actor: claude-code
  id: 01m50atns05eyx6knspvjqjnh2
  text: |-
    Review findings fixed (tests only, no production change).
    - `firstCommitFindsBoard`: a path ref to a repo whose key read fails, then `reader.setOrigin` and a written `.git/refs/heads/main` (the first commit, with no git). The wait is on `.commits(inRepo:)` until the call finds the board; the key is the new key.
    - `replacedRepoIsReadAgain`: a path ref to a repo, then the parent folder gets a new modification date first, the old repo moves away, and a new repo with a new origin is made at the same path. The wait is on `.place(parent)` until `host.board(ofFolderAt:)` gives the new key; the git-call counter goes up.
    - Mutation check: with `.place: false` and the `.commits` clause set to false in `FolderBoard.isExpired`, both new tests hit the 60 s time limit. With the code restored, they pass.
    - Discovery: FSEvents (file events) reports a change of the watched root folder itself (a new modification date, chmod, xattr) with the path of the root. The root event comes first in the batch when it comes first in time. The host thus reports `.place` and not `.repo`.
    - Discovery (new task ^0nkvw6d): after the `.place` forget, the host gives the new copy, but the GraphQL read through the session view still gives the old key. `KanbanGraph.loadRelatedBoard` keeps the first engine of a path in `relatedBoards` and `SessionFeeds`. So the `.place` test checks the host result, not the GraphQL read.
    - `swift test`: 1512 tests in 120 suites passed; only the accepted mlx "missing creator" warning.
  timestamp: 2026-10-15T17:47:44.288466+00:00
- actor: claude-code
  id: 01m50atqdj73jdgezhqcax1w1t
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/CrossRepo/PathRefCacheTests.swift (2 new tests, 2 helpers, 3 constants). Both review findings checked. `swift test`: 1512 passed, 0 failed. New task ^0nkvw6d for the stale related engine of the session view.
    - next: /review
  timestamp: 2026-10-15T17:47:45.970782+00:00
- actor: claude-code
  id: 01m50bash980cfxdfc8ff5sfsy
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 1 test file (2 findings fixed; no code change needed)
    - test: green — swift test, 1512 passed, 0 failed, 0 skipped; IntegrationTests 3 passed
    - commit: bea7ae3
    - review: clean — none
  timestamp: 2026-10-15T17:56:32.425485+00:00
depends_on:
- 01M4X707X79HZ4TJARR3PRJNB4
- 01M4X72ZMQ49D1DTVKFGZ2MXWZ
position_column: done
position_ordinal: ff8780
title: Keep the result of a path board ref in memory, so a repeated path ref runs no git
---
## What
divergence.md §16 Gap 1 (the rule: a read runs no `git`). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Found during ^3prjnb4. `KanbanGraph.resolution(of:current:)` sends a path ref that the scan index does not have to `BoardLocator.resolution(ofFolderAt:...)`. That function runs `git rev-parse --show-toplevel` (the top reader) and the key read on each call. The card ^gz2mxwz puts a board that a path reached into the key index, so a later ref to that board hits the index. But these cases still run `git` on each call:
- a path to a folder that is not in a git repo (the call gives `NOT_A_REPO`);
- a path to a repo whose key read fails.

Change:
- Keep the result of a path ref (the board, `notARepo`, or a failed key read) in the host, in memory.
- Forget the result when a file watcher sees a change of that folder (a new `.git`, a changed git config), the same as the scan cache of ^3prjnb4 (`ScanCache`, `ScanChange`).

## Acceptance Criteria
- [x] A second call with the same path ref to a folder that is not in a git repo runs no `git`.
- [x] A second call with the same path ref to a repo whose key read fails runs no `git`.
- [x] After `git init` in that folder, the next call with the path ref finds the board.

## Tests
- [x] A git-call counter stays the same over many calls with the same path ref.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-15 12:23)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 8 file(s) reviewed, 6 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/PathRefCacheTests.swift:66` `completeness/inverse-operation-coverage` — The change adds a forget path for a failed key read: `FolderBoard.isExpired` returns true for `.commits` in a repo whose key read failed (FolderBoard.swift:73). The record direction is tested by `failedKeyReadRunsNoGit`, which checks that repeated calls run no git. No test checks the inverse, where new commits give the repo a key and the next call reads git again. The test named for a failed key read only asserts that calls stay silent. Add one test. Record a path ref to a repo whose key read fails, make the first commit in the repo, wait with the recorder for `.commits(inRepo:)`, then check that the path ref finds the board. This proves the forget direction for the unreadable-key case.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/PathRefCacheTests.swift:94` `completeness/inverse-operation-coverage` — The change adds a forget path for a change of the parent folder of the watched repo: `FolderBoard.isExpired` returns true for every `.place` change (FolderBoard.swift:72). No test checks it. The only forget test, `gitInitFindsBoard`, uses a `.repo` change. So the next call after a change of the parent folder, which may replace or remove the repo, is not shown to read git again. Add one test. Record a path ref to a folder, replace the watched repo in its parent folder (for example move it away and make a new repo there), wait with the recorder for `.place(parent)`, then check that the next call reads git again and gives the new board. This proves the `.place` forget direction.
