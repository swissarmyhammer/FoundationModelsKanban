---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5p18b78t707cehdeh834gkv
  text: |-
    Research done.
    - The package has no resource yet. Package.swift has no `resources:` key. The new resource is `Sources/FoundationModelsKanban/Resources/FilterAgentPrompt.md`.
    - `VirtualTag.allCases` (Sources/.../Derived/VirtualTags.swift) is the one list of virtual tags. `VirtualTag.hiddenUnlessNamed` gives the default selection rule (only DELETED is hidden).
    - The grammar is in plan §6.3 and in the doc comment of `FilterParser`. Documentation/kanban/SKILL.md has a similar atom table and a "## Virtual tags" table; `KanbanSkillTests.virtualTagTableNamesEachVirtualTag` reads that table. The new test reuses that reader, so the two tests do not repeat the code.
    - The sample board of `FilterEvaluatorTests.sampleBoard()` has the tags bug, feature, docs, done, defect, old; the actors alice (Alice Smith), will; the columns todo, doing (In Progress), review, done. The examples use only these names, so `FilterNameCheckTests.sampleCheck` is the name check of the examples.
    - ^sq21qxn reads the examples from the resource in the IntegrationTests package. That package links only the product. Thus the example reader is production code (`FilterAgentPrompt.examples`), internal, and the integration test reaches it with `@testable import` (a debug `swift test` builds each module with testability).
    - ^6rxda32 needs the prompt text: `FilterAgentPrompt.load()` gives it. ^j48gsq3 adds the board vocabulary after the prompt; the prompt says that the vocabulary comes after it.
  timestamp: 2026-10-24T04:03:43.976196+00:00
- actor: claude-code
  id: 01m5p1jkemwq7wx51nwq9jj2ke
  text: |-
    Implementation landed.
    - New: `Sources/FoundationModelsKanban/Resources/FilterAgentPrompt.md` (the prompt: answer rules, atoms, operators with precedence and implicit AND, `## Virtual tags` table, default selection, 13 examples as `English:` / `Filter:` line pairs on the sample board).
    - New: `Sources/FoundationModelsKanban/Filter/FilterAgentPrompt.swift` (internal `FilterAgentPrompt`: `load()` from `Bundle.module`, `text`, `examples`, `englishLabel`, `filterLabel`). ^6rxda32 uses `load().text` as the instructions. ^sq21qxn reads `examples` through `@testable import`.
    - `Package.swift`: `resources: [.copy("Resources/FilterAgentPrompt.md")]` on the library target.
    - `KanbanSkillTests`: the virtual tag table reader is now `static func virtualTagNames(inTableOf:)`, so the skill test and the prompt test share one reader.
    - New: `Tests/FoundationModelsKanbanTests/Filter/FilterAgentPromptTests.swift`: 5 tests plus 2 parameterized tests with 13 cases each.
    - divergence.md §17: new bullet "The prompt (card ^k1s3550)".
    - Check of the criterion "a test fails when a virtual tag is not in the prompt": with the `MEDIUM` row removed, `virtualTagTableNamesEachVirtualTag` failed (names had no MEDIUM). The row is back.
    - First draft had the example "what can I start now"; it said "I", which the "me" rule maps to the caller actor. The example is now "tasks that are ready to start". The operator section is a list, not a table, because a table needs `\|\|`, and the model must not copy that form.
    - Not run: the IntegrationTests package (it needs a real model; this card adds no integration test).
  timestamp: 2026-10-24T04:09:20.084804+00:00
- actor: claude-code
  id: 01m5p1jkvspde2yzbbqp6zqft1
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsKanban/Resources/FilterAgentPrompt.md (new), Sources/FoundationModelsKanban/Filter/FilterAgentPrompt.swift (new), Tests/FoundationModelsKanbanTests/Filter/FilterAgentPromptTests.swift (new), Tests/FoundationModelsKanbanTests/KanbanSkillTests.swift, Package.swift, divergence.md. `swift build` and `swift test`: 1853 tests in 159 suites passed; the only warning is the accepted SwiftPM "missing creator" warning.
    - next: /review
  timestamp: 2026-10-24T04:09:20.505038+00:00
depends_on:
- 01M5MQSBS3E7J746F17Z794J91
position_column: doing
position_ordinal: '80'
title: 'Filter agent: write the system prompt as a package resource, with tested examples'
---
## What

Write the system prompt of the filter agent as a resource of the package, not as text in the code (divergence.md §17, "A smart prompt").

- Add the resource to the `FoundationModelsKanban` target (`resources:` in `Package.swift`).
- The prompt holds:
  - the grammar of the filter language: each sigil, each operator, the precedence and the implicit AND;
  - each virtual tag of `VirtualTag.allCases` and its meaning: `READY`, `BLOCKED`, `CONFLICT`, `DELETED`, `DONE`, `HIGH`, `MEDIUM`, `LOW`;
  - the rules of the default selection (plan §6.3);
  - examples of English and the filter statement for each one. Put the examples in a form that a test can read (for example a JSON list, or fenced pairs in the text that a test extracts).
- Keep the virtual tag list in one place. If the code already has the list (for example an enum), make a test that the prompt names each one, so the two cannot differ.

Note: `BLOCKING` is removed by divergence.md Q1 and C1. It is not a virtual tag, and `#BLOCKING` is an ordinary tag filter.

## Acceptance criteria

- [x] The prompt loads from `Bundle.module` at run time.
- [x] Each example statement parses with `FilterParser`.
- [x] Each example statement passes the name check against a fixture board that has the names of the examples.
- [x] A test fails when a virtual tag is not in the prompt.

## Tests

- Unit tests in `T/`: one test case for each example (parameterized), and the virtual tag test.
- `swift test` passes with no new warnings. #kanbanviewkit #filter-agent