---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
title: 'Filter agent: add the board vocabulary and the caller actor to each prompt'
---
## What

On each `translateFilter` call, the engine adds the live names of the board to the instructions of the model (divergence.md §17, "The vocabulary of the board").

- Make a pure function: board state + caller actor -> the text of the vocabulary part of the prompt.
- It holds:
  - each tag: slug, name and description;
  - each actor: slug and name;
  - each column: slug, name and board order;
  - each project: slug and name, if the board has projects;
  - the caller actor, with the rule that "me" and "my tasks" become `@<actor>`. With no caller actor, say that "me" has no meaning.
- The order is stable (board order for columns, slug order for the others), so a test can compare the text.

## Acceptance criteria

- [ ] The text names each tag, actor and column of a fixture board, with the fields above.
- [ ] The text gives the caller actor and the "me" rule.
- [ ] Two calls on the same board give the same text.

## Tests

- Unit tests in `T/` with a fixture board.
- `swift test` passes with no new warnings. #kanbanviewkit #filter-agent