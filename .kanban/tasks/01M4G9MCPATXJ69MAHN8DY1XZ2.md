---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4h6kvt8dzvy1339372zbcb2
  text: |-
    Research:
    - `BoardIndex.resolution(of:currentRoot:currentKey:)` is sync and only finds a path that the scan found. `BoardIndex.isPath` accepts only `/` and `~`.
    - `KanbanGraph.resolution(of:currentKey:)` resolves from the index, then rescans one time. `KanbanGraph.loadBoard` gives `.notFound` for `nil`, and `.notFound` gives `KanbanError.boardNotFound` (NOT_FOUND) with the search roots.
    - `RelatedBoards.board(resolvedAs:)` finds a loaded copy by `copy.directory.canonicalPath`, so a copy outside the scan places loads and reads with no change there.
    - `BoardLocator.key(ofRepoAt:knownKey:readingKeysWith:)` already gives the scan rule for a key read (cancel stops, other failure is logged and gives nil). Reuse it for the path read.
    - `BoardKey.read(fromRepoAt:)` gives `local/<lastPathComponent>` for a folder that is not a git repo, so the copy directory must be canonical (no `..`).
    Plan: add a shared `BoardIndex.directory(ofPath:currentRoot:)` (path prefixes `/`, `~`, `./`, `../`; relative from root), and `BoardLocator.resolution(ofFolderAt:currentRoot:readingKeysWith:)` that reads the key of any folder that exists. `KanbanGraph.resolution` calls it for a path ref that the index does not have, before the rescan.
  timestamp: 2026-10-09T20:45:30.312112+00:00
- actor: claude-code
  id: 01m4h6xzt6kd8w718fev5vwsy8
  text: |-
    Implementation landed.
    - `BoardIndex.directory(ofPath:currentRoot:)` is the one path rule: prefixes `/`, `~` (absolute) and `./`, `../` (from root). It gives a standardized URL (no `..`), so `BoardKey.read` gives `local/<real-folder-name>`.
    - `BoardLocator.resolution(ofFolderAt:currentRoot:readingKeysWith:)` reads the key of any folder that exists through the existing private `key(ofRepoAt:knownKey:readingKeysWith:)` (same scan rule: a cancel throws, other key failures are logged and give nil). A file or a missing path gives nil, so the engine gives NOT_FOUND.
    - `KanbanGraph.resolution(of:currentKey:)`: index first, then the folder read (no scan), then the rescan.
    - `BoardIndex.resolution(of copy:)` became `BoardResolution.init(of:currentRoot:)` so the index and the folder read share one current-board check. Callers updated (KanbanGraph.loadEachCopy, two tests).
    - Choice: the copy directory of a folder read is the standardized path the agent gave (symbolic links not resolved), so `Query.board(id:).path` shows that path. Equality with index copies and the current root uses `canonicalPath`.
    - Not changed: the NOT_FOUND message text ("a repo path from these places") is still correct advice, so it stays.
    - RED: 7 new tests failed with a stub (NOT_FOUND / nil). GREEN: 27 filtered tests pass. Full `swift test`: 1115 tests in 80 suites pass; only the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-09T20:51:02.086577+00:00
- actor: claude-code
  id: 01m4h6y21nzarssxycy7w3z70b
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, plan.md, Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoFixture.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoReadTests.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoWriteTests.swift; `swift test` 1115 tests in 80 suites passed, 0 failures, only accepted warnings
    - next: /review
  timestamp: 2026-10-09T20:51:04.373005+00:00
depends_on:
- 01M4G9Z14EEZ85ZSRQHFV1DCQ3
position_column: doing
position_ordinal: '80'
title: 'board: path argument accepts any folder path'
---
## What
plan.md §6.6: "To use a different copy, the agent gives its path in the `board` argument." Now `Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift:251-257` and `:274-276` resolve a path only when the scan found that copy. Also only a value that starts with `/` or `~` is a path, so `../x` is not a path.

- Treat a `board` value as a path when it starts with `/`, `~`, `./` or `../`. Resolve a relative path from the `root` of the `KanbanGraph`.
- A path to any folder resolves, also when the scan did not find it. The key of that board comes from `BoardKey.read` (with the no-git rule of the earlier task).
- A path to a folder that does not exist gives `NOT_FOUND`.
- Update plan.md §6.6.

## Acceptance Criteria
- [x] `board: "/tmp/x/other"` (outside the scan places) reads and changes the board in that folder.
- [x] `board: "../sibling"` resolves from `root`.
- [x] A path that does not exist gives `NOT_FOUND`.

## Tests
- [x] Tests in `Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift` and a mutation test with `board:` set to a path.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.