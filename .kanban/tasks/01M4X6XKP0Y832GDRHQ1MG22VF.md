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
- actor: claude-code
  id: 01m4xd3gpexjph81m9zac971xx
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (cc3cad9): 4 findings (4 confirmed, 7 refuted) — Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoWriteTests.swift:339, Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift:241, Tests/FoundationModelsKanbanTests/WatcherBudget.swift:12, Tests/FoundationModelsKanbanTests/WatcherBudget.swift:45
    - next: implement the 4 open items in the "Review Findings (2026-10-14 09:11)" section, then commit and review again.
  timestamp: 2026-10-14T14:29:47.854330+00:00
- actor: claude-code
  id: 01m4xd406kqtyva9202n27xce7
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 6 source files, README.md, 13 test files
    - test: green — swift test, 1148 passed, 0 failed, 0 skipped (WatcherBudget test trait added for the FSEvents stream limit)
    - commit: cc3cad9
    - review: findings — Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoWriteTests.swift:339, Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift:241, Tests/FoundationModelsKanbanTests/WatcherBudget.swift:12, Tests/FoundationModelsKanbanTests/WatcherBudget.swift:45
  timestamp: 2026-10-14T14:30:03.731861+00:00
- actor: claude-code
  id: 01m4xdkcjqrwqrk6c3143dn9p4
  text: |-
    Review findings (2026-10-14 09:11) fixed:
    - reuse/reuse: `SerialGate` now takes `init(slots: Int = serialSlots)` (a count of free slots, not a busy flag). The run label changed from `run(serially:)` to `run(inSlot:)`; the 3 engine callers use a trailing closure and need no change. `WatcherBudget` is now an `enum` namespace that holds `static let shared = SerialGate(slots: slotCount)`. The parallel acquire/release queue is gone.
    - magic-numbers-swift: `WatcherBudget.slotCount = 16`. The literals in WatcherBudgetTests (2, 12, 20, 7) are named constants too. WatcherBudgetTests now tests `SerialGate(slots:)` (RED: compile failure "argument passed to call that takes no arguments", then GREEN).
    - duplication: new `CrossRepoWriteTests.expectFailure(of:named:in:giving:coded:)` and `expectAddTaskFailure(naming:in:giving:coded:)`. `pathOutsideGitGivesNotARepo`, `missingFolderPathGivesNotFound` and `missingBoardGivesNotFound` call them; each keeps its own trailing check.
    - invariant-propagation: BoardKeyTests engine tests now iterate `localOrigins`, and add `engineInSubfolderGivesKeyOfRepo` (over `subfolderOrigins`) and `engineOutsideRepoGivesNotARepo`. `keyResponse(ofEngineAt:)` now calls `RepoBoardTests.respond(to:inWorkingDirectory:)` and does not copy it. These tests passed on the first run, because the behavior already existed. They are coverage for the engine path.
  timestamp: 2026-10-14T14:38:27.927424+00:00
- actor: claude-code
  id: 01m4xdkexdrzm9h1rhy1ahxj1h
  text: |-
    ### implement — changed
    - evidence: `swift test` 1150 tests in 84 suites passed, no compiler warnings (only the accepted "missing creator" line). 5 files: Sources/FoundationModelsKanban/Tool/KanbanGraph.swift (SerialGate slots), Tests/FoundationModelsKanbanTests/WatcherBudget.swift, Tests/FoundationModelsKanbanTests/WatcherBudgetTests.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoWriteTests.swift, Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift. All 4 findings checked.
    - next: /review
  timestamp: 2026-10-14T14:38:30.317684+00:00
- actor: claude-code
  id: 01m4xdxx8qsph96qapgy0p2759
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (8cfa570). 0 findings, 0 confirmed, 1 refuted, 7 attempted. 5 files reviewed. 2 .kanban/ files are ignored by .reviewignore. All 4 prior findings are checked.
    - next: none. The task is in done.
  timestamp: 2026-10-14T14:44:12.695987+00:00
- actor: claude-code
  id: 01m4xdy69051kzw36wb6pj69zs
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 5 files (4 findings fixed)
    - test: green — swift test, 1150 passed, 0 failed, 0 skipped
    - commit: 8cfa570
    - review: clean — task moved to done
  timestamp: 2026-10-14T14:44:21.920276+00:00
position_column: done
position_ordinal: de80
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

## Review Findings (2026-10-14 09:11)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 54 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoWriteTests.swift:339` `duplication/duplication` — The new test pathOutsideGitGivesNotARepo repeats the scaffold of missingFolderPathGivesNotFound. Both make the repos, build a field with Self.boardField(path), run CommentTests.run on the app graph, build a KanbanError expected value, and call ErrorCoverageTests.expectFailure with MutationName.addTask. Copies of this scaffold drift apart. A change to the field shape or the failure check must then be made in two places. Extract one helper in CrossRepoWriteTests that takes the path reference and the expected KanbanError, runs the addTask field on the app graph, and checks the failure. Call it from pathOutsideGitGivesNotARepo and from missingFolderPathGivesNotFound. Keep the trailing checks (hasBoardDirectory, fileExists) in each test, since they differ.
- [x] `Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift:241` `completeness/invariant-propagation` — The change removed the engine-level tests for a folder outside a repo, for a subfolder engine, and for an engine with no repo. The engine path now reaches the new notARepo and worktree-top rules through `KanbanGraphTests.keyResponse(of:)`, but the only engine test left is the local-origin case at line 241. A regression in how the engine handles a folder outside a repo, or a subfolder, would pass this file. The engine test also uses only `Self.localOrigins.first`, so the other local origins never reach the engine. Add an engine test for a folder outside a repo (expecting the notARepo error from the engine's read) and one for a subfolder of a repo. Iterate over `Self.localOrigins` in the engine test, as the non-engine test at line 198 does.
- [x] `Tests/FoundationModelsKanbanTests/WatcherBudget.swift:12` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Tests/FoundationModelsKanbanTests/WatcherBudget.swift:45` `reuse/reuse` — acquire and release rebuild the wait-queue of SerialGate, which already holds a busy flag, a FIFO list of checked continuations, and an enter and leave pair. This is a near-match that was copied, not extended. Parameterize SerialGate by its slot count instead of writing a parallel counting queue. Then WatcherBudget becomes an instance of the existing gate with more than one slot.
