---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4x9t07zcjyzshmpnbyjpbbn
  text: |-
    Research done. Findings:
    - KanbanGraph keeps `root` (the working directory given to init) and uses it in about 15 places: the key read, the watcher, the session path key, the scan places, and the path refs. Each use runs after the first load. The plan: resolve the worktree top in `loadedSession()`, keep it in `LoadState.loaded`, and pass the current board as a `BoardCopy` (top + key) where the code passed only `currentKey`.
    - The tests use a fake key reader in temp folders that are not git repos (KanbanGraphTests.makeGraph). Thus the top read needs its own seam: a `WorktreeTopReader` beside `BoardKeyReader`. The test fixture gives an identity fake; GitGraphFixture gives the real `BoardKey.worktreeTop(of:)`.
    - `git rev-parse --show-toplevel` gives the real path (`/private/var/...`), but GitSandbox paths are `/var/...`. To keep `board { path }` the same, the top keeps the spelling of the working directory: walk up the working directory to the ancestor whose canonical path is the top.
    - NOT_A_REPO must come out as a response error, so `BoardKeyError.notARepo(path:)` maps to a new `KanbanError.notARepo(path:)` (code `NOT_A_REPO`). A path ref outside git gets a new `BoardResolution.notARepo(path:)`, so the field gets the error, the same as NOT_FOUND.
    - Files that need a change beyond the card list: README.md (example 1 says a folder does not have to be a git repo), ReadmeExamplesTests (runs the README in a plain folder), KanbanGraphTests.boardInPlainFolder, CrossRepoReadTests.pathOutsidePlacesReadsFolder.
    - Keep `local/<main-clone-name>` for a repo with no remote (the card note: M7 + M8 is a separate task). Rename `BoardKey.init(localDirectoryName:)` to `init(mainCloneName:)` so that no code makes a key from any folder name.
  timestamp: 2026-10-14T13:32:10.367842+00:00
- actor: claude-code
  id: 01m4xaxxjqf9ba1ks81pd9h26s
  text: |-
    Implementation landed. Decisions and facts for the next agent:
    - New `BoardKeyError.notARepo(path:)` and `KanbanError.notARepo(path:)` (code `NOT_A_REPO`, message "The kanban needs a git repo. `<path>` is not in a git repo."). The engine maps the first to the second in `KanbanGraph.worktreeTop()`, so each call gives an error response, not a thrown fault.
    - New `BoardKey.worktreeTop(of:)` and seam `WorktreeTopReader`. The top keeps the path spelling of the working directory (walk up to the ancestor whose canonical path equals the git path), so `board { path }` does not change to `/private/var/...`.
    - `KanbanGraph` keeps `workingDirectory`; `LoadState.loaded(CurrentBoard)` holds the session and the top folder. Functions that took `currentKey:` now take `current: BoardCopy`.
    - Path refs: `BoardLocator.resolution(ofFolderAt:...findingTopsWith:)` gives the board at the worktree top; a folder outside git gives the new `BoardResolution.notARepo(path:)`, and the field fails with NOT_A_REPO (same shape as NOT_FOUND).
    - Scan candidates need a `.git` entry. `Git.programNotFoundStatus` was removed: git not installed is now a git failure (G4), not "no repo".
    - `BoardKey.init(localDirectoryName:)` renamed to `init(mainCloneName:)`; the `local/<main-clone-name>` key for a repo with no remote stays until M7/M8 (^yd33ytsb task).
    - README example 1 text and ReadmeExamplesTests now use a git repo (`git init` in `ExampleBoard`, init is async).
    - Process note: test edits and production edits were applied by two helpers at the same time, so no separate RED build run was recorded; the new tests named APIs that did not exist before (`worktreeTop`, `notARepo`, `mainCloneName`, `findingTopWith`).
    - No ARCHITECTURE.md in the repo.
  timestamp: 2026-10-14T13:51:47.287994+00:00
- actor: claude-code
  id: 01m4xaxzaggwyhrq29d78ce3aw
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` clean (no new warnings); `swift test` 1146 tests in 83 suites passed. 6 source files (BoardKey, BoardLocator, RelatedBoards, Errors, Schema, KanbanGraph), README.md, 12 test files changed, 1 new test file Tests/FoundationModelsKanbanTests/Tool/RepoBoardTests.swift.
    - next: /review
  timestamp: 2026-10-14T13:51:49.072907+00:00
position_column: doing
position_ordinal: '80'
title: Put the board only in a git repo, at the worktree top
---
## What
divergence.md §16, the final decision after M5, and the final M6 decision. The user: "`.kanban` is always repo top — there is no such thing as a kanban without a repo — remove all the 'local kanban' complexity." This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Decided behavior:
- The board of a working directory is `<worktree top>/.kanban/`. Get the worktree top with `git rev-parse --show-toplevel` in the working directory. In the main clone, this is the top folder of the main clone. In a linked worktree, it is the top folder of that worktree. A bare repo works: each worktree has its own top folder.
- Each worktree has its own board, on its own branch. Boards join only when the branches merge (union merge of the log lines). All worktrees of one repo have the same key. A URI with that key, in a session of that repo, names the current board of the session. From a different repo, it names the first copy in scan order.
- A working directory that is not in a git repo has no board. Each kanban call gives a new error code `NOT_A_REPO` with the message: "The kanban needs a git repo. `<path>` is not in a git repo."
- A `.kanban/` in a subfolder of a repo is ignored. Do not read it and do not make one.
- G4: a git failure stops the board from opening. This is now correct, because there is no `local/` fallback for a folder outside git.

Remove:
- Boards in folders that are not git repos, and the locator code that finds them (commit `afca516`, task `^fv1dcq3`; S/CrossRepo/BoardLocator.swift).
- The key `local/<folder-name>` for a folder outside git and for a subfolder of a repo (S/Identity/BoardKey.swift, task `^j47qcme` "BoardKey: a board works in any folder, git is not required").
- A `board:` path to any folder (commit `107ffed`, task `^8dy1xz2`). Keep the path forms (`/`, `~`, `./`, `../`, relative to the current root), but a path must be inside a git repo. It names the board at the worktree top of that path. A path that is not in a git repo gives `NOT_A_REPO`. A path that does not exist gives `NOT_FOUND`.

Note: the key of a repo with no `origin` remote, and a repo with no commit, are in a separate task (M7 + M8). In this task, keep the current key for a git repo with no remote until that task is done.

## Acceptance Criteria
- [ ] A working directory in a subfolder of a repo uses `<repo top>/.kanban/`.
- [ ] A `.kanban/` in a subfolder is not used.
- [ ] A working directory that is not in a git repo gives `NOT_A_REPO` on each kanban call, with the message above.
- [ ] A working directory in a linked worktree uses `<worktree top>/.kanban/`, not the board of the main clone.
- [ ] `board: "<path in a git repo>"` names the board at the worktree top of that path.
- [ ] `board: "<path outside git>"` gives `NOT_A_REPO`.
- [ ] The locator does not find or key a folder that is not a git repo. No code makes a `local/<folder-name>` key.

## Tests
- [ ] A session in a subfolder uses the repo board.
- [ ] A `.kanban/` in a subfolder is not used.
- [ ] A folder outside git gives `NOT_A_REPO`.
- [ ] A session in a worktree uses the worktree board. Two worktrees have the same key.
- [ ] Change the tests that the commits `afca516` and `107ffed` added (T/CrossRepo/BoardLocatorTests.swift, T/CrossRepo/CrossRepoWriteTests.swift `FolderKind.plainFolder` cases) so that a plain folder gives `NOT_A_REPO` or is not found.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.