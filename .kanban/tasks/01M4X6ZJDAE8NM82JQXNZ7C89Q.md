---
assignees:
- claude-code
position_column: todo
position_ordinal: '8580'
title: Load all board files in one worker pool and list the node folders at the same time
---
## What
divergence.md §16, L2 and L3. The user: "we do need our board load to be as parallel as possible." This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

- L2: the loader reads the files of one node type at a time: board, actors, columns, tags, tasks, comments (S/Events/Loader.swift:44,109-119). Each stage waits for its slowest file before the next stage starts. But each file folds alone (`log.readLog(of:)`, :171). Only the join needs the stage order. Change: one worker pool reads and folds all files of all node types. Then the join runs in stage order, in memory. This removes five barriers.
- L3: the directory listings run one after the other (:151-156, one for each node type). Change: list the six folders at the same time.
- The result of a load must not change: the same graph, the same events, the same order of the join.

## Acceptance Criteria
- [ ] One worker pool reads and folds the files of all six node types.
- [ ] The join runs in stage order after all folds are done, and gives the same graph as before.
- [ ] The six folder listings run at the same time.
- [ ] The peak worker count stays in the current limit.

## Tests
- [ ] The worker observer shows that the files of all types are read in one pool (a file of a later type starts before all files of an earlier type end).
- [ ] The existing loader tests, the shuffle and replay property test, and the 2000-file peak worker test pass with no change in result.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.