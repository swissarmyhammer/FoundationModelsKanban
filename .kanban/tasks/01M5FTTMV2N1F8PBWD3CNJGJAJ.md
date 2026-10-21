---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5g31yrpy69zee7ds2jt0m96
  text: |-
    Research and repro:
    - Repro: a test that builds 256 `PublicSchema()` at once in a task group (`swift test --filter SchemaBuildConcurrencyTests`, 0.66 s per pass) hung 1 run in 20 with a 60 s timeout. The `sample` of the hung helper: 30 cooperative threads (`com.apple.root.default-qos.cooperative`), all in `GraphQLSchema.init → typeMapReducer → getFields → defineFieldMap → GraphQLField.resolve.getter` (29) or `.subscribe.getter` (1) → `OS_dispatch_queue.sync` → `_dispatch_sync_f_slow → __DISPATCH_WAIT_FOR_QUEUE__ → _dlock_wait`. One idle worker sits in `__workq_kernreturn`. No thread holds or waits on a barrier.
    - Root cause: GraphQL 4.3.0 `Type/Definition.swift` guards `GraphQLField.resolve`/`subscribe` with ONE process-wide concurrent queue (`fieldPropertyQueue`), and the type field caches with another (`cacheQueue`), and calls `sync` on them from whatever thread calls. Nothing in GraphQL, Graphiti or Extras ever writes `resolve`/`subscribe` after init, so every thread was a READER. Under contention a reader `sync` takes the slow path: it enqueues itself and waits for a drain of the queue on the default-QoS root queue. Each parallel test that builds a schema blocks a cooperative thread in such a wait; when every cooperative thread is blocked there the drain never ran in the sampled hang. Only a schema build reads `GraphQLField.resolve` (the executor reads the plain `let`s of `GraphQLFieldDefinition`), so concurrent schema builds are what fill the queue.
    - Experiment: pure readers with no build (256 tasks × 20000 `GraphQLField.resolve` reads, and 256 tasks × 200 passes of `getFields()` on a built schema) passed 15/15 runs, but each run took 2 s to 18 s, so the slow path is hit and recovers there.
    - Where builds happen: `KanbanGraph.init` builds a new `PublicSchema` for every view (every test that makes a view), `KanbanGraph.schemaSDL` builds one on each read, and about 30 test sites call `PublicSchema()` / `PatchSchema()` directly. Only ResponseWarningsTests builds with a test extension.
    - Fix plan (this package only, no dependency change): (1) build the public schema with no extension and the patch schema once per process, and share them; (2) run every schema build through one process-wide gate, so no two builds ever run at once and the GraphQL property queues never see two builders.
  timestamp: 2026-10-21T20:39:45.174203+00:00
- actor: claude-code
  id: 01m5g4en6jk6xfahgdmmch9nx8
  text: |-
    Implementation landed (not committed), all in this package. No dependency is forked, patched or re-pinned.
    - New `SchemaBuildGate` (Sources/FoundationModelsKanban/GraphQL/SchemaBuildGate.swift): a process-wide `Mutex` that runs each schema build one at a time, so the GraphQL property queues never have two builders at once. It is a Mutex and not an actor because the schema initializers are synchronous. The lock guards no state and never waits on async work.
    - `PublicSchema`: `init(extendedWith: SchemaExtension? = nil)`. `nil` gives a static shared schema, built one time through the gate. A non-nil extension builds its own schema through the gate. `PublicSchema.noExtension` is removed because nothing uses it now. The defaults in `KanbanGraph` (both inits), `KanbanGraphTests.makeGraph` and `QueryFixture.respond` are now `SchemaExtension? = nil`.
    - `PatchSchema`: built one time through the gate and shared.
    - Effect: every `KanbanGraph` view, `KanbanGraph.schemaSDL`, and the ~30 test sites now share one built schema instead of each building its own. The only builds left are the two shared ones and ResponseWarningsTests' extension builds, and those run one at a time.
    - Tests: new Tests/FoundationModelsKanbanTests/GraphQL/SchemaBuildConcurrencyTests.swift (4 tests). RED before the fix: 3 failed (the public schema is not shared, the patch schema is not shared, and concurrent extension builds overlapped). The fourth test, an extension build is a separate schema and leaves the shared one unchanged, guards the new cache and passed before the fix too. All 4 pass after the fix.
    - What did not apply: building off the cooperative pool alone was not used. A builder on another thread would still contend on the same global queues, and the callers (`KanbanGraph.init`, `schemaSDL`) are synchronous, so they would block a cooperative thread waiting for it anyway. Sharing the schema plus one build at a time removes the contention itself.
    - Remaining exposure, recorded for the next agent: GraphQL execution still does reader `sync` calls on `cacheQueue` (`getFields` for each resolved field) from cooperative threads. That is inside GraphQL and cannot be changed without patching it. A pure-reader stress (no builds, 5M+ reads across 256 tasks) never hung in 15 runs.
  timestamp: 2026-10-21T21:04:09.938671+00:00
