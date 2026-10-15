---
assignees:
- claude-code
position_column: todo
position_ordinal: ae80
title: 'Undo: find a second copy with the key of the home board in the same transaction'
---
## What
Found during ^14fa5z2. The `boards` value of an event holds only the keys of the other boards: the key of its own board is removed (S/Tool/Commit.swift `Event.recording(operations:changing:inBoard:)`). When one transaction writes two copies (worktrees) of the same repo, and the undo finds the transaction first in one of these copies (the home board), the other copy with the same key is not in `boards`. Then `BoardStore.boards(of:foundIn:among:)` in S/GraphQL/UndoMutations.swift does not look for it, and the undo reverses only part of the transaction.

## Change
- Also look for the key of the home board in the host table and in the `boards` input, and reverse each other copy with that key that holds events of the txn.

## Tests
- [ ] A transaction that writes the current board and a second worktree of the current repo is reversed on both by one `undo`.
- [ ] Tests use temporary fixture folders, never the `.kanban/` of this repo.
- [ ] `swift test` passes.