---
comments:
- actor: wballard
  id: 01m4bv7s76bk45gd9cksx7tv97
  text: |-
    Research done.
    - FoundationModelsMetadataRegistry is at ../FoundationModelsMetadataRegistry, origin git@github.com:swissarmyhammer/FoundationModelsMetadataRegistry.git, branch main (local = origin/main 91d4225). Its manifest is swift-tools 6.4; the local toolchain is Swift 6.4, so a 6.2 package can depend on it. CodeContext refers to siblings with the git@ URL and `branch: "main"`.
    - API: `MetadataSearcher<Item: SearchableMetadata>` (actor). `init(items:mode:weights:embedder:selection:onDiagnostic:)`; `update(items:) async` (hash-guarded; it awaits the embed of changed items); `search(intent:limit:) async throws -> [Match<Item>]` (throws only in `.selection` mode). `Match` has `id`, `score`, `signals: Signals?` (bm25, trigram, cosine as Double), `item`. `TextEmbedding.embed(_:) async throws -> [[Float]]` comes from FoundationModelsRanker (re-exported).
    - With no embedder, `signals.cosine` is 0.0, not nil. Thus the kanban `SearchSignals.cosine` must be set to null by the kanban code when no embedder is configured.
    - An embedder that throws: the query embed uses `try?` and reports `.embeddingUnavailable` through `onDiagnostic`; the default `onDiagnostic` logs with swift-log. The search does not throw.
    - There is no public `addTask` mutation yet (task ^4002gz in todo). The test for "after addTask" uses the commit path (a task patch through `CommitSession.run`), which is the same commit path that addTask will use.
    - Plan: `TaskSearch` (Search/) holds the `MetadataSearcher`. `KanbanGraph` makes it, gives it to `CommitSession` (update after the first load, after each commit, and after a changed-file apply) and to `KanbanContext` (for the `Board.searchTasks` resolver). `searchTasks` is nullable (`[TaskHit!]`), because a non-null field that throws drops all `data` in GraphQLSwift.
  timestamp: 2026-10-07T18:50:27.942620+00:00
- actor: wballard
  id: 01m4bw6qygy8knhq1aveknqtxz
  text: |-
    Implementation landed (TDD: the new tests failed first, then passed).
    - Package.swift: `FoundationModelsMetadataRegistry` by URL (`git@github.com:swissarmyhammer/...`, branch `main`), in the library target and the test target (the tests give a fake `TextEmbedding`). The registry pulls FoundationModelsExtras, and that pulls swift-syntax and mlx-swift. The build now prints one SwiftPM build-system line for the dependency bundle: `warning: missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)`. The line is not from a source file of this package; the compiler gives no warning for our code.
    - `Search/TaskSearchItem.swift`: `SearchableMetadata`; `id` = task URI; block = title, tag names, body.
    - `Search/TaskSearch.swift`: `TaskSearch` holds one `MetadataSearcher` (`.retrieval`). `update(from:)` gives the live tasks of a view. `hits(for:in:among:first:)` asks for `limit` = the count of the task nodes of the graph, keeps only the selected tasks, and keeps `first`. `SearchSignals.cosine` is nil when there is no embedder (the registry gives 0.0, not nil). Embedder failure: the default `onDiagnostic` of the registry logs with swift-log; the search gives no error.
    - `KanbanGraph` keeps the `TaskSearch` (new `embedder:` parameter on the public init, `embeddingWith:` on the internal init). It gives the search to `CommitSession` and to `KanbanContext` (new `search` field).
    - `CommitSession.updateSearch()` runs after the first load (from `KanbanGraph.loadedSession`) and after each commit attempt (a commit, or a changed-file apply before a run again). The watcher task (^41vdxz) must call `updateSearch()` after each batch.
    - `Board.searchTasks(query:filter:first:)` is nullable (`[TaskHit!]`), because GraphQLSwift drops all `data` when a non-null field throws.
    - Done rule: `TaskSelection(searchFiltering:)` uses the same default as `Board.tasks`: done tasks are excluded unless the filter names a column. The shared default is the new private `excludesDoneByDefault(for:)`, which `init(for:)` also uses now.
    - There is no public `addTask` yet (^4002gz). The "after addTask" test adds a task with a patch through `CommitSession.run` (the commit path that `addTask` will use), then searches.
    - Test helpers changed for reuse: `QueryFixture.respond(to:searchingWith:)` and `makeSearch(embeddingWith:)`, `CommitTests.makeSession(of:mintingFrom:searchingWith:)`, `KanbanGraphTests.taskPatch(of:titled:)`.
  timestamp: 2026-10-07T19:07:22.448659+00:00
