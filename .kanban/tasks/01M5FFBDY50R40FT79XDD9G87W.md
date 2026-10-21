---
assignees:
- claude-code
depends_on:
- 01M5F23SEC4X5S9D80NESC56VK
position_column: todo
position_ordinal: '8680'
title: Correct the older schema descriptions that do not match their resolvers (links, collect results, virtual tags)
---
## What
The second review of ^esc56vk (2026-10-21) found descriptions that are older than that task and do not match their resolvers:
- `linkStatus` and `linkTarget` (GraphQL/CheckLinksField.swift around :158, and GraphQL/SchemaDescription.swift)
- `collectResultRepairs` and `collectResultOtherLinks` (GraphQL/SchemaDescription.swift)
- `VirtualTag.explanation` for READY, BLOCKED and DELETED

The exact mismatch for each is in the "Review Findings (2026-10-21 09:53)" section and the review comment on ^esc56vk.

Read each resolver path end to end, then rewrite the description as a short statement that is plainly true. Re-record Tests/Fixtures/kanban.graphql with GRAPHQL_GOLDEN_RECORD=1.

## Acceptance Criteria
- [ ] Each listed description matches its resolver behavior
- [ ] The golden SDL is re-recorded and the golden test passes

## Tests
- [ ] `swift test` is green