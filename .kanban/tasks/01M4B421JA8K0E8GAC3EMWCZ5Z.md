---
depends_on:
- 01M4B3VKJ8W42AXVFVMH6WN5VQ
- 01M4B3YYXT069TKADQ93CBAA93
- 01M4B406Z7RVSBJKKJ8KJW0CY2
- 01M4B41VDXZ3NKEG4554PVXWQN
position_column: todo
position_ordinal: a280
title: 'Cross-repo: BoardLocator and board refs'
---
## What
Find related boards on the disk and read them. The basis is plan.md §6.6 and §12 items 13 and 26.
- Add the `locator: BoardLocator = .default` parameter (the extra search roots) to `KanbanGraph.init`.
- `Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift`: scan the parent directory of the current repo (one level down) and the configured search roots for git repos. For each: key from the current `origin`; enabled if `.kanban/board.jsonl` exists. Index: key → list of directories. Scan one more time on an unknown key.
- Many copies of one key: the current key resolves to the current directory; a different key resolves to the first copy in scan order (parent directory first, then each search root in config order, then directory names in sort order). A path in `board` selects a copy.
- Board refs for `Query.board(id:)`: a key, a unique repo directory name, or a path. `Query.boards(enabled:)` lists each copy with its path; a board that is not enabled shows the directory name.
- Read across boards: `node(id:)` with a URI of a related board, and a cross-board `dependsOn` target, load that board. A loaded related board stays live and gets its own watcher. A target in a board that is not found counts as not done.

## Acceptance Criteria
- [ ] Two temporary repos side by side: a task in one depends on a task in the other, and `ready` changes after the other task is completed (by `completeTask` in the same process, and by a write from a second process).
- [ ] Two copies of one repo: the current key gives the current directory; a related key gives the first copy on each call; a path selects the other copy; `boards` lists both.
- [ ] A board that cannot be found gives `NOT_FOUND` with the search roots in the message.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift` and `CrossRepoReadTests.swift`, with temporary git repos and worktrees.
- [ ] Run `swift test --filter BoardLocatorTests` and `--filter CrossRepoReadTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.