- actor: wballard
  id: 01m4bw6v07ckh6tvcdxkvn0m31
  text: |-
    ### implement — changed
    - evidence: `swift test --filter TaskSearchTests` 11/11 passed; `swift test` 593 tests in 37 suites passed; `periphery scan --retain-public --report-exclude 'Tests/**' -- --build-system native --build-tests`: no unused code. Files: Package.swift, Package.resolved, Sources/FoundationModelsKanban/Search/TaskSearch.swift (new), Sources/FoundationModelsKanban/Search/TaskSearchItem.swift (new), GraphQL/Schema.swift, GraphQL/QueryResolvers.swift, GraphQL/TaskSelection.swift, Tool/Commit.swift, Tool/KanbanGraph.swift, Tests/.../Search/TaskSearchTests.swift (new), GraphQL/QueryFixture.swift, Filter/TaskQueryFixture.swift, GraphQLEngineTests.swift, Tool/CommitTests.swift, Tool/KanbanGraphTests.swift.
    - next: /review
  timestamp: 2026-10-07T19:07:25.575276+00:00
- actor: wballard
  id: 01m4bwcbkqkfckq8c31n8rkhz6
  text: |-
    ### finish iteration 1 — stuck
    - implement: changed — 17 files (Package.swift, Package.resolved, Search/TaskSearch.swift, Search/TaskSearchItem.swift, Schema, QueryResolvers, TaskSelection, Commit, KanbanGraph, and 6 test files); swift test 593 passed
    - test: stuck — a clean `swift build --build-tests` has warnings that come only from the new dependency chain (FoundationModelsMetadataRegistry → FoundationModelsExtras → mlx-swift 0.32.3):
      - `warning: missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)` (SwiftPM build planning)
      - many `-Wc++17-extensions` warnings from the Metal sources in `.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal/` (complex.h, utils.h, sort.h, steel_attention.h)
    - cause: a root package cannot set build settings for a dependency's targets, and the registry has no product without the MLX dependency.
    - blocker: a person must choose: (1) fix upstream in mlx-swift (C++17 for the Metal build) and pin the fixed version, (2) report the "missing creator" warning to SwiftPM or try a newer toolchain, (3) split the registry so that it has a product with no MLX, or (4) accept these dependency warnings as known (a policy change to the zero-warning rule).
    - commit: none on main. The work is kept on the local branch `wip/a9rehs7-search`, so that main stays free of warnings.
    - review: not run
  timestamp: 2026-10-07T19:10:26.423108+00:00
- actor: wballard
  id: 01m4c2qfnmmfrf455fw28fx1x7
  text: |-
    ### decision (person) — blocker resolved
    - The user accepts the dependency build warnings as known: the SwiftPM `warning: missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)` and the `-Wc++17-extensions` warnings from the mlx-swift Metal sources in `.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal/`.
    - These are the ONLY accepted warnings. A warning from our own sources, or any other dependency warning, still fails the test step.
    - The repo must record this note (for example a "Known build warnings" section in README.md), so that later readers know why the build output is not empty.
    - Next: start from the parked branch `wip/a9rehs7-search` (commit e29af3f), bring it onto main, add the note, and run the finish loop again.
  timestamp: 2026-10-07T21:01:22.484413+00:00
- actor: wballard
  id: 01m4c3k0y1z1nma1q59gt36xjm
  text: |-
    Rebase of the parked work onto main (no commit).
    - `git cherry-pick --no-commit e29af3f` on main a897866. Conflicts in QueryResolvers.swift and TaskSelection.swift only. Kept all of main: the `tasks(deleted:)` doc and `listsDeleted`. `TaskSelection.init(for:)` now uses `arguments.excludeDone ?? (!arguments.listsDeleted && excludesDoneByDefault(for: filter))`; `init(searchFiltering:)` sets `listsDeleted = false`. `swift package resolve` kept Package.resolved. Then `git cherry-pick --quit` to clear the cherry-pick state; HEAD is still a897866.
    - New main tests needed the `search` field of `KanbanContext`: ColumnActorTests.result(of:in:) and NodeQueryTests (`fixture.context`). New helper `CommitTests.callContext(of:)`; `QueryFixture.context(searchingWith:)` is internal with a default.
    - Index coverage: each public mutation (addTask, updateTask, tag, comment, delete paths) runs in `KanbanGraph.respond` -> `CommitSession.run`, and `run` calls `updateSearch()` after each commit attempt. No other code path changes the live graph (only `commit` calls `live.apply` and `live.adopt`). Tag rename changes the tag names in the render block; the searcher hash-guard embeds the changed tasks again. A delete removes the task from `orderedTasks()`, so it leaves the catalog.
    - Test: the raw-patch test `commitUpdatesSearch` is replaced by `addTaskUpdatesSearch`, which uses the real `addTask` mutation on an engine. RED seen with the post-commit `updateSearch()` removed (hits `[]`), GREEN after restore. The parked helpers `CommitTests.makeSession(searchingWith:)` and `KanbanGraphTests.taskPatch(of:titled:)` are removed again (no caller). `AddUpdateTaskTests.title` is now internal (the search test reuses it).
  timestamp: 2026-10-07T21:16:24.897270+00:00
