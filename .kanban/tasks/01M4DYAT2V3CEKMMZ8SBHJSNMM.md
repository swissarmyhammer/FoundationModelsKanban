---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4dysm711f6vjqmfdxfcdy81
  text: |-
    Research and pins.

    - origin/main of the siblings (fetched 2026-10-08): Extras 5c1c638, MetadataRegistry 858f5da, Ranker 6156346, Multitool 24f65ed, CodeContext 97caa23, Router 85b96f3. The root graph has only Extras, MetadataRegistry and Ranker. Multitool, CodeContext and Router are not in this graph (Multitool is ^qjfsmrp).
    - New API: `PooledEmbedding` (FoundationModelsExtras, ModelPool/PooledEmbedder.swift) has `func embed(texts: [String]) async throws -> [[Float]]`. The old Ranker `TextEmbedding` had `embed(_:)`. `MetadataSearcher.init(items:mode:weights:embedder:selection:onDiagnostic:)` now takes `(any PooledEmbedding)?`. No other API that this repo uses changed. MetadataRegistry does NOT re-export `PooledEmbedding`, so the library and the test target must name the FoundationModelsExtras product.
    - Cause of the swift-case-paths failure: `swift package update` fails in SwiftPM 6.4 also on a graph that is already current ("Everything is already up-to-date", then `exhausted attempts ... 'swift-case-paths' unresolved`). No sibling uses swift-parsing. swift-parsing 0.15.2 declares swift-case-paths only under its `CasePaths` trait (`condition: .when(traits: ["CasePaths"])`), and the root turns the traits off with `traits: []`. The update path does not apply the root trait setting to that conditional dependency. A fresh `swift package resolve` with no Package.resolved works and gives the same pins. Thus I changed the 3 sibling pins by hand and checked them with `swift package resolve` (exit 0, checkouts at the new revisions). A fresh resolve in a scratch copy with the new Package.resolved leaves the file unchanged.
    - RED: with the new pins, `swift build --build-tests` fails with `TaskSearch.swift:24:39: cannot find type 'TextEmbedding' in scope` and 3 errors in KanbanGraph.swift.
  timestamp: 2026-10-08T14:31:07.233933+00:00
- actor: claude-code
  id: 01m4dz1phh0g29k20x5wvmq5ft
  text: |-
    ### implement — changed
    - evidence: 9 files. Package.swift, Package.resolved, IntegrationTests/Package.resolved, Sources/FoundationModelsKanban/Search/TaskSearch.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Tests/FoundationModelsKanbanTests/Search/TaskSearchTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/QueryFixture.swift, plan.md (§6.4 and §7.2 name `PooledEmbedding`).
    - Pins (root and IntegrationTests, the same): FoundationModelsExtras 5c1c638d3112, FoundationModelsMetadataRegistry 858f5da3d26c, FoundationModelsRanker 61563468972b (all origin/main). No other pin changed. Root originHash 90b3b27a… (the value of a fresh resolve of the new manifest).
    - Public API change (1): `KanbanGraph.init(root:actor:locator:embedder:)` — `embedder` is now `(any PooledEmbedding)?` (FoundationModelsExtras) in place of `(any TextEmbedding)?`. A caller imports FoundationModelsExtras to name the type. The library product now links the FoundationModelsExtras product directly (it was already in the graph).
    - Internal changes: `TaskSearch.init(embeddingWith:)` and `KanbanGraph.init(...embeddingWith:...)` take `(any PooledEmbedding)?`. The test fakes `FakeEmbedder` and `FailingEmbedder` conform to `PooledEmbedding` with `embed(texts:)`. The test target links FoundationModelsExtras in place of FoundationModelsMetadataRegistry (the tests used only `TextEmbedding` from it). TaskSearchItem.swift and the CLI needed no change. No other sibling API that this repo uses changed.
    - Build: clean `swift build --build-tests` (fresh scratch path) shows only the 2 accepted kinds: 76 `-Wc++17-extensions` warnings, all in `mlx-swift/Source/Cmlx/mlx-generated/metal/`, and 1 SwiftPM `missing creator for mutated node`. No new kind.
    - Periphery: `No unused code detected.`
    - Root: `swift test --skip-build` 3 times: 964 tests in 67 suites passed each time (7.8 s, 8.0 s, 8.8 s). Search suite: 11 of 11 passed, expected results not changed.
    - IntegrationTests: `swift build --build-tests && swift test` passed (1 test in 1 suite).
    - next: /review.
  timestamp: 2026-10-08T14:35:31.761416+00:00
- actor: claude-code
  id: 01m4dz1t6zytppjze3rbymn4xc
  text: 'Correction to the step record above: the change has 8 files, not 9. The list in that record is complete.'
  timestamp: 2026-10-08T14:35:35.519364+00:00
position_column: doing
position_ordinal: '80'
title: Move TaskSearch to PooledEmbedding and the current sibling packages
---
## What
A person decided this for ^qjfsmrp (2026-10-08). The current `main` of FoundationModelsExtras, FoundationModelsMetadataRegistry, FoundationModelsRanker, FoundationModelsCodeContext, FoundationModelsRouter and FoundationModelsMultitool replaced the `TextEmbedding` protocol with Extras `PooledEmbedding` (see Multitool commit b4e34f0, "refactor!: use the FoundationModels LanguageModel and Extras PooledEmbedding directly"). This repo pins old revisions, and `Sources/FoundationModelsKanban/Search/TaskSearch.swift:24:39` does not compile against the current packages (`cannot find type 'TextEmbedding' in scope`).

- Move every use of `TextEmbedding` to the current API:
  - `Search/TaskSearch.swift` and `TaskSearchItem.swift`;
  - the `embedder` parameter of `KanbanGraph.init`;
  - the search tests and their fake embedder;
  - any other user (search for `TextEmbedding`).
  Read the current sources of Extras and MetadataRegistry (in `../FoundationModelsExtras`, `../FoundationModelsMetadataRegistry`, or the new checkouts) to get the exact API. Look at how Multitool b4e34f0 did the same move.
- Update `Package.resolved` (root and `IntegrationTests/`) so that every sibling package is at its current `main`. `swift package update <package>` failed with `swift-case-paths` unresolved; find the cause, or change the pins by hand and check them with `swift package resolve`.
- Keep the `searchTasks` behavior the same. Keep the public API change as small as possible, and list each public change.
- `Package.swift` and README say that `IntegrationTests/Package.resolved` must use the same pins as the root. Keep that true.

## Acceptance Criteria
- [x] The root package and `IntegrationTests/` build against the current `main` of all sibling packages.
- [x] No `TextEmbedding` use remains.
- [x] The `searchTasks` tests pass with no change to their expected results.

## Tests
- [x] The existing search tests (`Tests/FoundationModelsKanbanTests/Search/`), with the fake embedder moved to the new API.
- [x] Run the full root `swift test` 3 times and `IntegrationTests/` `swift test`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.