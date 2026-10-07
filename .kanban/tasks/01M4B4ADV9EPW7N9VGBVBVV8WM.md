---
depends_on:
- 01M4B3XHRVFA2YDCJC76MAFQR5
- 01M4B3X08THVXHAJEQ4Z8PDB4H
position_column: todo
position_ordinal: ab80
title: 'Live graph: apply changed files to the graph'
---
## What
Update a loaded `Graph` from a list of changed log files. The commit check and the watcher both use this. The basis is plan.md §5.6 (Apply a batch, Large changes, A line that does not parse).
- `Sources/FoundationModelsKanban/Observe/LiveGraph.swift`: `apply(changedPaths:)` on a board graph, with the loader work queue and the stage order (board, actors, columns, tags, tasks, comments).
  - Changed file: read and fold the node again from the start; replace the state in its slot.
  - New file: make a new slot; resolve waiting edges to it.
  - Removed file: remove the node; edges to it become unresolved.
- After the stages: join again, update the global event list (add new event ids, remove gone ids), and record the new file signatures. Return the new event ids, so that a caller can make `Change` values.
- More than half of the files of the board changed: do a full reload with the loader.

## Acceptance Criteria
- [ ] After each case (changed, new, removed file, many files), the graph equals a fresh load of the same files.
- [ ] A new file resolves an edge that pointed to it; a removed file makes the edge unresolved.
- [ ] A line that does not parse is skipped, and the other lines still apply.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Observe/LiveGraphApplyTests.swift`: change files on disk directly, call `apply`, compare with a fresh load.
- [ ] Run `swift test --filter LiveGraphApplyTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.