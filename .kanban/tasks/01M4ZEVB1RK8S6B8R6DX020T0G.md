---
assignees:
- claude-code
position_column: todo
position_ordinal: b180
title: Show an assignee that is a full URI of a different board in Task.assignees
---
## What
A move or a copy of a task to a different board (^7jyymre, divergence.md Q21) stores each assignee of the old board as the full `kanban://<old key>/actor/<slug>` URI. This is the decided rule of the card.

`Task.assignees` (S/GraphQL/QueryResolvers.swift, `view.liveObjects(at: state.assignees.compactMap(\.resolvedSlot))`) reads only edges that resolve to a slot of the same board. Thus the moved task shows no assignee on the target board, and the `@actor` filter does not find it.

## Decide and do
- Option A: `Task.assignees` reads a remote actor URI from the related board (as `dependsOn` does), and the `@actor` filter matches the slug of a remote actor.
- Option B: the transfer makes each missing actor on the target board (as E6 does for tags) and stores a local ref. This changes the decided rule of Q21, so the user must decide.

## Acceptance Criteria
- [ ] After `moveTask(board:)` of a task with an assignee, `Task.assignees` of the new task gives the actor.
- [ ] `@<slug>` finds the moved task.

## Tests
- [ ] A test in Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoTransferTests.swift with two temporary git repos.
- [ ] `swift test` passes.