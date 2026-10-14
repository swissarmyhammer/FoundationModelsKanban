---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4ya7491s30jv06ayfmy8hd0
  text: |-
    Research done.
    - DependencyMarkers.all(in:) scans the whole body for the scheme. It has no line or code context. All the consumers go through it: Graph.dependencies(of:inBoard:) (readiness, cycle check in TaskMutations, RelatedBoards), and DependencyWarnings (the Q3 write check). Thus a change to all(in:) covers the cycle check and the write check.
    - DependencyMarkers.removing(markersOf:from:) calls all(in:) one line at a time, so it has no fence state. It must use the per-line flags of the whole body.
    - TagMarkers.tagBearingFlags(of:) and TagMarkers.inlineCodeEnd hold the skip logic. Plan: move the fence/heading flags and the inline code span walk to one shared helper in Sources/FoundationModelsKanban/Body/, and use it from TagMarkers and DependencyMarkers.
    - The existing test DependencyMarkersTests.markerEndsBeforePunctuation has a URL in inline code ("`url`!") as a marker. The decided behavior changes this, so that case must leave that test.
  timestamp: 2026-10-14T22:58:34.913282+00:00
- actor: claude-code
  id: 01m4yajt5zd7xvn0yrvt0tvv7c
  text: |-
    Implementation landed.
    - New shared helper Sources/FoundationModelsKanban/Body/MarkdownCode.swift: markerBearingLines(of:), editingMarkerBearingLines(of:with:), markerBearingFlags(of:), proseRanges(inLine:). The fence/heading flags, the inline code walk, and the fence/heading constants moved here from TagMarkers.
    - TagMarkers now uses MarkdownCode for the line flags and for inline code (markers(inLine:) walks the prose ranges). The behavior of tag markers is the same: all TagMarkersTests pass.
    - DependencyMarkers.all(in:) and removing(markersOf:from:) now use the same rule. The cycle check (Graph.dependencies) and the write check (DependencyWarnings) call all(in:), so they also count only the counted markers.
    - Test changes: DependencyMarkersTests.markerEndsBeforePunctuation had a URL in inline code as a marker; that mention is now "url!" (the inline code case is now not a marker). TagMarkersTests.skippedLines calls MarkdownCode.markerBearingFlags (the function moved).
    - New tests: DependencyMarkersTests (fenced, tilde fence, inline, heading; normal text; remove keeps code and heading), MarkdownCodeTests (prose ranges), AddUpdateTaskTests (dependsOn: [] keeps URL in code block; URL in code block gives no DEPENDENCY_CYCLE).
    - RED seen for each new test before the change. GREEN after. Full `swift test`: 1266 tests in 96 suites passed; only the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-14T23:04:57.791036+00:00
- actor: claude-code
  id: 01m4yajwfbv8tm5smaw87q02zn
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsKanban/Body/MarkdownCode.swift (new), Sources/FoundationModelsKanban/Derived/DependencyMarkers.swift, Sources/FoundationModelsKanban/Tags/TagMarkers.swift, Tests/FoundationModelsKanbanTests/Body/MarkdownCodeTests.swift (new), Tests/FoundationModelsKanbanTests/Derived/DependencyMarkersTests.swift, Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift, Tests/FoundationModelsKanbanTests/Mutations/AddUpdateTaskTests.swift; swift test: 1266 passed, 0 failed
    - next: /review
  timestamp: 2026-10-14T23:05:00.139477+00:00
- actor: claude-code
  id: 01m4yb0ypw9rswwfv70jb9s1yc
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 7 files
    - test: green — swift test, 1266 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: 6379e93
    - review: findings — Sources/FoundationModelsKanban/Body/MarkdownCode.swift:60, Sources/FoundationModelsKanban/Body/MarkdownCode.swift:100
  timestamp: 2026-10-14T23:12:41.180912+00:00