- actor: wballard
  id: 01m4c3x1ktpv7aqs5gcw5kdjvv
  text: |-
    ### implement — changed
    - evidence: `swift package clean && swift build --build-tests`: build complete; 77 warning lines = 1 SwiftPM `missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)` + 76 `-Wc++17-extensions` lines from `.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal/`; no other warning. `swift test`: 723 tests in 43 suites passed. TDD: `TaskSearchTests/addTaskUpdatesSearch` failed on its assertion (hits `[]`) with the post-commit `updateSearch()` removed, and passed after restore.
    - files: Package.swift, Package.resolved, README.md, Sources/.../Search/TaskSearch.swift (new), Sources/.../Search/TaskSearchItem.swift (new), GraphQL/Schema.swift, GraphQL/QueryResolvers.swift, GraphQL/TaskSelection.swift, Tool/Commit.swift, Tool/KanbanGraph.swift, Tests: Search/TaskSearchTests.swift (new), GraphQL/QueryFixture.swift, GraphQL/NodeQueryTests.swift, Filter/TaskQueryFixture.swift, GraphQLEngineTests.swift, Mutations/AddUpdateTaskTests.swift, Mutations/ColumnActorTests.swift, Tool/CommitTests.swift.
    - periphery: `periphery scan --retain-public --report-exclude 'Tests/**' -- --build-system native --build-tests` reports 5 assign-only properties in GraphQL/Errors.swift. This change does not touch that file. New task ^3p88txm records them.
    - no commit; branch `wip/a9rehs7-search` is kept; nothing pushed.
    - next: /review
  timestamp: 2026-10-07T21:21:53.274928+00:00
- actor: wballard
  id: 01m4c4b0pzzkbnn5kqj568przp
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (e0b544b): 1 finding (1 confirmed, 1 refuted) — Tests/FoundationModelsKanbanTests/GraphQLEngineTests.swift:27 `reuse/reuse`.
    - next: Make one helper with a clock parameter from `CommitTests.callContext(of:)`, and use it in `makeContext`. Then review again.
  timestamp: 2026-10-07T21:29:31.103361+00:00
- actor: wballard
  id: 01m4c4baqm1c3brg6r8zcj7jyv
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 19 code and doc files (cherry-picked e29af3f onto main, README.md "Known build warnings", addTask search test)
    - test: green — swift test, 723 passed; build warnings only the 2 accepted kinds (1 SwiftPM missing creator + 76 mlx-swift Metal -Wc++17-extensions), 0 other
    - commit: e0b544b
    - review: findings — Tests/FoundationModelsKanbanTests/GraphQLEngineTests.swift:27
  timestamp: 2026-10-07T21:29:41.364067+00:00
- actor: wballard
  id: 01m4c4f887kdzvq57g3bj320gt
  text: |-
    Finding `reuse/reuse` (GraphQLEngineTests.swift `makeContext`) is fixed. One helper now makes each test `KanbanContext`.
    - `CommitTests.callContext(of:timedBy:searchingWith:)`: new `timedBy` clock parameter (default `{ CommitTests.callTime }`) and new `searchingWith` search parameter (default `TaskSearch(embeddingWith: nil)`). The existing callers (`CommitTests.patchMutationAppliesToWorkingGraph`, `ColumnActorTests.result(of:in:)`) do not change.
    - `GraphQLEngineTests.makeContext` calls `CommitTests.callContext(of:timedBy:)`.
    - `QueryFixture.context(searchingWith:)` (instance) is replaced by `static QueryFixture.context(reading:searchingWith:)`. It calls `CommitTests.callContext` with the store of the graph in the `DependencyMarkersTests` board and the clock `DependencyMarkersTests.time`. `QueryFixture.respond` and `NodeQueryTests.nodesWithAmbiguousIDIsNull` use it.
    - `TaskQueryFixture.context` calls `QueryFixture.context(reading: board.graph)`. Thus the store-and-clock pair of the two query fixtures is in one place too.
    - A search of `Tests/` for `KanbanContext(` now finds one match only: the body of `CommitTests.callContext`.
    - Note: `dump validators` wrote a rules file of 754K characters, too large to read in one pass. I used the rule list that the caller gave (magic numbers, case binding, fluent labels, first-argument labels, doc comments, 120-character lines, narrowest access, dead code, duplication, test integrity).
  timestamp: 2026-10-07T21:31:49.895600+00:00
