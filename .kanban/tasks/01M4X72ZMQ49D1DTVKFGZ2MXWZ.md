---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4yehgd18k97n7h1mqx5vgg1
  text: 'Research done. Each key lookup (dependency readiness, node(id:), undo boards(of:)) goes through KanbanGraph.resolution(of:current:): first the cached scan index, then BoardLocator.resolution(ofFolderAt:) for a path, then host.currentScanIndex. A path outside the scan places resolves only in the folder step, and nothing records it, so a later key ref of that board gives NOT_FOUND. Plan: the host keeps the copies that a call reached by a path (key + worktree top). The key lookup asks the scan index first (first copy in scan order, the plan §6.6 rule), then the copies reached by a path, in the sort order of the path. Test fixture: CrossRepoWriteTests.makeOutsideFolder (sandbox/outside/other, origin new-lib), never the .kanban/ of this repo.'
  timestamp: 2026-10-15T00:14:09.313572+00:00
- actor: claude-code
  id: 01m4yf35c898mjbhkmb8y162b5
  text: |-
    Implementation landed (TDD). RED: 5 of the 6 new tests in PathBoardKeyTests failed before the change (key ref NOT_FOUND, node null, ready false, undo NOT_FOUND). The test "scanCopyComesBeforePathCopy" passed before the change. It is a guard of the order rule: a copy in the scan index comes before a copy that a call reached by a path. GREEN: all 6 pass after the change.

    Change: KanbanHost keeps `pathCopies` (canonical worktree top -> BoardCopy). `recordPathCopy(_:)` records each `.copy` that BoardLocator.resolution(ofFolderAt:) gives in KanbanGraph.resolution(of:current:). `pathCopy(namedBy:)` resolves a key or board URI only after the current scan index has no copy with the key. Copies with the same key resolve in the sort order of the canonical path. A copy whose folder is gone does not match. BoardIndex.boardKey(in:) is now internal (it was private), so the host can parse the key the same way.

    Full `swift test` (one run): 1281 tests, 11 issues, all `BoardWatcherError.streamNotStarted` in IncompatibleBoardTests and TagMutationTests. Those two suites pass alone (40 tests, `swift test --skip-build --filter "IncompatibleBoardTests|TagMutationTests"`). At the time of the run the machine load average was about 65, and a FoundationModelsAgents swift test process was running. The FSEvents stream limit applies to the whole system. The /test step must confirm that the suite is green.
  timestamp: 2026-10-15T00:23:47.848715+00:00
- actor: claude-code
  id: 01m4yf37vd1rr0bsbdpy3yqeqz
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/Tool/KanbanHost.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift, Tests/FoundationModelsKanbanTests/CrossRepo/PathBoardKeyTests.swift (new, 6 tests pass). Full suite: 11 streamNotStarted issues in 2 suites that this change does not touch. Those 2 suites pass alone.
    - next: /test, to confirm the full suite is green, then /review
  timestamp: 2026-10-15T00:23:50.381931+00:00
depends_on:
- 01M4X6XKP0Y832GDRHQ1MG22VF
position_column: doing
position_ordinal: '80'
title: Put a board that a call reached by a path into the key index
---
## What
divergence.md X4 (§1.1, §11 bugs; K8 stays as work). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem: a board that the call reached only by a path to a folder outside the scan places (for example `board: "/x/notes"`, where `/x/notes` is a git repo) does not go into the scan index (S/Tool/KanbanGraph.swift:703-721). A path into a folder that the scan finds is in the index. Results: a task on that board is done, but a task that depends on it stays BLOCKED; `node(id:)` with a URI of that board gives null; undo with no `board` field, of a transaction that also changed that board, gives `NOT_FOUND`. Undo with `board: "/x/notes"` works.

Note: after the task "Put the board only in a git repo", a `board:` path must be inside a git repo. This task applies to such a path outside the scan places.

Change: when a call reaches a board by a path, add that board (its key and its worktree top) to the key index of the host (or the locator), so that a later URI with that key resolves to it. Use the same order rule as for other copies with the same key.

## Acceptance Criteria
- [x] After a call with `board: "<path outside scan places>"`, a URI with the key of that board resolves to it.
- [x] A task that depends on a done task on that board is READY.
- [x] `node(id:)` with a URI of that board gives the node.
- [x] Undo with no `board` field, of a transaction that also changed that board, reverses both boards.

## Tests
- [x] The three results above, each as a test (these are also listed in the K14 missing tests).
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.