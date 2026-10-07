---
position_column: todo
position_ordinal: b480
title: 'Root move: merge two moved root fields with the same response key'
---
## What
`Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift`: each moved root query field gets its own `_kanbanRoot<n>: board { … }` wrapper. When two moved fields have the same response key, `RewrittenDocument.restoring(_:moving:)` keeps only the first value (`OrderedDictionary(restored) { first, _ in first }`). The selections of the second field are lost with no error.

Example: `{ tasks { totalCount } ... on Query { tasks { edges { node { id } } } } }` gives `data.tasks` with `totalCount` only. GraphQL merges the two `tasks` selections, so the caller expects both `totalCount` and `edges`.

The same problem occurs for two direct root fields with the same key, for example `{ tasks { totalCount } tasks { edges { node { id } } } }`.

## Acceptance Criteria
- [ ] Two moved root fields with the same response key give one `data.<key>` with the merged result of the two selections.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift`: the two examples above give the same `data.tasks` as `{ board { tasks { totalCount edges { node { id } } } } }` gives under `data.board.tasks`.
- [ ] Run `swift test --filter NameRewriteTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.