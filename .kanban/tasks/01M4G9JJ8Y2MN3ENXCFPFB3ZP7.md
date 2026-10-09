---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gzsda0r2j4xpdwy5ptk62n
  text: |-
    Research:
    - `TagMarkers.marker(in:at:)` stops the slug text at the first scalar that is not `isMarkerSlugScalar` (ASCII letter, ASCII digit, `Slug.separator`). Thus `#needs_review` gives the slug `needs`.
    - `TaskMutations.addMarkerTags` makes a tag for each new marker slug. The tag name is the slug value (existing rule: `#Bug` gives the name `bug`). This task keeps that rule.
    - `FilterParser.Body` already accepts `_` (body = not whitespace and not a stop character). `FilterParserTests` already has the case `my_tag`. The filter body set also accepts `.`, `:` and `/` for URLs, so it cannot be the same set as the marker set. The filter `#needs_review` resolves through `RefResolver` to the slug `needs-review`; it fails today only because the marker gives `needs`.
    - `wordJoiner` (`_` before `#` glues the `#` to a word) stays. `TagName.spaceReplacement` is the `_` that a tag name gets for spaces; the marker set will use that constant.
  timestamp: 2026-10-09T18:46:12.032566+00:00
- actor: claude-code
  id: 01m4gzznepgq8cnrbx0ctnn3e2
  text: |-
    Implementation landed.
    - `TagMarkers.slugPunctuation` = [`Slug.separator`, `TagName.spaceReplacement`] is the one set of marker characters other than ASCII letters and digits. `isMarkerSlugScalar` reads it.
    - Filter parser: no change. `FilterParser.Body` already accepts `_`, and it also accepts `.`, `:` and `/` for URLs, so one shared set with the marker set is not possible. `FilterParserTests` already has the case `my_tag`.
    - Choices: the tag that a new marker makes keeps the existing name rule (the name is the slug, so `#needs_review` makes the tag named `needs-review`). The `_` before `#` still glues the `#` to a word (Rust rule), so `#a_#b` gives only `a`. A virtual tag marker still makes no tag.
    - Dead end: the first form of the untagTask test expected `updateTask` before `untagTask` in the response JSON. The encoder sorts the keys, so `untagTask` comes first.
    - RED: 5 tests failed (12 issues). GREEN: same 5 pass. Full suite: 1100 tests in 79 suites pass; only the accepted SwiftPM "missing creator" warning.

    ### implement — changed
    - evidence: Sources/FoundationModelsKanban/Tags/TagMarkers.swift, Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift, Tests/FoundationModelsKanbanTests/Filter/FilterEvaluatorTests.swift, Tests/FoundationModelsKanbanTests/Mutations/AddUpdateTaskTests.swift, Tests/FoundationModelsKanbanTests/Mutations/TaskOperationTests.swift; `swift test` 1100 tests pass
    - next: /review
  timestamp: 2026-10-09T18:49:36.982173+00:00
- actor: claude-code
  id: 01m4h06g2ngznd88xqfxad76h6
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD, 3 findings — Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift:172, Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift:173, Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift:197. The commit message is true for the diff. Each acceptance criterion and test item has a test in the diff.
    - next: /implement the open items of the Review Findings section
  timestamp: 2026-10-09T18:53:20.853601+00:00
- actor: claude-code
  id: 01m4h06hhekjfybf8108k6g008
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 5 files
    - test: green — swift test, 1100 tests in 79 suites passed
    - commit: 92520ab
    - review: findings — Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift:172, Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift:173, Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift:197
  timestamp: 2026-10-09T18:53:22.350053+00:00