- actor: claude-code
  id: 01m4ybcfmgx7hc8nhaz5747h16
  text: |-
    Review findings fixed in Sources/FoundationModelsKanban/Body/MarkdownCode.swift.
    - Fence walk: a new private FenceLine value (marker, run length, info string) holds the opening fence. A fence closes only on a fence line with the same marker, a run that is not shorter, and only whitespace after the run (CommonMark). A backtick run with a backtick in its info string does not open a fence. fencePrefixes and Substring.isFenceLine are gone; fenceMarkers and minimumFenceLength replace them.
    - Inline code: inlineCodeEnd now reads the length of the opening backtick run and closes only on a later run of the same length. A run of a different length is part of the span. A span that does not close still goes to the end of the line (the earlier rule, kept on purpose; CommonMark makes an unclosed run literal text).
    - Tests (RED seen first, then GREEN): MarkdownCodeTests (new double/triple backtick prose cases; new fenceClosesOnMatchingFence with mixed ``` and ~~~, run length, info string, backtick in info string), DependencyMarkersTests (mixed fences, double- and triple-backtick spans with a task URL), TagMarkersTests (mixed fences, double-backtick span).
    - swift test: 1267 tests in 96 suites passed; only the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-14T23:18:58.960034+00:00
- actor: claude-code
  id: 01m4ybch373j9dysa1w6zqrj9d
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/Body/MarkdownCode.swift, Tests/FoundationModelsKanbanTests/Body/MarkdownCodeTests.swift, Tests/FoundationModelsKanbanTests/Derived/DependencyMarkersTests.swift, Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift; swift test: 1267 passed, 0 failed; 2 of 2 review findings checked
    - next: /review
  timestamp: 2026-10-14T23:19:00.455004+00:00
position_column: doing
position_ordinal: '80'
title: Skip task URLs in code blocks, inline code, and headings for dependency markers
---
## What
divergence.md Q5 (DECIDED: no), D1, and §11 "Q5". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem (D1): a task URL in a code block is a dependency. Tag markers skip fenced blocks and headings (S/Tags/TagMarkers.swift:88-98) and inline code (:121-156). Dependency markers do not skip them (S/Derived/DependencyMarkers.swift:32-36,65-93). An example URL in a code block can block a task or cause `DEPENDENCY_CYCLE`.

Decided behavior: use the same rule as for tag markers. A task URL in a fenced code block, in inline code, or in a heading is not a dependency.
- Change S/Derived/DependencyMarkers.swift:32-36,65-93. Use the same skip logic as S/Tags/TagMarkers.swift:88-98,121-156 (share one helper if you can).
- The removal of a URL by `updateTask(dependsOn:)` (which removes the URLs that the new list drops from the body) must use the same rule: it must not change a URL in code or in a heading.
- The cycle check and the write check (Q3) also use only the counted markers.

## Acceptance Criteria
- [ ] A task URL in a fenced code block does not make a dependency.
- [ ] A task URL in inline code does not make a dependency.
- [ ] A task URL in a heading does not make a dependency.
- [ ] A task URL in normal text still makes a dependency.
- [ ] `updateTask(dependsOn: [])` removes a URL in normal text, and keeps the same URL in a code block.
- [ ] A URL in a code block that would close a cycle does not give `DEPENDENCY_CYCLE`.

## Tests
- [ ] One test for each skip case (fenced, inline, heading) and one for normal text.
- [ ] A test for the removal rule of `updateTask(dependsOn:)`.
- [ ] A test that a URL in code does not cause `DEPENDENCY_CYCLE`.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-14 18:08)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/Body/MarkdownCode.swift:60` `completeness/invariant-propagation` — The fence walk treats any fence line as toggling one shared state, so a `~~~` line inside a ``` block closes the block early and a ``` line inside a ~~~ block does too. The text after the early close is then scanned as prose, so a task URL inside a real code block can count as a marker. Fence-type and fence-length matching are not part of the rule, though the doc comment describes a fenced code block as the unit. Record the opening fence's prefix in the walk and close only on a fence line with the same prefix, as CommonMark does. Add one test that mixes ``` and ~~~ inside a block.
- [x] `Sources/FoundationModelsKanban/Body/MarkdownCode.swift:100` `completeness/invariant-propagation` — The inline-code scanner only handles single-backtick spans. A double-backtick opener is read as an empty span followed by a second empty span, so the text between them is treated as prose. A task URL inside a double-backtick code span is therefore counted as a marker, and the rule the change was meant to enforce ("a URL in inline code is not a marker") is only enforced for one delimiter width. Match the opening run length of backticks and close only on a run of the same length. Add one test with a double-backtick span that holds a task URL, in DependencyMarkersTests and in TagMarkersTests.
