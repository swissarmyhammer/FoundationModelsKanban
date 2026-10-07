---
depends_on:
- 01M4B3ZDK527CRVKQQRT87RGHJ
- 01M4B4ADV9EPW7N9VGBVBVV8WM
- 01M4B4180ZBKH8RSE3FA9REHS7
position_column: todo
position_ordinal: a180
title: 'Live graph: FSEvents watcher and batches'
---
## What
The FSEvents watcher that drives the live graph. The basis is plan.md §5.6 and §12 item 25. Applying the changed files is in the separate task "Live graph: apply changed files to the graph".
- `Sources/FoundationModelsKanban/Observe/BoardWatcher.swift`: an FSEvents stream with file-level events on `.kanban/` of each loaded board, for the life of `KanbanGraph`. Each board that `KanbanGraph` loads (the current board and each related board) gets its own watcher.
- A repo with no `.kanban/` yet: watch the repo directory until `.kanban/` appears, then load the board and move the watcher to `.kanban/`.
- Batches: the changed paths of one FSEvents group go to the serial gate as one batch, and `LiveGraph.apply` runs inside the gate. Ignore a file whose signature equals the recorded signature (own writes, repeated events). After a batch, update the searcher of the board.
- `KanbanGraph.close()`: stop all watchers.

## Acceptance Criteria
- [ ] With no subscriber, a manual edit of a task log changes the result of a later query (wait for the batch with an async expectation and a timeout).
- [ ] The tool's own write makes no `apply` call (a test counter on `apply`).
- [ ] A `.kanban/` directory that appears after the first call is loaded and watched; after `close()`, a file change makes no `apply` call.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Observe/BoardWatcherTests.swift`.
- [ ] Run `swift test --filter BoardWatcherTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.