---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4h532mcwf6hhsf72zkbvb6x
  text: |-
    Research:
    - `BoardKey.read(fromRepoAt:)` runs `git config --get remote.origin.url`, then `git rev-parse --git-common-dir`. Callers: `KanbanGraph.init(root:actor:...)`, `GitGraphFixture.makeGraph`, `BoardLocatorTests`, `PortabilityTests`. `BoardLocator` gives only top-level repo folders (folders with a `.git` entry) to the key reader, so the new rules do not change the keys that the locator reads.
    - `BoardLocator.key(ofRepoAt:)` must still get `gitCancelled` to stop a scan. Thus the new read must not catch a cancel or a time-out. It catches only `gitUnavailable` (git cannot start) and a failure status of `git rev-parse`.
    - Two existing tests state the old rules and must change: `subdirectoryGivesKeyOfRepo` (now `local/<subfolder-name>`) and `directoryOutsideRepoThrows` (now `local/<folder-name>`). `engineOutsideRepoThrows` changes to expect success.
    - Plan: one `git rev-parse --path-format=absolute --show-toplevel --git-common-dir` call gives the top-level folder and the common git folder. When the top-level folder is not `root` (canonical paths), the key is `local/<folder-name>`. An `origin` that `BoardKey(remoteURL:)` refuses gives `local/<main-clone-name>`.
  timestamp: 2026-10-09T20:18:51.660968+00:00
- actor: claude-code
  id: 01m4h5cmw7pw5y16vbqj41fttw
  text: |-
    Implementation landed.
    - RED: 6 new or changed BoardKeyTests cases and `KanbanGraphTests.boardInPlainFolder` failed with `gitFailed` (not a git repo) and `invalidRemoteURL` (local origin). The subfolder case gave the repo key.
    - GREEN: `BoardKey.read` now runs one `git rev-parse --path-format=absolute --show-toplevel --git-common-dir`. A failure status of git (not a repo, or git not installed: `/usr/bin/env` exits 127) or `gitUnavailable` gives `local/<folder-name>`. When the top-level path (canonical) is not `root`, the key is `local/<folder-name>`. An `origin` that `BoardKey(remoteURL:)` refuses gives `local/<main-clone-name>`. A time-out and a cancel still throw, so `BoardLocator` still stops on a cancel.
    - Choice for an open rule: each `origin` that gives no key (no host, and also a host with no path) gives `local/<main-clone-name>`. This is closest to plan.md "a repo without a remote uses local/<directory-name>".
    - Changed old tests that stated the old rules: `subdirectoryGivesKeyOfRepo` (now `local/Sources`), `directoryOutsideRepoThrows` (now `local/plain-directory`), `engineOutsideRepoThrows` (now `engineOutsideRepoGivesLocalKey`, success with `local/<folder-name>`). Removed the unused `isGitFailure` helper.
    - Docs: `KanbanGraph` type doc, `root` property doc, and both `init` docs say "The folder of the board". plan.md §2.1, §3.1 diagram, §3.2, §12 items 1 and 4 updated. §3.1 and §12 item 1 also said "one board per repo", so they changed too, to stay true.
    - BoardLocator.repos(in:) is not changed (^fv1dcq3).
  timestamp: 2026-10-09T20:24:05.255509+00:00
- actor: claude-code
  id: 01m4h5cqnbs02v08yqvyp5k0v9
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/Identity/BoardKey.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift, plan.md. `swift test`: 1100 tests in 80 suites passed, 0 failures. The only build warning is the accepted SwiftPM "missing creator for mutated node".
    - next: /review
  timestamp: 2026-10-09T20:24:08.107348+00:00
depends_on:
- 01M4G9GXTJSANGYS1315NRZSQH
- 01M4G9GQ28QA3Z7MYQG9JE3H3Z
position_column: doing
position_ordinal: '80'
title: 'BoardKey: a board works in any folder, git is not required'
---
## What
The owner decided that git is not required. `KanbanGraph(root:)` must open and make a board in any folder. Now `BoardKey.read(fromRepoAt:)` (`Sources/FoundationModelsKanban/Identity/BoardKey.swift:128-133`) runs `git config` and `git rev-parse`, and a folder that is not in a git repo throws `gitFailed`. A remote `origin` that is a local path (`/srv/git/repo.git`, `../upstream`, `file:///…`) throws `invalidRemoteURL` (`BoardKey.swift:49-57`, `:128-133`).

This task changes only the board key. The task ^fv1dcq3 ("BoardLocator finds boards in folders that are not git repos") changes the locator. This task runs after ^9je3h3z, because both tasks change `Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift`.

Rules for `BoardKey.read`:
- When `root` is the git top-level directory (or the root of a worktree), the key comes from git, as now.
- When `root` is not in a git repo, or git is not installed, the key is `local/<folder-name>`. `<folder-name>` is the last path component of `root`.
- When `root` is a subfolder of a git repo (not its top-level directory), the key is `local/<folder-name>`. Thus two boards in one repo never have the same key.
- When `origin` has no host (a local path or `file://`), the key is `local/<main-clone-name>` (the same as a repo with no remote).
- `.kanban/` stays at `<root>/.kanban/`. `root` is the folder that the caller gives. Do not search up for a git top-level directory.

Other changes:
- The doc comment of `KanbanGraph.init`: change "The root directory of the repo" to "The folder of the board".
- Update plan.md: §2.1 (`Board` = the board of one folder; a git repo is one case), §3.2, §12 item 4. Say that a folder that is not a git repo, or a subfolder of a git repo, gets `local/<folder-name>`.

## Acceptance Criteria
- [x] `KanbanGraph(root: <temp folder with no .git>)` + `addTask` makes `<root>/.kanban/` and returns a task id with the key `local/<folder-name>`.
- [x] `KanbanGraph(root: <subfolder of a git repo>)` gives the key `local/<subfolder-name>`, not the key of the repo.
- [x] A repo whose `origin` is a local path opens with the key `local/<main-clone-name>`.
- [x] Each existing git test still passes.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift`: no repo, a subfolder of a git repo, and a local-path `origin`.
- [x] `Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift`: open a board in a plain temp folder and run a mutation and a query.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.