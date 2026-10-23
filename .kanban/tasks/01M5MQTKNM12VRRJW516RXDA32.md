---
assignees:
- claude-code
depends_on:
- 01M5MQS3GXPJ1ZDMZ9V9HQJWT8
- 01M5MQSGQF8VVFY28RNK1S3550
- 01M5MQTEP4SYRD67XJSJ48GSQ3
position_column: todo
position_ordinal: '8480'
title: 'Filter agent: the write, parse and correct loop, with a scripted model'
---
## What

Fill the translator seam of `translateFilter` with the loop of the filter agent (divergence.md §17, "The loop" and "No memory").

- Each call makes a new `LanguageModelSession` with the `filterModel`, the system prompt resource and the board vocabulary.
- The model writes one statement. The engine parses it with `FilterParser` and runs the name check.
- A parse error or an unknown name goes back to the model as the `INVALID_FILTER` message (the position, the specific message and the corrected example). The model writes again in the same session.
- At most 3 attempts. The first statement that parses and passes the name check is the result: `{ filter, attempts: n }`.
- After 3 failed attempts: `filter` is null, `message` gives the last error, `attempts` is 3.
- An error of the model itself (for example, the model is not available) gives a clear error. It does not count as an attempt.

## Acceptance criteria

- [ ] A correct statement at once gives `attempts: 1`.
- [ ] A parse error and then a correction gives `attempts: 2`, and the second prompt holds the `INVALID_FILTER` message.
- [ ] An unknown name and then a correction gives `attempts: 2`.
- [ ] 3 failed attempts give `filter: null`, the last error in `message`, and `attempts: 3`. There is no 4th call.
- [ ] Two calls do not share a session.

## Tests

- Unit tests in `T/` with a scripted `LanguageModel` that gives a fixed list of answers and records each prompt.
- `swift test` passes with no new warnings. #kanbanviewkit #filter-agent