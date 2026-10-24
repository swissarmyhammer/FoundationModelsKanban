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
- actor: claude-code
  id: 01m5pky525g4w7ayg4grmeb1rn
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (46b3a58). 2 findings — Sources/FoundationModelsKanban/Filter/FilterAgentLoop.swift:85, Sources/FoundationModelsKanban/Filter/FilterAgentLoop.swift:144
    - next: Correct the 2 open items in the "Review Findings (2026-10-24 04:28)" section. Then do the review again. The task stays in review.
  timestamp: 2026-10-24T09:30:12.933302+00:00
- actor: claude-code
  id: 01m5pkywqte4q5y58pvc4hqykt
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 10 files, FilterAgentLoop, FILTER_AGENT_FAILED
    - test: green — swift test, 1866 tests in 161 suites
    - commit: 46b3a58
    - review: findings — Sources/FoundationModelsKanban/Filter/FilterAgentLoop.swift:85, Sources/FoundationModelsKanban/Filter/FilterAgentLoop.swift:144
  timestamp: 2026-10-24T09:30:37.178172+00:00
- actor: claude-code
  id: 01m5pm66my26r5nfnfs7mx67ka
  text: |-
    Picked up again for the 2 review findings. Research:
    - The resolver chain is `throws(KanbanError)`, but many resolvers of the schema use untyped `async throws` (for example `addTask`, `searchTasks`). So `translateFilter`, `FilterAgent.translate` and `FilterAgentLoop.translate` can throw untyped, and a `CancellationError` goes to the GraphQL executor unchanged.
    - The GraphQL executor catches each resolver error into the `errors` list of the response. The toolkit (`GraphQLError.codedAsResultError`) gives a non-coded error the code `INTERNAL`. Thus a cancellation cannot leave `KanbanGraph.execute` as a throw. The nearest correct way: the agent and the resolver give the cancellation unchanged; the response then has `INTERNAL`, not `FILTER_AGENT_FAILED`. To record in divergence.md §17.
    - The toolkit pattern (FoundationModelsExtras `ToolCallResult`): a call stops only for its own cancel (`Task.isCancelled`).
    - Plan for the forgiving read: repeat the steps until the text does not change; a code span is a run of n backticks at each end with no run of exactly n inside; a code fence closes only with a run of at least as many backticks as the opening fence.
  timestamp: 2026-10-24T09:34:36.702139+00:00
- actor: claude-code
  id: 01m5pme4wb936bvc3e2sybb92p
  text: |-
    Both findings corrected with TDD (RED seen first: the cancel test got `.filterAgentFailed(reason: "CancellationError()")`; the new wrapped answers got the "more calls than its 1 scripted answers" error; the not-one-span answers lost one backtick at each end).
    - Finding 1: `stoppingTheAgent` gives the `CancellationError` unchanged (or a new one when the model gives a different error) when `Task.isCancelled`; else `FILTER_AGENT_FAILED`. `FilterAgentLoop.translate`, `FilterAgent.translate` and the `translateFilter` resolver now throw untyped. Discovery: with the task cancelled before the call, the SDK still calls the executor one time (the call is recorded), and the error that comes back is `CancellationError()`, not the scripted failure.
    - Finding 2: `statement(in:)` runs the steps again until a full round does not change the text. `withoutCodeSpan` removes only one real code span (same run of n backticks at each end, no run of exactly n in the content). The same cause in `withoutCodeFence`: the closing fence must have at least as many backticks as the opening fence. New test cases: a span around the label, a fence on one line, a span of two backticks, a fence of four backticks, and two answers that are not one code span.
    - divergence.md §17 records the cancel decision (the GraphQL executor catches resolver errors, so a cancelled call gives `INTERNAL` in the response, not `FILTER_AGENT_FAILED`) and the new read rules.
  timestamp: 2026-10-24T09:38:57.035075+00:00
