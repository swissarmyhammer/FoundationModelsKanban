---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4xtpjya1878h8hg54cwcam8
  text: |-
    Research (implement):
    - MetadataSearcher API at the pinned revision 858f5da (remote dependency, branch main). `update(items:)` sets the keyword index (BM25, trigram) with no suspension after the hop into the actor, and then awaits the single-flight embed loop. No public call tells the caller that the keyword part is done. A detached `update` gives no signal; a searcher made with `init(index:embedder:)` embeds the full catalog at its first search (FirstSearchCatchUp), so its first search waits for the embedder.
    - Result: the goal is possible in this repo with the current API, with no change in FoundationModelsMetadataRegistry. TaskSearch keeps two searchers: a keyword searcher with no embedder (its `update` returns after the keyword index, because there is nothing to embed), and an embedding searcher that a background loop updates (newest catalog only). `hits` uses the embedding searcher only when its catalog is the current catalog; until then it uses the keyword searcher and gives no cosine score.
    - The load code is now in BoardEngine.load (not KanbanGraph.loadSession). BoardLoader.load joins the graph and then merges the event lists. The plan: split the load into a join step and a merge step, and run the keyword update and the merge at the same time.
    - No new API in FoundationModelsMetadataRegistry, so the card item "a test in ../FoundationModelsMetadataRegistry for the new API" does not apply. The user said not to edit any other repo.
  timestamp: 2026-10-14T18:27:24.234855+00:00
- actor: claude-code
  id: 01m4xv8bpg80xz4f02df15gynk
  text: |-
    Implementation landed (TDD: the three new tests failed first for the expected reasons, then passed).
    - Load split: `BoardLoader.join()` + `JoinedBoard.merged()`; `LiveGraph.join(using:)` + `LiveGraph.Joined.merged()`. `load()` keeps its old behavior.
    - `EngineLoad.session()` (BoardEngine.swift): `async let key`; join the files; `async let live` = merge of the event lists; then the keyword update of the search runs at the same time as the merge. The session returns when the graph, the event list, and the keyword index are ready.
    - `TaskSearch` now holds a keyword searcher (no embedder, so `update(items:)` returns after BM25 and trigram) and an optional `EmbeddedTaskCatalog` actor. The actor updates a second searcher with the embedder in a background loop (newest catalog only). `hits` uses the searcher with the embedder only when it holds the newest catalog; else the keyword searcher, and `cosine` is null.
    - New test seam: `BoardLoadObserver.boardEventsWillMerge(at:)` (default no-op).
    - `BoardEngine.close()` calls `TaskSearch.stopEmbedding()`, so no background loop continues after the host closes. Note: `MetadataSearcher` runs its embed in its own unstructured task, so an embed in flight can still run to its end; the loop takes no next catalog.
    - Discovery: a commit and a watcher batch also call `updateSearch()`. They now also return after the keyword index; the embeddings of the changed tasks finish in the background.
    - Cost: with an embedder, each board keeps two keyword indexes (one in each searcher).
    - `QueryFixture.makeSearch` now waits for the embeddings (`waitForEmbeddings()`), so the old fake-embedder test still sees cosine scores.
    - README: one sentence about the readiness behavior.
  timestamp: 2026-10-14T18:37:06.640650+00:00
- actor: claude-code
  id: 01m4xv8gb8mn1mqx5eq756y890
  text: |-
    ### implement — changed
    - evidence: 9 files. New: Sources/FoundationModelsKanban/Search/EmbeddedTaskCatalog.swift, Tests/FoundationModelsKanbanTests/Search/SearchReadinessTests.swift. Changed: Sources/FoundationModelsKanban/Events/Loader.swift, Sources/FoundationModelsKanban/Observe/LiveGraph.swift, Sources/FoundationModelsKanban/Search/TaskSearch.swift, Sources/FoundationModelsKanban/Tool/BoardEngine.swift, Tests/FoundationModelsKanbanTests/GraphQL/QueryFixture.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanHostTests.swift, README.md. `swift build --build-tests`: only the accepted SwiftPM "missing creator" warning. `swift test`: 1194 tests in 88 suites passed. FoundationModelsMetadataRegistry: no change, no new API needed.
    - next: /review
  timestamp: 2026-10-14T18:37:11.400108+00:00
depends_on:
- 01M4X6ZBTA66TCPVYM41QR0ACD
position_column: doing
position_ordinal: '80'
title: Start the search update early and make the session ready before the embeddings finish
---
## What
divergence.md §16, L4 (DECIDED). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/). Now `loadSession` loads the graph, then calls `updateSearch()` and waits (S/Tool/KanbanGraph.swift:567-577). `MetadataSearcher.update(items:)` waits until the embeddings of all tasks are done.

Decided behavior:
- Start the search update as soon as the task nodes exist, at the same time as the event merge and the other load work.
- The session is ready when the graph is loaded. `host.session(...)` waits for the files, the graph, the event list, and the keyword index (BM25 and trigram). It does not wait for the embeddings.
- The embeddings finish in the background. Until then, `searchTasks` uses the keyword scores (`MetadataSearcher+Search.swift:92-95`).

Dependency on another repo: `MetadataSearcher` is in `../FoundationModelsMetadataRegistry`. That package needs an API that updates the keyword index and returns, and then computes the embeddings in the background (for example `update(items:)` that returns after the keyword index, plus a way to wait for or observe the embeddings). Make that change in `../FoundationModelsMetadataRegistry` first (a separate commit in that repo), or, if you cannot, record the request and stop. Then use the new API here.

Result: no new API was necessary. The current `MetadataSearcher` API is sufficient (see the comments). FoundationModelsMetadataRegistry did not change.

## Acceptance Criteria
- [x] The search update starts before the event merge ends.
- [x] `host.session` returns before a slow embedder finishes.
- [x] `searchTasks` right after `host.session` returns gives keyword hits.
- [x] When the embeddings finish, `searchTasks` uses them with no new load.

## Tests
- [x] `host.session` returns before a slow embedder finishes, and `searchTasks` gives keyword hits at once.
- [ ] A test in `../FoundationModelsMetadataRegistry` for the new API (keyword index ready before embeddings). Does not apply: no new API was added, and the user said not to change any other repo.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes in this repo. FoundationModelsMetadataRegistry did not change.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.