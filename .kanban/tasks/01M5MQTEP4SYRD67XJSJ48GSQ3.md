---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5nynhe7fcxek3e5s3x5j64c
  text: 'Note: `BLOCKING` is removed by divergence.md Q1 and C1. It is not a virtual tag, and `#BLOCKING` is an ordinary tag filter. The description of this card does not name `BLOCKING`, so the description did not change. When the vocabulary names the virtual tags, use `VirtualTag.allCases`.'
  timestamp: 2026-10-24T03:18:30.599300+00:00
- actor: claude-code
  id: 01m5p2gmgyvwq8wv79wpse33an
  text: |-
    Implementation landed.

    - New type `FilterVocabulary` (internal enum) in `Sources/FoundationModelsKanban/Filter/FilterVocabulary.swift`. The pure function is `FilterVocabulary.text(of: BoardView, for: SessionActor?) -> String`. It takes `BoardView` because the seam `FilterTranslator.translate(_:notAFilterBecause:on:for:using:)` gets a `BoardView` and a `SessionActor`. The loop (^6rxda32) adds the text after `FilterAgentPrompt.load().text`. This card does not call it from production code.
    - The parts: `## The vocabulary of the board`, then `### Tags`, `### Actors`, `### Columns` (numbered from 1 in board order), `### The caller`. A list with no item gives `- none`.
    - Tags come from `Graph.boardTagSlots` (live, not renamed), the same list as `Board.tags`. Actors come from `FilterNames.liveNodes(of: ActorNode.self)`. Columns come from `Readiness.columnOrder`. Tags and actors are in slug order.
    - The description of a tag is its body (the `description` alias of `body`). Line breaks become spaces.
    - No project part: the board has no projects (plan §2.2). No virtual tag part: the prompt has the table.
    - `ReadinessFixture.addTag` has the new parameters `named` and `describedAs` (defaults keep each old call correct).
    - divergence.md §17 has a new bullet "The vocabulary (card ^j48gsq3)".

    Discovery: the session actor becomes a board actor only on its first write. A caller that did not write yet gets `@<slug>`, and the name check rejects it. I did not decide this. New task ^pmbkng7 has the options, and it depends on ^6rxda32.

    Process note: one edit (make the static constants of `FilterVocabulary` private) was made with `sed` in the shell, not with the files tool. Each other edit used the files tool.
  timestamp: 2026-10-24T04:25:44.222062+00:00
- actor: claude-code
  id: 01m5p2gmxw8154jhn7hkad2qs4
  text: |-
    ### implement — changed
    - evidence: `swift test` 1858 tests in 160 suites passed; only the accepted SwiftPM "missing creator" warning. RED seen first (`cannot find 'FilterVocabulary' in scope`), then `swift test --filter FilterVocabularyTests` 4 passed. Files: Sources/FoundationModelsKanban/Filter/FilterVocabulary.swift (new), Tests/FoundationModelsKanbanTests/Filter/FilterVocabularyTests.swift (new), Tests/FoundationModelsKanbanTests/Derived/ReadinessFixture.swift, divergence.md.
    - next: /review. Follow-up task ^pmbkng7 needs a decision by a person.
  timestamp: 2026-10-24T04:25:44.636380+00:00
- actor: claude-code
  id: 01m5p2nnzs5k2pw416w21g7p1c
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 2dd25dd). 0 findings, 0 confirmed, 2 refuted, 7 attempted, 0 failed. The engine reviewed 3 files: FilterVocabulary.swift, FilterVocabularyTests.swift, ReadinessFixture.swift. The .kanban files are not in the scope (.reviewignore). No validator matches divergence.md. The task had no prior Review Findings sections.
    - next: The task is in done. Card ^6rxda32 can use FilterVocabulary.text(of:for:). Task ^pmbkng7 holds the open "me" question for a caller that is not a board actor.
  timestamp: 2026-10-24T04:28:29.561368+00:00
- actor: claude-code
  id: 01m5pk0xyytp12raq2caq6rxy8
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 4 files, FilterVocabulary.text(of:for:)
    - test: green — swift test, 1858 tests in 160 suites
    - commit: 2dd25dd
    - review: clean — 0 findings (2 refuted)
  timestamp: 2026-10-24T09:14:15.390878+00:00
position_column: done
position_ordinal: ffbd80
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

- [x] The text names each tag, actor and column of a fixture board, with the fields above.
- [x] The text gives the caller actor and the "me" rule.
- [x] Two calls on the same board give the same text.

## Tests

- Unit tests in `T/` with a fixture board.
- `swift test` passes with no new warnings. #kanbanviewkit #filter-agent