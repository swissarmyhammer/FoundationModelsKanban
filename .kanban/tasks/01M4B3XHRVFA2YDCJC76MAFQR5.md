---
depends_on:
- 01M4B3XB2P4CK66JYADZWD88DR
- 01M4B3X08THVXHAJEQ4Z8PDB4H
position_column: todo
position_ordinal: '8e80'
title: 'Parallel loader: stages, work queue, join'
---
## What
Load one board from disk into a `Graph`. The basis is plan.md §5.3 (The parallel loader) and §12 item 23.
- `Sources/FoundationModelsKanban/Events/Loader.swift`: six stages in entity order: board, actors, columns, tags, tasks, comments.
- Work queue: a stage puts its files in a queue; a `TaskGroup` with `ProcessInfo.activeProcessorCount` workers (configurable for tests) takes files until the queue is empty. Each worker folds one node with `Replay`. A barrier ends each stage.
- Join at the end of each stage: change each stored ref to a slot of an earlier stage. Tag `renamedTo` and task `dependsOn` resolve at the end of their own stage. A missing or cross-board target stays unresolved.
- Global event list: a k-way merge by event `id` of the sorted event lists of all files.
- A missing directory (for example no `comments/`) is an empty stage.

## Acceptance Criteria
- [ ] A load with 1 worker and a load with 8 workers give equal graphs and equal global event lists.
- [ ] After the load, each edge to a node in the board is a slot; a cross-board `dependsOn` stays unresolved.
- [ ] With 2000 task files and N workers, the peak number of workers that run at the same time equals N (a test counter records the peak).

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Events/LoaderTests.swift`: write fixture logs with `EventLog`, then load.
- [ ] Run `swift test --filter LoaderTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.