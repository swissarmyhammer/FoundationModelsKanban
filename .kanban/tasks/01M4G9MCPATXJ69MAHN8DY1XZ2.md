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
- actor: claude-code
  id: 01m4h74np56w1yzsa5bcn4jjek
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 7 files
    - test: green — swift test, 1115 tests in 80 suites passed
    - commit: 107ffed
    - review: findings — Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift:102, Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift:282, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoWriteTests.swift:278
  timestamp: 2026-10-09T20:54:41.093218+00:00
- actor: claude-code
  id: 01m4h78ezp1cgr4qxyxdeag4q7
  text: |-
    Research for the 3 review findings:
    - Each write of a board goes through `EventLog(repositoryAt:)`: `append` makes `<folder>/.kanban/` and the git files in it (`prepareDirectory`), then writes `<folder>/.kanban/<type>/<id>.jsonl`; the lock is `<folder>/.kanban/.lock`. Thus a write through a path ref already writes only under `<folder>/.kanban/`. No code change on the write path is necessary; the fix is the doc comment at `BoardIndex.directory(ofPath:currentRoot:)`, the trust text in plan.md §6.6, and a test that compares the files of the folder before and after.
    - `BoardKey.read` runs only read-only git commands (`rev-parse`, `remote get-url`), so the files of `.git/` do not change on a key read. The test can compare the contents of each file outside `.kanban/`, not only the paths.
    - `isFolder` goes: the guard in `BoardLocator.resolution(ofFolderAt:currentRoot:readingKeysWith:)` calls `FileManager.default.fileExists(atPath:isDirectory:)` directly. The existing tests for a file path and a missing path cover it.
    - The new tests are coverage of behavior that exists, so they pass on the first run (no RED from a missing feature).
  timestamp: 2026-10-09T20:56:45.302132+00:00
- actor: claude-code
  id: 01m4h7f9a2sc684x2epykrg1g8
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift (remove `isFolder`, inline `FileManager.default.fileExists(atPath:isDirectory:)` in the guard; trust-decision doc comment at `BoardIndex.directory(ofPath:currentRoot:)` that points to plan.md §6.6), plan.md (§6.6 new bullet "Trust of a path ref"), Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift (`outsideReferenceFromRoot` constant, shared `expectOutsideFolderResolves(as:namedBy:)`, `relativePathOutsidePlacesResolvesToFolder` over `FolderKind.allCases`), Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoWriteTests.swift (shared `makeOutsideFolder(as:in:)`, `expectAddTaskWritesOutsideFolder(as:namedBy:)`, `files(inFolderAt:)`; `relativePathWritesFolderFromRoot` over `FolderKind.allCases`; new `pathRefWritesOnlyBoardDirectory` over `FolderKind.allCases` that compares path and contents of each file outside `<folder>/.kanban/` before and after with exact equality). Filtered run: 9 tests in 3 suites passed. Full `swift test`: 1116 tests in 80 suites passed; only the accepted SwiftPM "missing creator" warning.
    - note: the write path already writes only under `<folder>/.kanban/` (all writes go through `EventLog`), so no code change on the write path was necessary. The new tests are coverage of behavior that exists, so they passed on the first run.
    - next: /review
  timestamp: 2026-10-09T21:00:28.866165+00:00
- actor: claude-code
  id: 01m4h7m0x1nz2s1j7ef064vb99
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 4 files
    - test: green — swift test, 1116 tests in 80 suites passed
    - commit: b0880a1
    - review: clean — 0 findings
  timestamp: 2026-10-09T21:03:04.097315+00:00
depends_on:
- 01M4G9Z14EEZ85ZSRQHFV1DCQ3
position_column: done
position_ordinal: db80
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

## Review Findings (2026-10-09 15:52)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 6 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift:102` `reuse/reuse` — The new private helper isFolder rebuilds a directory check with url.resourceValues(forKeys: [.isDirectoryKey]). The standard library already gives this check: FileManager.default.fileExists(atPath:isDirectory:). The helper adds a second way to test for a folder in this file, and the code base already uses FileManager.default.fileExists for existence checks (EventLog.swift:144, EventLog.swift:159, BoardLocator.swift:133, BoardLocator.swift:231). Using the standard call keeps one pattern. Replace the body of isFolder with a call to FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) and return true only when the call returns true and isDirectory is true. Or inline the call at the one use site in resolution(ofFolderAt:readingKeysWith:) and remove the helper.
- [x] `Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift:282` `code-security/injection` — Path traversal: `directory(ofPath:currentRoot:)` joins a board ref that starts with `./` or `../` onto the repo root with no containment check, so `..` segments can point outside the repo. The same ref can also be an absolute or `~` path (line 288) with no check. Because `resolution(ofFolderAt:)` and `addTask` then read keys and write `.kanban` logs in the resolved folder, an LLM-supplied or otherwise untrusted board ref can make the tool read or write under any directory the process can reach. If arbitrary folders are intended (plan.md §6.6), state that as an explicit trust decision and restrict the write path, for example by requiring the target to be a git repo or to already hold `.kanban/board.jsonl` before any write. If the scope must stay inside the repo or the search roots, canonicalize the result with `canonicalPath` and reject it when it does not have the root or a search root as its prefix.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoWriteTests.swift:278` `completeness/inverse-operation-coverage` — The relative-path write test covers only a plain folder. The absolute-path write test (pathOutsidePlacesWritesFolder) runs for both FolderKind.gitRepo and FolderKind.plainFolder, but a ../ path to a git repo folder is never written. The key of a git repo reached by a relative path (origin, not local/<name>) is therefore unproven. Parameterize relativePathWritesFolderFromRoot over CrossRepoFixture.FolderKind.allCases, using kind.makeFolder and kind.key(ofFolderNamed:origin:), and add the same kind loop to relativePathOutsidePlacesResolvesToFolder in BoardLocatorTests.swift.
