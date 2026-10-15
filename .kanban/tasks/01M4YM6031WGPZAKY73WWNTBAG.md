---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m50yg7trjf4pjweyz08sdega
  text: |-
    Research and implementation notes:
    - Cause confirmed. With a worktree of the current repo as the second board, the events of the call have `boards: nil`, because the key of the second copy is the same as the key of the event's own board. So `boards(of:foundIn:among:)` got no key and reversed only the home board.
    - Fix: `boards(of:foundIn:among:)` now puts `key(of: home)` first in the key list, then the keys of the `boards` value. `copies(ofKey:holding:among:)` then looks in the scan, the host table, and the `boards` input for the home key. The home board always holds the txn, so this key never gives `transactionBoardNotLoaded`. `eachOnce` removes the home board when the scan gives it again.
    - Cost: an undo of a single-board txn now also asks `loadedTargets(withKey:)` for the home key. The first time, that can record a `.loadedCopies` request and make the call run again after the read. All 1540 tests pass with this.
    - RED: the new test `CrossRepoCopyUndoTests/undoReversesWorktreeOfCurrentRepo` failed. The worktree task kept its `addTask` event, and the two newest events had 2 different txns. GREEN after the fix.
    - Test helper: I moved the two expectations of `expectUndone` into the new `expectOneUndo(of:wrote:)`, so that the new test uses them and does not copy them.
    - divergence.md X5: added the sub-bullet "Second copy of the home board (closed by ^wwntbag)". plan.md was not changed.
  timestamp: 2026-10-15T23:31:33.848022+00:00
- actor: claude-code
  id: 01m50ygcamqkgfhh14c015tgq9
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/GraphQL/UndoMutations.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCopyUndoTests.swift, divergence.md. RED then GREEN on `swift test --filter CrossRepoCopyUndoTests/undoReversesWorktreeOfCurrentRepo`. Full `swift test`: 1540 tests in 122 suites passed. The only build warning is the accepted mlx "missing creator" warning.
    - next: /review
  timestamp: 2026-10-15T23:31:38.452263+00:00
- actor: claude-code
  id: 01m50yqtz5jg55hg9n3e2p12mq
  text: |-
    ### test — green
    - evidence: swift build complete, 1 warning (allowed SwiftPM "missing creator"). swift test: 1540 tests in 122 suites passed, 0 failures, 0 skipped, no time-limit failures, first run. IntegrationTests with scratch path integration-build: 3 tests in 3 suites passed, 0 failures.
    - next: review
  timestamp: 2026-10-15T23:35:42.821846+00:00
- actor: claude-code
  id: 01m50yrh5mhfh9fgpm0pwhp8wc
  text: |-
    ### commit — changed
    - evidence: local commit "fix(undo): reverse a second copy of the home board in one undo (^wwntbag)". Files: Sources/FoundationModelsKanban/GraphQL/UndoMutations.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCopyUndoTests.swift, divergence.md, and the changed .kanban/tasks files. The sha is in the step block of the caller, because a comment cannot hold its own sha. Not pushed.
    - next: none
  timestamp: 2026-10-15T23:36:05.556189+00:00
position_column: doing
position_ordinal: '80'
title: 'Undo: find a second copy with the key of the home board in the same transaction'
---
## What
Found during ^14fa5z2. The `boards` value of an event holds only the keys of the other boards: the key of its own board is removed (S/Tool/Commit.swift `Event.recording(operations:changing:inBoard:)`). When one transaction writes two copies (worktrees) of the same repo, and the undo finds the transaction first in one of these copies (the home board), the other copy with the same key is not in `boards`. Then `BoardStore.boards(of:foundIn:among:)` in S/GraphQL/UndoMutations.swift does not look for it, and the undo reverses only part of the transaction.

## Change
- [x] Also look for the key of the home board in the host table and in the `boards` input, and reverse each other copy with that key that holds events of the txn.

## Tests
- [x] A transaction that writes the current board and a second worktree of the current repo is reversed on both by one `undo`.
- [x] Tests use temporary fixture folders, never the `.kanban/` of this repo.
- [x] `swift test` passes.