- actor: wballard
  id: 01m4c4faqdh54drmj2vhfmxkpc
  text: |-
    ### implement — changed
    - evidence: `swift test`: 723 tests in 43 suites passed, exit 0. Build warnings: 1 line only, the accepted SwiftPM `missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)`; no warning from our sources. Files: Tests/FoundationModelsKanbanTests/Tool/CommitTests.swift, Tests/FoundationModelsKanbanTests/GraphQLEngineTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/QueryFixture.swift, Tests/FoundationModelsKanbanTests/GraphQL/NodeQueryTests.swift, Tests/FoundationModelsKanbanTests/Filter/TaskQueryFixture.swift. Finding marked `- [x]`. No commit.
    - next: /review
  timestamp: 2026-10-07T21:31:52.429442+00:00
- actor: wballard
  id: 01m4c4p54n2y7zgvw4gagga6s8
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (c9e71ed). 0 findings, 0 confirmed, 1 refuted. 5 files reviewed. 2 files under `.kanban/` not reviewed (ignore rule). All prior Review Findings items are checked.
    - next: none. The task moved to done.
  timestamp: 2026-10-07T21:35:36.085223+00:00
- actor: wballard
  id: 01m4c4pbv7wvbm1qwm24d6jmhc
  text: |-
    ### finish iteration 3 — clean
    - implement: changed — 5 test files (CommitTests, GraphQLEngineTests, QueryFixture, NodeQueryTests, TaskQueryFixture); 1/1 findings checked
    - test: green — swift test, 723 passed; build warnings only the 2 accepted kinds
    - commit: c9e71ed
    - review: clean — 0 findings
  timestamp: 2026-10-07T21:35:42.951714+00:00
depends_on:
- 01M4B3Z67TC96REJGDHD2DFH0R
- 01M4B3YYXT069TKADQ93CBAA93
- 01M4B3ZDK527CRVKQQRT87RGHJ
position_column: done
position_ordinal: a280
title: 'Search: searchTasks with MetadataSearcher'
---
## What
Ranked search over tasks. The basis is plan.md §6.4 and §12 item 6.
- Add `FoundationModelsMetadataRegistry` (by URL, the same as CodeContext).
- Add the `embedder: (any TextEmbedding)? = nil` parameter to `KanbanGraph.init`.
- `Sources/FoundationModelsKanban/Search/TaskSearchItem.swift`: conforms to `SearchableMetadata`; `id` = task URI; `renderBlock()` = title, tag names, body.
- `Search/TaskSearch.swift`: one `MetadataSearcher` for each board, kept by `KanbanGraph`; `update(items:)` after the first load and after each commit that changes tasks (the watcher task calls it after each batch). Mode `.retrieval`.
- `Board.searchTasks(query!, filter, first)`: search with `limit` = the number of tasks, then remove tasks that do not pass `filter`, deleted tasks, and done tasks (the same defaults as `tasks`), and keep `first`. Result `TaskHit { task, score, signals { bm25, trigram, cosine } }`.
- An embedder failure falls back to BM25 + trigram, is logged with swift-log, and gives no error.

## Blocker
Resolved. The person accepts the two dependency build warnings as known (see the decision comment and the "Known build warnings" section of README.md). All other warnings still fail the build check.

## Acceptance Criteria
- [x] With no embedder, a search for a word in the title ranks that task first, and `cosine` is null.
- [x] With a fake embedder, `cosine` is set; with a failing embedder, the search still returns results.
- [x] After `addTask`, a search finds the new task; `filter` and the deleted and done rules apply.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Search/TaskSearchTests.swift`.
- [x] Run `swift test --filter TaskSearchTests`; expect all pass.

## Bring the work onto main
- [x] `git cherry-pick --no-commit e29af3f` onto main; resolve the conflicts by hand and keep all of main; `swift package resolve`; no commit made.
- [x] The index update after each commit covers `addTask`, `updateTask`, and the tag, comment, and delete paths (all go through `CommitSession.run`).
- [x] Test: a task made with the real `addTask` mutation is found by `searchTasks` (replaces the raw-patch test).
- [x] README.md: "Known build warnings" section in ASD-STE100.
- [x] Clean `swift build --build-tests`: only the two accepted warning kinds. `swift test`: all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-07 16:25)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 16 file(s) reviewed, 8 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `Package.resolved` — no validator matches this file
> - `README.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/GraphQLEngineTests.swift:27` `reuse/reuse` — `makeContext` builds a `KanbanContext` with a no-embedder `TaskSearch` and a fixed clock inline. `CommitTests.callContext(of:)` already builds the same shape (same `KanbanContext` init, same `TaskSearch(embeddingWith: nil)`) with a different clock. The two copies can drift apart, for example if the context gains a field. Give `CommitTests.callContext` a clock parameter (for example `callContext(of store: BoardStore, clock: @escaping @Sendable () -> DateTime = { callTime })`) and have `makeContext` call it. Otherwise, keep the two helpers but note that they must stay in step. The fixed-clock argument is the only difference, so one parameterized helper is enough.
