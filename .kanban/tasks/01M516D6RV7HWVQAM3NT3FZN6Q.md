---
assignees:
- claude-code
depends_on:
- 01M4ZEVB1RK8S6B8R6DX020T0G
position_column: todo
position_ordinal: b780
title: Send a change feed event for a moved task when its remote assignee actor changes
---
## What
Found during ^x020t0g (divergence.md Q21, option A). A task that `moveTask(board:)` or `copyTask` moved to a different board keeps each assignee as the full `kanban://<old key>/actor/<slug>` URI. `Task.assignees` now reads that actor from the old board.

When the actor changes on the old board (rename, delete, undelete), the change feed of the target board does not send an event for the moved task. A subscriber on the target board thus keeps an old assignee value.

## Change
- When a related board applies a change to an actor, find each task on this board that has that actor URI as an assignee, and send an update for it in the change feed (the same way as a dependency on a related board does for `blockedBy` and `ready`).

## Acceptance Criteria
- [ ] A rename of a remote assignee actor gives an update event for the moved task on the target board.
- [ ] A delete of a remote assignee actor gives an update event, and `Task.assignees` leaves the actor out.

## Tests
- [ ] Tests with two temporary git repos. Each repo gets a unique first commit. Never use the `.kanban/` of this repo.
- [ ] `swift test` passes.