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
- actor: claude-code
  id: 01m5p1qnsmag6haft2zhvpcs38
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD — 2 findings (2 confirmed, 0 refuted) — Sources/FoundationModelsKanban/Filter/FilterAgentPrompt.swift:14, Tests/FoundationModelsKanbanTests/Filter/FilterAgentPromptTests.swift:46
    - next: implement the 2 open items in the "Review Findings (2026-10-23 23:11)" section, then review again.
  timestamp: 2026-10-24T04:12:06.324972+00:00
- actor: claude-code
  id: 01m5p1re991bp82f9c14jk0kd8
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 6 files, FilterAgentPrompt.md resource and FilterAgentPrompt type
    - test: green — swift test, 1853 tests in 159 suites
    - commit: 14a0be9
    - review: findings — Sources/FoundationModelsKanban/Filter/FilterAgentPrompt.swift:14, Tests/FoundationModelsKanbanTests/Filter/FilterAgentPromptTests.swift:46
  timestamp: 2026-10-24T04:12:31.401623+00:00
- actor: claude-code
  id: 01m5p1xmdm3g8bdm4xygghqxq5
  text: |-
    Review findings fixed.
    - Finding 1 (`english` is assign-only): ^sq21qxn sends the English text of each example to `translateFilter`, so the property stays. New parameterized test `FilterAgentPromptTests.exampleHasEnglishText` reads `example.english` for each of the 13 examples: the text is not empty and has no space at the start or end (that is, it is text that a person types). Check of the test: with a trailing space on the line "English: urgent bugs", the test failed for that example only. The resource is back as it was (git diff shows no change to it).
    - Finding 2 (duplicate virtual tag test): new helper `KanbanSkillTests.expectVirtualTagTable(in:sourceLocation:)` calls `virtualTagNames(inTableOf:)` and runs the `#expect`, with the source location of the caller. Both `virtualTagTableNamesEachVirtualTag` tests call it; each `@Test` declaration stays.
    - Note: `dump validators` for a .swift file gives a file of 754K characters, too large to read in one time. The rules that apply here (dead code, duplication, doc comment on each item, test integrity) come from the findings and the earlier pass.
  timestamp: 2026-10-24T04:15:21.524285+00:00
- actor: claude-code
  id: 01m5p1xmx63tr23ap9zzaqc88b
  text: |-
    ### implement — changed
    - evidence: 2 files — Tests/FoundationModelsKanbanTests/Filter/FilterAgentPromptTests.swift, Tests/FoundationModelsKanbanTests/KanbanSkillTests.swift. `swift build --build-tests`: complete. `swift test`: 1854 tests in 159 suites passed; the only warning is the accepted SwiftPM "missing creator" warning. Both review findings are marked `- [x]`.
    - next: /review
  timestamp: 2026-10-24T04:15:22.022895+00:00
- actor: claude-code
  id: 01m5p215ttsq6z938ha540qe29
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 87e7883) gave 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. Both earlier findings are checked and fixed. The test `exampleHasEnglishText` reads `english` (Tests/FoundationModelsKanbanTests/Filter/FilterAgentPromptTests.swift:75). The shared helper `KanbanSkillTests.expectVirtualTagTable(in:)` (Tests/FoundationModelsKanbanTests/KanbanSkillTests.swift:198) has calls from both virtual tag tests.
    - next: none. The task is in done.
  timestamp: 2026-10-24T04:17:17.658960+00:00
- actor: claude-code
  id: 01m5p21nwzr63ye6kmyj6s62hx
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 2 files, the 2 findings fixed
    - test: green — swift test, 1854 tests in 159 suites
    - commit: 87e7883
    - review: clean — 0 findings, 2/2 earlier findings checked
  timestamp: 2026-10-24T04:17:34.111553+00:00
depends_on:
- 01M5MQSBS3E7J746F17Z794J91
position_column: done
position_ordinal: ffbc80
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

## Review Findings (2026-10-23 23:11)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 4 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `Sources/FoundationModelsKanban/Resources/FilterAgentPrompt.md` — no validator matches this file
> - `divergence.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/Filter/FilterAgentPrompt.swift:14` `code-hygiene/dead-code-swift` — var.instance `english` is assignOnlyProperty.
- [x] `Tests/FoundationModelsKanbanTests/Filter/FilterAgentPromptTests.swift:46` `duplication/duplication` — The new test `virtualTagTableNamesEachVirtualTag` repeats the body of the test of the same name in `KanbanSkillTests`. Both tests read a Markdown text, call `virtualTagNames(inTableOf:)`, and compare the result with `VirtualTag.allCases.map(\.rawValue)`. Only the text source differs. If one assertion changes, the other copy can drift out of sync. Move the assertion into one shared helper, for example `KanbanSkillTests.expectVirtualTagTable(in text: String)`, that calls `virtualTagNames(inTableOf:)` and runs the `#expect`. Call it from both tests with the skill text and the prompt text. Keep the two `@Test` declarations so each test still reports its own name.
