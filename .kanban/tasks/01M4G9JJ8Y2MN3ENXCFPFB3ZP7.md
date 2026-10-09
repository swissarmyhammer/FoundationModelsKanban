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
depends_on:
- 01M4G9J9NMNJR8NZPSYPC53Z77
position_column: doing
position_ordinal: '80'
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