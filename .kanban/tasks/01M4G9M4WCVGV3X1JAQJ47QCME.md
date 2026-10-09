---
assignees:
- claude-code
depends_on:
- 01M4G9GXTJSANGYS1315NRZSQH
- 01M4G9GQ28QA3Z7MYQG9JE3H3Z
position_column: todo
position_ordinal: '9380'
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
- [ ] `KanbanGraph(root: <temp folder with no .git>)` + `addTask` makes `<root>/.kanban/` and returns a task id with the key `local/<folder-name>`.
- [ ] `KanbanGraph(root: <subfolder of a git repo>)` gives the key `local/<subfolder-name>`, not the key of the repo.
- [ ] A repo whose `origin` is a local path opens with the key `local/<main-clone-name>`.
- [ ] Each existing git test still passes.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift`: no repo, a subfolder of a git repo, and a local-path `origin`.
- [ ] `Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift`: open a board in a plain temp folder and run a mutation and a query.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.