- actor: claude-code
  id: 01m5g4ess8d2dm1z76k65ny2sa
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsKanban/GraphQL/SchemaBuildGate.swift (new), Sources/FoundationModelsKanban/GraphQL/Schema.swift, Sources/FoundationModelsKanban/GraphQL/PatchSchema.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Tests/FoundationModelsKanbanTests/GraphQL/SchemaBuildConcurrencyTests.swift (new), Tests/FoundationModelsKanbanTests/GraphQL/QueryFixture.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift. Before the fix: the stress repro (256 concurrent PublicSchema builds) hung 1 run in 20. After the fix: the stress repro (the 256-build shape, plus 64 extension builds beside 64 shared-schema SDL readers, plus SchemaBuildConcurrencyTests) passed 40/40 runs with no hang, using a 60 s timeout per run. The full `swift test` passed 20/20 runs in a row with no hang: 1750 tests in 146 suites, 0 failures, 0 skipped, 24 to 38 s each, using a 600 s timeout per run. A full recompile of the package targets gave zero compiler warnings; the only warning was the mlx-swift "missing creator" one. The temporary stress test file is deleted.
    - next: /review
  timestamp: 2026-10-21T21:04:14.632588+00:00
- actor: claude-code
  id: 01m5g4q13p74z66xxjp077ekr0
  text: |-
    ### test — green
    - evidence: `swift package clean && swift build` completed with no warnings from this package (only the ignored mlx-swift "missing creator" warning, plus -Wc++17-extensions warnings from the mlx-swift checkout Metal headers, which are third-party). `swift test` run 3 times in a row, each exit 0, no hang: 1750 tests in 146 suites passed (26.8s, 26.2s, 27.6s), 0 failed, 0 skipped. `swift build --build-tests` in IntegrationTests/ completed (Build complete, no warnings besides the ignored creator one) with the changed PublicSchema API and noExtension removed.
    - next: no code changes were needed; nothing committed. Ready for review.
  timestamp: 2026-10-21T21:08:44.278613+00:00
position_column: doing
position_ordinal: '80'
title: 'Fix the intermittent swift test hang: GraphQL schema builds deadlock on Definition.swift dispatch queues'
---
## What
About 1 full `swift test` run in 5 to 10 hangs forever after about 7 seconds. It reproduces on a97a04b with no working-tree changes (1 hang in 9 runs). A `sample` of the hung `swiftpm-testing-helper` shows every cooperative thread (23) blocked in `_dispatch_sync_f_slow` / `_dlock_wait`. The path runs from `PublicSchema.init(extendedWith:)` (Schema.swift) → `SchemaBuilder.build()` → `GraphQLSchema.init` → `typeMapReducer` → `GraphQLObjectType.getFields()` / `GraphQLInterfaceType.getFields()` (cacheQueue `.sync(flags: .barrier)`) → `defineFieldMap` → `GraphQLField.resolve.getter` (fieldPropertyQueue `.sync`), all in the GraphQL checkout at `.build/checkouts/GraphQL/Sources/GraphQL/Type/Definition.swift`. Many parallel tests that each build a schema use up the cooperative pool with blocking dispatch syncs.

## Acceptance Criteria
- [x] Find the root cause: GraphQL dependency version, a shared or cached schema per process, or no parallel schema builds on the cooperative pool
- [x] 20 full `swift test` runs in a row with no hang
