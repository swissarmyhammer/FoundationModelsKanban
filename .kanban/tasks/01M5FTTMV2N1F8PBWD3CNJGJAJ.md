---
assignees:
- claude-code
position_column: todo
position_ordinal: '8780'
title: 'Fix the intermittent swift test hang: GraphQL schema builds deadlock on Definition.swift dispatch queues'
---
## What
About 1 full `swift test` run in 5 to 10 hangs forever after about 7 seconds. It reproduces on a97a04b with no working-tree changes (1 hang in 9 runs). A `sample` of the hung `swiftpm-testing-helper` shows every cooperative thread (23) blocked in `_dispatch_sync_f_slow` / `_dlock_wait`. The path runs from `PublicSchema.init(extendedWith:)` (Schema.swift) → `SchemaBuilder.build()` → `GraphQLSchema.init` → `typeMapReducer` → `GraphQLObjectType.getFields()` / `GraphQLInterfaceType.getFields()` (cacheQueue `.sync(flags: .barrier)`) → `defineFieldMap` → `GraphQLField.resolve.getter` (fieldPropertyQueue `.sync`), all in the GraphQL checkout at `.build/checkouts/GraphQL/Sources/GraphQL/Type/Definition.swift`. Many parallel tests that each build a schema use up the cooperative pool with blocking dispatch syncs.

## Acceptance Criteria
- [ ] Find the root cause: GraphQL dependency version, a shared or cached schema per process, or no parallel schema builds on the cooperative pool
- [ ] 20 full `swift test` runs in a row with no hang
