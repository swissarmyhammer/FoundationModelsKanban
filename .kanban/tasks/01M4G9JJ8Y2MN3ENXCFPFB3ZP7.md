---
assignees:
- claude-code
depends_on:
- 01M4G9J9NMNJR8NZPSYPC53Z77
position_column: todo
position_ordinal: 8b80
title: Body tag markers accept _ in the tag name
---
## What
plan.md §6: a tag name changes each run of spaces to `_`. Thus `addTag(name:"needs review")` gives the name `needs_review` and the slug `needs-review`. But `Sources/FoundationModelsKanban/Tags/TagMarkers.swift:166` and `:191-193` stop the marker text at `_`. A body with `#needs_review` parses as `#needs`, `addMarkerTags` (`GraphQL/TaskMutations.swift:403-407`) makes a new tag `needs`, and the task does not get `needs-review`. `untagTask(needs-review)` also does not remove the `#needs_review` text.

- Accept `_` in the marker characters. The marker then resolves to its slug (§6.1).
- Check the filter parser `#tag` atom (`Sources/FoundationModelsKanban/Filter/FilterParser.swift`) for the same character set, so that `#needs_review` in a filter works.

## Acceptance Criteria
- [ ] A body with `#needs_review` gives the task the tag `needs-review` and makes no tag `needs`.
- [ ] `untagTask(needs-review)` removes `#needs_review` from the body.
- [ ] The filter `#needs_review` matches the task.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Tags/TagMarkersTests.swift` and a filter test.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.