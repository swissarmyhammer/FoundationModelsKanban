---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m515cav5hdr36723wqfvadx7
  text: |-
    ### finish iteration 1 — stuck
    - no step ran. The acceptance criteria say "The user decides." The orchestrator does not choose between option A (comments stay on the tombstone) and option B (copy comments to the new task in the same transaction).
    - next: the user picks A or B. Then /finish can run the task.
  timestamp: 2026-10-16T01:31:45.893730+00:00
position_column: todo
position_ordinal: b280
title: Decide what moveTask(board:) does with the comments of the moved task
---
## What
`moveTask(board:)` (^7jyymre, divergence.md Q21) makes a new task on the target board and tombstones the old task. The comments of the old task stay on the old task (a tombstone). The new task has no comments. divergence.md Q21 and E6 do not name comments.

## Decide
- Option A: keep the current behavior. The old task body has the line with the new URI, so a reader can find the old comments through the tombstone.
- Option B: copy each comment to the new task on the target board, in the same transaction (the author ref becomes a full URI of the old board, the same as an assignee).

## Acceptance Criteria
- [ ] The user decides. divergence.md records the decision.
- [ ] For option B: a test with two temporary git repos shows the comments on the new task, and one `undo` removes them.