---
assignees:
- claude-code
position_column: todo
position_ordinal: '8580'
title: 'Commit: no partial transaction on disk when an append fails'
---
## What
`Sources/FoundationModelsKanban/Tool/Commit.swift:536-538` and `:627-629` append one node file at a time, and then one board at a time. If an append throws after an earlier append succeeded, the call returns an error, but the earlier lines stay in the logs. plan.md §5.4 steps 5.3–5.5 describe an all-or-nothing commit.

Also, `append(recording:changing:)` in `Sources/FoundationModelsKanban/Tool/Commit.swift` calls `live.adopt` for each board in turn. Thus when the append of board 2 fails, board 1 is already adopted into its live graph.

- Before the first append, record the size of each file that the commit will append to (for a new file, record that it did not exist).
- If an append fails, truncate each changed file back to its size, and remove each new file, for each board. Do this while the locks are still held. Then throw the original error.
- Change `append(recording:changing:)` so that no board is adopted (`live.adopt`) until all appends of all boards succeed.
- The live graph and the signatures must not change when the commit fails.
- Make the append step testable: inject a file writer (or a fault hook) into the commit path, so that a test can make the Nth append fail.
- Update plan.md §5.4 to describe the rollback.

## Acceptance Criteria
- [ ] When the second append of a cross-board transaction fails, no file of either board changes, and the call returns an error.
- [ ] After a failure on board 2, the live graph of board 1 is unchanged.
- [ ] When an append to a new node file fails, the file does not exist after the call.
- [ ] The next call works normally and sees no part of the failed transaction.

## Tests
- [ ] A test in `Tests/FoundationModelsKanbanTests/Tool/` (for example `CommitRollbackTests.swift`) with a fault-injecting writer, for one board and for two boards.
- [ ] A two-board test: the append of board 2 fails, then a query of board 1 gives the same result as before the call.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.