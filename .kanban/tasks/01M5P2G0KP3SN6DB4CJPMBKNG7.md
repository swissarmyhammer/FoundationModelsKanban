---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5pk0ykxt2y4ra9vt1v9178h
  text: |-
    ### decision (user, 2026-10-24)
    Option 2: the name check accepts the slug of the caller actor, also when the caller is not yet an actor of the board. Then "my tasks" is a valid filter that selects no task. Record this in divergence.md §17.
  timestamp: 2026-10-24T09:14:16.061319+00:00
- actor: claude-code
  id: 01m5pn82yaj9x23c63xvhj0gq1
  text: |-
    ### implementation (option 2)
    - Research: `FilterAgent` is the only production maker of `FilterNameCheck`. It already has the `SessionActor` of the call. The cleanest path: `FilterNameCheck(over:inBoard:for: SessionActor?)`, the same optional type as `FilterVocabulary.text(of:for:)`. `FilterAgent` gives its caller, so the check of a text that is already a filter (attempts 0) and each loop statement use the same rule. `FilterAgentLoop` needs no change: it gets the check from `FilterAgent`.
    - Rule: `FilterNameCheck.isKnown` for `.assignee` also passes when `Slug.normalizedText(of: name)` is the local id of the caller ref (`isCallerSlug`). Thus the slug, the slug in a different case, and the actor URL of this board pass. Only the caller slug gets the rule; the caller is not a candidate for the nearest name, so the message of other unknown actors does not change.
    - Evaluator: `tasks(filter:)` needs no rule. `FilterEvaluator.assigneeTest` gives no match for a name that names no actor, with no error (existing test "An assignee atom that names nothing matches nothing"). The new loop test also checks that `@newcomer` selects no task on the board.
    - Not changed: prompt resource, vocabulary text, schema descriptions, SDL golden file. plan.md not touched.
    - TDD: RED was seen first (3 cases of the caller form test gave "no actor named `newcomer`"; the loop test made a second model call). Then GREEN.
    - Tests: `FilterNameCheckTests` (callerSlugPasses with 3 forms; unknownActorWithCallerGivesSameError; shared `unknownActorFilter` / `unknownActorError()`); `FilterAgentLoopTests.myTasksOfCallerThatIsNotAnActor` (helpers `translate`, `call`, `instructions` now take the caller).
    - divergence.md §17: new bullet "\"Me\" for a caller that is not an actor of the board" with the decision, the rule, the path, the evaluator finding, and the tests.
    - Note: the validator dump file was 754K characters. I read the rule index and the Swift rule bodies, not the full text of the rules for other languages.
  timestamp: 2026-10-24T09:53:07.018926+00:00
- actor: claude-code
  id: 01m5pn88ptjdftn27jq63tz991
  text: |-
    ### implement — changed
    - evidence: `swift test` 1871 tests in 161 suites passed, 0 failures; only the accepted SwiftPM "missing creator" warning. 5 files: Sources/FoundationModelsKanban/Filter/FilterNameCheck.swift, Sources/FoundationModelsKanban/Filter/FilterAgent.swift, Tests/FoundationModelsKanbanTests/Filter/FilterNameCheckTests.swift, Tests/FoundationModelsKanbanTests/Filter/FilterAgentLoopTests.swift, divergence.md
    - next: /review (task stays in doing)
  timestamp: 2026-10-24T09:53:12.922087+00:00
depends_on:
- 01M5MQTKNM12VRRJW516RXDA32
position_column: doing
position_ordinal: '80'
title: 'Filter agent: decide "me" when the caller actor is not an actor of the board'
---
## What

The vocabulary (card ^j48gsq3, `FilterVocabulary.text(of:for:)`) tells the model to write `@<slug>` of the session actor for "me". The session actor becomes a node of the board only on its first write (plan §6). Thus a caller that did not write to the board yet gets `@<slug>`, and the name check (`FilterNameCheck`) gives `INVALID_FILTER` for it: "no actor named ...", with the nearest actor as the example. The loop (card ^6rxda32) then sends that message back, and the model can change "me" to a different actor.

A person must decide the behavior. Options:

1. Keep it. "My tasks" of a caller with no tasks fails after 3 attempts with `filter: null`.
2. The name check accepts the slug of the session actor, so `@<caller>` passes and selects no task.
3. The vocabulary tells that the caller actor is not an actor of the board, and that "me" selects no task.

Record the decision in divergence.md §17.

## Acceptance criteria

- [x] divergence.md §17 records the decision.
- [x] A unit test covers "my tasks" for a caller that is not an actor of the board.

## Tests

- `swift test` passes with no new warnings. #kanbanviewkit #filter-agent