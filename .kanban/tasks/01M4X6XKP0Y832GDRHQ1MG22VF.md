---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
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