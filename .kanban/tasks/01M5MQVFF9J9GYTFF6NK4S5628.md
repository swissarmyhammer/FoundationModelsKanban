---
assignees:
- claude-code
position_column: todo
position_ordinal: '8980'
title: Add acceptReview and rejectReview mutations
---
## What

KanbanViewKit has the verbs "accept a task" and "reject it with a comment" (its plan §3.4). The schema has no review verbs today. The board has a `review` column (order 2, between `doing` and `done`).

- `acceptReview(input: {id})`: completes the task (the same result as `completeTask`: the task goes to the done column).
- `rejectReview(input: {id, comment})`: adds the comment to the task and moves the task back to the doing column (the column before `review` in board order), in one transaction. The comment is required.
- Find the review column and the target columns by their role, not by a fixed slug, if the board model has column roles. Else use the board order, and record the rule.
- A task that is not in the review column: decide to refuse it or to accept it (very forgiving tool inputs: accept it when the result is clear). Record the decision in `divergence.md`.
- Add schema descriptions and update the tool description.

## Acceptance criteria

- [ ] `acceptReview` moves a review task to done, in one transaction.
- [ ] `rejectReview` adds the comment and moves the task to doing, in one transaction. One `undoChange` reverses both.
- [ ] `rejectReview` with no comment gives a clear error.

## Tests

- Unit tests in `T/` for each criterion.
- `swift test` passes with no new warnings. #kanbanviewkit