- actor: claude-code
  id: 01m4h0de7sfzg2ae8ezbb717cs
  text: |-
    Review findings done in `Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift`.
    - The parse cases of `parseKeepsUnderscore`, `parseIgnoresCase`, `gluedMarkerIsNotTag`, `trailingHyphenIsNotPartOfSlug` and `tildeFenceHidesMarker` are now in `parseCases`, each group with a comment. Those 5 tests are deleted, and `underscoreParseCases` is deleted. `parseGivesSlugs` runs all 28 cases.
    - `removeCases` is now `(name, body, expected)`. The cases of `removeKeepsUnderscore`, `removeUndoesAppend` and `removeIgnoresCase` are in it. `bystanderBodies` is added as `(bugTagName, body, body)`. Those 4 tests are deleted, and `underscoreRemoveCases` and `appendedCases` are deleted. `removeTakesOutMarkers` takes the name. Its second check now reads `slug.value`, not `"bug"`, so it also applies to the underscore cases. It runs all 39 cases.
    - New constant `bugTagName`. `removeKeepsSkippedLines` stays, because its body is different.
    - The glued-marker case changed from `.isEmpty` to `== []` (exact equality).
    - Case counts before and after: parse 28 = 28, remove 39 = 39, skipped lines 2 = 2. Tests in the file: 12 before, 3 after.

    ### implement — changed
    - evidence: Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift; `swift test --filter TagMarkersTests` 3 tests (28 + 39 + 2 cases) pass; `swift test` 1091 tests in 79 suites pass (1100 − 9 deleted); the only build warning is the accepted SwiftPM "missing creator" warning
    - next: /review
  timestamp: 2026-10-09T18:57:08.345320+00:00
- actor: claude-code
  id: 01m4h0k7npgthdteemgyvpcn12
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD, 0 findings (1 file reviewed, 2 .kanban files excluded by .reviewignore). All 3 prior findings are checked. The commit message is true for the diff. The case tables cover each input of the deleted tests: parse 5 tests to 9 cases in parseCases; remove 16 + append 7 + case 1 + underscore 2 + bystander 13 = 39 cases in removeCases.
    - next: none, the task is in done
  timestamp: 2026-10-09T19:00:18.230603+00:00
- actor: claude-code
  id: 01m4h0k8ntvt1qfm82z4k3g1qx
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 1 file
    - test: green — swift test, 1091 tests in 79 suites passed
    - commit: d680a33
    - review: clean — 0 findings
  timestamp: 2026-10-09T19:00:19.258134+00:00
depends_on:
- 01M4G9J9NMNJR8NZPSYPC53Z77
position_column: done
position_ordinal: d180
title: Body tag markers accept _ in the tag name
---
## What
plan.md §6: a tag name changes each run of spaces to `_`. Thus `addTag(name:"needs review")` gives the name `needs_review` and the slug `needs-review`. But `Sources/FoundationModelsKanban/Tags/TagMarkers.swift:166` and `:191-193` stop the marker text at `_`. A body with `#needs_review` parses as `#needs`, `addMarkerTags` (`GraphQL/TaskMutations.swift:403-407`) makes a new tag `needs`, and the task does not get `needs-review`. `untagTask(needs-review)` also does not remove the `#needs_review` text.

- Accept `_` in the marker characters. The marker then resolves to its slug (§6.1).
- Check the filter parser `#tag` atom (`Sources/FoundationModelsKanban/Filter/FilterParser.swift`) for the same character set, so that `#needs_review` in a filter works.

## Acceptance Criteria
- [x] A body with `#needs_review` gives the task the tag `needs-review` and makes no tag `needs`.
- [x] `untagTask(needs-review)` removes `#needs_review` from the body.
- [x] The filter `#needs_review` matches the task.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift` and a filter test.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-09 13:51)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 5 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift:172` `duplication/duplication` — parseKeepsUnderscore repeats the body of parseGivesSlugs verbatim; only the case list differs. A later change to one assertion can miss the other copy and the two tests drift apart. Add the underscore cases to parseCases and delete parseKeepsUnderscore, so one parameterized test covers both sets of cases.
- [x] `Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift:173` `reuse/reuse` — parseKeepsUnderscore is a near-copy of parseGivesSlugs. Its body is the same single assertion, `#expect(Self.slugTexts(in: body) == expected)`, on the same (body, expected) arguments. Keeping two copies means a future change to the parse assertion must be made twice. Remove parseKeepsUnderscore and append underscoreParseCases to parseCases, so parseGivesSlugs runs all cases. If a separate test name is wanted, keep one parameterized test that takes the combined case list.
- [x] `Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift:197` `reuse/reuse` — removeKeepsUnderscore is a near-copy of removeTakesOutMarkers. Both call TagMarkers.removing(markersOf: try Self.slug(of: ...), from: body) and compare the result to an expected string. removeTakesOutMarkers only adds a second check, which is also needed for the underscore cases. Add the underscore cases to removeCases, or move the name into the case tuple and have removeTakesOutMarkers take it. Then delete removeKeepsUnderscore. The per-case tuple of the existing removeCases shape is the parameter, so no second test is needed.
