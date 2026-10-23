---
assignees:
- claude-code
position_column: todo
position_ordinal: '8980'
title: 'Add rejectTask: move a task back with a comment, in one transaction'
---
## What

The agent moves a task to Done itself, and the user does not accept each task (TestudoApp D92). The user can move a card back, with a comment that goes to the agent (D92 (e)). KanbanViewKit has the verb "reject with a comment" for this (its plan §3.4). There is no "accept" verb (decision of the user, 2026-10-23).

Today the client must send `moveTask` and `addComment` as two mutations.

## Work

- Add `rejectTask(input: {id, comment, column, before, after, ordinal})`.
- It adds the comment to the task (the actor of the call is the author) and moves the task, in one transaction. One `undoChange` reverses both.
- `comment` is required and must not be empty.
- The placement fields are the same as in `moveTask`. With no `column`, the task goes to the column before its current column in board order (from Done or Review, to the column before it). A task in the first column with no `column` gives a clear error.
- A move is never refused for a version conflict (KanbanViewKit D100): `rejectTask` takes no `ifVersion`.
- Add schema descriptions, update the tool description, and record the verb and the default column rule in `divergence.md`.

## Acceptance criteria

- [ ] `rejectTask(input: {id, comment: "..."})` on a task in Done adds the comment and moves the task to the column before Done, in one transaction.
- [ ] With `column: "doing"`, the task goes to Doing.
- [ ] One `undoChange` removes the comment and moves the task back.
- [ ] A missing or empty comment gives a clear error and writes nothing.
- [ ] The `changes` event holds the moved task and the new comment.

## Tests

- Unit tests in `T/` for each criterion.
- `swift test` passes with no new warnings.