- actor: claude-code
  id: 01m5pme59nnpa315bcrqbg5bzn
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` clean; `swift test` — 1868 tests in 161 suites passed; only the accepted SwiftPM "missing creator" warning. 5 files — Sources/FoundationModelsKanban/Filter/FilterAgentLoop.swift, Sources/FoundationModelsKanban/Filter/FilterAgent.swift, Sources/FoundationModelsKanban/GraphQL/TranslateFilterField.swift, Tests/FoundationModelsKanbanTests/Filter/FilterAgentLoopTests.swift, divergence.md
    - next: /review
  timestamp: 2026-10-24T09:38:57.461067+00:00
- actor: claude-code
  id: 01m5pmkkkpn2azq2nasfy0qn7y
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (f24a59d). 1 finding (1 confirmed, 4 refuted). Sources/FoundationModelsKanban/Filter/FilterAgentLoop.swift:192. The 2 earlier findings are checked.
    - next: Correct the duplication finding in FilterAgentLoop.swift (leadingMarkCount and trailingMarkCount). Then do the review again.
  timestamp: 2026-10-24T09:41:55.958623+00:00
- actor: claude-code
  id: 01m5pmm75d1q0cb9c4f80d96ce
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 5 files, the 2 findings fixed
    - test: green — swift test, 1868 tests in 161 suites
    - commit: f24a59d
    - review: findings — Sources/FoundationModelsKanban/Filter/FilterAgentLoop.swift:192
  timestamp: 2026-10-24T09:42:15.981097+00:00
- actor: claude-code
  id: 01m5pmsjtpkwjpdhf8014pvj6d
  text: |-
    ### implement — changed
    - evidence: 1 file — Sources/FoundationModelsKanban/Filter/FilterAgentLoop.swift. leadingMarkCount and trailingMarkCount are now one function, markCount(of:fromEnd:), and the four callers use it. The file has no other copy of this pattern. `swift build --build-tests`: only the accepted "missing creator" warning. The first full `swift test` run stopped with a fatal error in KanbanGraph ("The view holds the engine of the board ... and has no session of it"). That code is not part of this change. The second full run passed: 1868 tests in 161 suites, with only the accepted warning. The intermittent crash is recorded as a new task.
    - next: /review
  timestamp: 2026-10-24T09:45:11.766870+00:00
- actor: claude-code
  id: 01m5pmwxayg7c9pzbp65va18ec
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 75a5275): 0 findings, 0 confirmed, 0 refuted; 7 validator runs, 0 failed. 1 file reviewed. All 3 earlier findings are checked.
    - next: none. The task is in done.
  timestamp: 2026-10-24T09:47:00.830087+00:00
- actor: claude-code
  id: 01m5pmxc23w7vvtapf3pa0b885
  text: |-
    ### finish iteration 3 — clean
    - implement: changed — 1 file, markCount(of:fromEnd:)
    - test: green — swift test, 1868 tests in 161 suites
    - commit: 75a5275
    - review: clean — 0 findings, 3/3 earlier findings checked
  timestamp: 2026-10-24T09:47:15.907127+00:00
depends_on:
- 01M5MQS3GXPJ1ZDMZ9V9HQJWT8
- 01M5MQSGQF8VVFY28RNK1S3550
- 01M5MQTEP4SYRD67XJSJ48GSQ3
position_column: done
position_ordinal: ffbe80
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

## Review Findings (2026-10-24 04:28)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 8 file(s) reviewed, 4 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `Tests/Fixtures/kanban.graphql` — no validator matches this file
> - `divergence.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/Filter/FilterAgentLoop.swift:85` `completeness/public-output-contract` — stoppingTheAgent converts every error from the model into KanbanError.filterAgentFailed, including CancellationError. When the caller cancels the call, the error that reaches the caller is a user-facing FILTER_AGENT_FAILED message that tells the caller to send the call again, not a cancellation. The cancelled call is then reported as a model failure, which hides the cancellation from the caller. Rethrow CancellationError unchanged, or check Task.isCancelled in the catch block, so that only real model and prompt-resource failures become FILTER_AGENT_FAILED. Add a test that cancels the call and checks that the error is not FILTER_AGENT_FAILED.
- [x] `Sources/FoundationModelsKanban/Filter/FilterAgentLoop.swift:144` `completeness/invariant-propagation` — withoutCodeSpan removes the first and last backtick of any text that starts and ends with a backtick. It does not check that the text is a code span. A text that is a code fence with no line break, or a span that wraps a label, loses one mark at each end and still fails the parse. The docstring says the forgiving read handles a code span, but a span that wraps a label ('`Filter: #bug`') is not handled, because the label step runs before the span step. Strip the span before the label, or repeat all the steps until nothing changes. Add one test case for a span that wraps a label, and one for a single-line fenced statement.

## Review Findings (2026-10-24 04:40)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 3 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `divergence.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/Filter/FilterAgentLoop.swift:192` `duplication/duplication` — trailingMarkCount repeats the body of leadingMarkCount (line 184). The two differ only by reversed(). Both count the same mark character, so the logic can drift apart. Replace both helpers with one function that takes a direction, for example `markCount(of text: some StringProtocol, fromEnd: Bool) -> Int`. Or keep both names as one-line calls to that function. Do not add the parameter if the two helpers stay as the only callers and the reader gains nothing.
