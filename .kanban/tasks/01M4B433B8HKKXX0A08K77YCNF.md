---
depends_on:
- 01M4B421JA8K0E8GAC3EMWCZ5Z
- 01M4B4002GZV6E43G5CQ74BJNZ
position_column: todo
position_ordinal: a680
title: 'Cross-repo writes: board field, enable, multi-board commit'
---
## What
Change related boards in one call. The basis is plan.md §6.6 and §5.4 (multi-board locks). The cross-board cycle check and cross-board undo are in a separate task.
- The optional `board` field on `initBoard`, `updateBoard`, `addTask`, `addColumn`, `addActor`, `addTag`, `renameTag`. A mutation on an existing node finds its board from the node.
- Enable a related repo: the first mutation on a repo with no `.kanban/` initializes its board (auto-init). A query on such a repo writes nothing.
- One call, many boards: one `txn`; each patch records the keys of the other boards in `boards`; locks in key order; the session actor rule in each board; a patch in board A that points to board B holds the full URI of the node with the current key of B.

## Acceptance Criteria
- [ ] `addTask(board: "<related>")` writes to the related log; a related repo with no `.kanban/` gets a board on its first mutation.
- [ ] One call that changes two boards writes one `txn` to both, and each patch has the key of the other board in `boards`.
- [ ] A `dependsOn` edge from board A to board B is stored as a full URI with the key of B; no log line has the key of its own board.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoWriteTests.swift`, with two temporary git repos side by side.
- [ ] Run `swift test --filter CrossRepoWriteTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.