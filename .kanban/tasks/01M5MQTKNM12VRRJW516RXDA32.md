---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5pk9bdezwthgh70157swwry
  text: |-
    Research done.
    - The seam is `FilterTranslator` in Sources/FoundationModelsKanban/Filter/FilterAgent.swift. `PendingFilterTranslator` is the only conformer. `FilterAgent` is made for each call in KanbanGraph (`FilterAgent(model: engine.filterModel)`).
    - The resolver chain uses `throws(KanbanError)`. A model error and a missing prompt resource are not KanbanError, so the loop needs a new KanbanError case to give a clear error. Plan: `filterAgentFailed(reason:)` with the code `FILTER_AGENT_FAILED`. It counts no attempt.
    - `LanguageModelSession(model:instructions:)` and `respond(to:)` give the answer text. A scripted executor sends `.response(action: .appendText(text, tokenCount:))` to the channel, and reads the instructions and prompt entries from `request.transcript` (same shape as ScriptedLanguageModel in FoundationModelsMetadataRegistry tests).
    - The instructions: `FilterAgentPrompt.load().text` (ends with a line break), then a line break, then `FilterVocabulary.text(of:for:)`.
    - Unit tests of the loop can use `FilterVocabularyTests.board()` and `FilterVocabularyTests.alice` with `BoardView(of:inBoard:)`.
    - ^sq21qxn calls `translateFilter` through the public API with a real model, so it needs nothing more from this card than a working loop.
  timestamp: 2026-10-24T09:18:51.310707+00:00
- actor: claude-code
  id: 01m5pkqms8p6tq3fv87k160g5m
  text: |-
    Implementation landed.
    - New `FilterAgentLoop` (Sources/FoundationModelsKanban/Filter/FilterAgentLoop.swift) replaces `FilterTranslator` and `PendingFilterTranslator`. `FilterAgent` makes one `FilterNameCheck` and gives it to the loop with the model.
    - `FilterAgentLoop.attemptLimit` = 3. The first prompt is the text. A failed statement sends `KanbanError.message` of its INVALID_FILTER error as the next prompt in the same session. After 3 failed statements: `{ filter: null, message: <last error>, attempts: 3 }`.
    - Decision recorded in divergence.md §17 ("The loop part"): new code `FILTER_AGENT_FAILED` (`KanbanError.filterAgentFailed(reason:)`) for an error of the model or a prompt resource that cannot be read. It counts no attempt.
    - Decision recorded: a forgiving read of each answer (trim, code fence with or without a language or a closing fence, the `Filter:` label, a code span).
    - Discovery: the FoundationModels SDK passes an error that the executor throws to the caller of `respond(to:)` with no wrap, so `String(describing:)` of the scripted error is the reason.
    - `SpyLanguageModel` now plays a script (`SpyModelAnswer`) and records instructions and prompt entries of each call (`SpyModelCall`).
    - Schema description of `translateFilter` and the golden SDL updated. The tool description does not name `translateFilter` (divergence §17), so it has no change.
    - Not done here (by order): ^pmbkng7.
  timestamp: 2026-10-24T09:26:39.656506+00:00
- actor: claude-code
  id: 01m5pkqn6vs86pxqjt6qec18k2
  text: |-
    ### implement — changed
    - evidence: `swift test` — 1866 tests in 161 suites passed; only the accepted SwiftPM "missing creator" warning. 10 files — Sources/FoundationModelsKanban/Filter/FilterAgent.swift, Sources/FoundationModelsKanban/Filter/FilterAgentLoop.swift (new), Sources/FoundationModelsKanban/GraphQL/Errors.swift, Sources/FoundationModelsKanban/GraphQL/SchemaDescription+FilterAgent.swift, Tests/Fixtures/kanban.graphql, Tests/FoundationModelsKanbanTests/Filter/SpyLanguageModel.swift, Tests/FoundationModelsKanbanTests/Filter/FilterAgentLoopTests.swift (new), Tests/FoundationModelsKanbanTests/Filter/TranslateFilterTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/KanbanErrorTests.swift, divergence.md
    - next: /review
  timestamp: 2026-10-24T09:26:40.091530+00:00
depends_on:
- 01M5MQS3GXPJ1ZDMZ9V9HQJWT8
- 01M5MQSGQF8VVFY28RNK1S3550
- 01M5MQTEP4SYRD67XJSJ48GSQ3
position_column: doing
position_ordinal: '80'
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

- [x] A correct statement at once gives `attempts: 1`.
- [x] A parse error and then a correction gives `attempts: 2`, and the second prompt holds the `INVALID_FILTER` message.
- [x] An unknown name and then a correction gives `attempts: 2`.
- [x] 3 failed attempts give `filter: null`, the last error in `message`, and `attempts: 3`. There is no 4th call.
- [x] Two calls do not share a session.

## Tests

- Unit tests in `T/` with a scripted `LanguageModel` that gives a fixed list of answers and records each prompt.
- `swift test` passes with no new warnings. #kanbanviewkit #filter-agent