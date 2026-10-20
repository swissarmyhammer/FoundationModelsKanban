---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5be2cewg18ebkxm55twrsta
  text: |-
    ### finish iteration 1 — stuck
    - implement: not run — the task needs a decision by a person before work can start (see "Decision needed": rewrite the merged lists, ignore `board` in the check, or merge the source board log lines; each changes a recorded decision)
    - next: a person chooses one option and records it in divergence.md, then `/finish ^16js6jx`
  timestamp: 2026-10-20T01:16:01.372039+00:00
position_column: todo
position_ordinal: '80'
title: Merged collectBoards lines are held after a fresh load when their source transaction also wrote the source board log
---
## What
Found during ^ye4xk09. `collectBoards` does not merge the board log of a source (`S/CrossRepo/BoardCollect.swift`, divergence.md M9). The first transaction of a source board (auto-init and `addTask`) writes `board` and the node logs. Its lines name `board` in their `files` list (divergence.md Q23), and they keep this list when they are merged into the target (Q23 "Changed (2026-10-19)").

The target board log has no line of that source transaction. So a fresh load of the target (`BoardLoader.load`) holds all merged lines of that transaction: the columns, the task, and the actor of the source. The live graph after the call shows them, because `LiveGraph.adopt` applies the written events with no check. After a restart, the tasks are not on the board.

The old count check had the same problem: the count named 7 files, and the target holds 6 of them.

## Reproduce
`CollectBoardsTests` fixture: collect the two sources, then `BoardLoader(reading: EventLog(repositoryAt: target)).load()`. `heldEvents` holds the merged `addTask` lines of each source. The test `collectTransactionListsOnlyItsFiles` checks only the collect transaction for this reason.

## Decision needed
A person must choose the fix, because each option changes a recorded decision:
- `collectBoards` rewrites the list of each merged line to drop the refs that it does not merge (`board`). This changes "merged lines keep their own list".
- The transaction check ignores `board` in the list of a line in a different file. This weakens the crash check of the board log.
- `collectBoards` merges the lines of the source board log that belong to a merged transaction. This changes M9.

## Acceptance Criteria
- [ ] After `collectBoards` and a fresh load of the target, no merged line is held.
- [ ] Tests use temporary folders only.