---
depends_on:
- 01M4B3YQSXZCGCB08FVP8QCSF3
- 01M4B3XHRVFA2YDCJC76MAFQR5
- 01M4B3VKJ8W42AXVFVMH6WN5VQ
- 01M4B4A8735GAP57Q8ZVDP5HY2
position_column: todo
position_ordinal: '9480'
title: 'KanbanGraph: execute, serial gate, board load'
---
## What
The engine actor and the query path. The basis is plan.md §5.4 steps 1 to 3 and §7.2.
- `Sources/FoundationModelsKanban/Tool/KanbanGraph.swift`: `public actor KanbanGraph` with `init(root:actor:)`, `execute(query:variables:operationName:) async throws -> String` (response JSON with sorted keys), and `schemaSDL`. The `locator:` and `embedder:` parameters of plan.md §7.2 are added by the cross-repo and search tasks, with default values, so this init stays valid.
- Serial gate: an async queue so that calls in one process run one at a time (an actor alone does not do this).
- Load the current board with the parallel loader the first time that a call needs it, then keep the `Graph` in memory (the watcher comes in a later task). The board key is read from git with `BoardKey`.
- A query on a repo with no `.kanban/` returns an empty board with the repo directory name and writes nothing.
- The tool does not throw for a GraphQL error; it throws only for an I/O fault.

## Acceptance Criteria
- [ ] A query on fixture logs returns the expected JSON through `execute`.
- [ ] Two concurrent `execute` calls on one `KanbanGraph` run one at a time (a test records that the second starts after the first ends).
- [ ] A query on an empty repo writes no file.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift`: temporary repo directory, fixed clock and ULID source, fake `BoardKey`.
- [ ] Run `swift test --filter KanbanGraphTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.