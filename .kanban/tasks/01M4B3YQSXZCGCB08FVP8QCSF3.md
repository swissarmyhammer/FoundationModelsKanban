---
depends_on:
- 01M4B3V9XKKT81TCZFJJT4PE6E
- 01M4B3YC73VSKE9VEP29E3CZNQ
- 01M4B4AJGSQDJ4PCBP2W5XQJKR
- 01M4B3Y4M87387J50EQCD36VB0
position_column: todo
position_ordinal: '9380'
title: Public schema types and board queries
---
## What
The read side of the public GraphQL schema. The basis is plan.md §4.1. `node`, `nodes`, and the tombstone rules are in a separate task.
- `Sources/FoundationModelsKanban/GraphQL/Schema.swift`: the `Node` interface (`id`, `body`, `created`, `updated`, `deleted`) and the types `Board`, `Column`, `Actor`, `Tag`, `Task`, `Comment`, `TaskConnection` (cursor paging: `edges`, `pageInfo`, `totalCount`), `BoardSummary`, `Progress`.
- `GraphQL/QueryResolvers.swift`: resolvers read a `Graph` and the current board key from a context. Each `id` is the full URI. `Board.columns`, `Board.actors`, `Board.tags`, `Board.task(id:)`, `Board.tasks(first:, after:)` (the scoping arguments and `filter` are wired in the filter task). Task order: column order, then ordinal.
- `Query.board(id:)` for the current board only (related boards come with the cross-repo task).

## Acceptance Criteria
- [ ] A deep query (task → dependsOn → comments → author) returns the correct nested graph from a fixture graph.
- [ ] Paging with `first` and `after` returns each task one time, and `totalCount` is correct.
- [ ] Each `id` in the output is a full `kanban://` URI with the current board key.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/GraphQL/QueryResolverTests.swift`: GraphQL documents against fixture graphs; compare response JSON.
- [ ] Run `swift test --filter QueryResolverTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.