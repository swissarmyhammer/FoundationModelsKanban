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
- actor: claude-code
  id: 01m4xvn39v5ztekv9vfjzz41bs
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 9 files (no change in FoundationModelsMetadataRegistry)
    - test: green — swift test, 1194 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: 3059b9f
    - review: findings — Tests/FoundationModelsKanbanTests/Search/SearchReadinessTests.swift:72, Tests/FoundationModelsKanbanTests/Search/SearchReadinessTests.swift:98, Tests/FoundationModelsKanbanTests/Search/SearchReadinessTests.swift:155
  timestamp: 2026-10-14T18:44:04.027123+00:00
- actor: claude-code
  id: 01m4xvvp1cy2svv8r59baxyj9q
  text: |-
    Review findings fixed in Tests/FoundationModelsKanbanTests/Search/SearchReadinessTests.swift (test code only, no production change):
    - no-test-cheating: added `#expect(!keywordHits.isEmpty)` before the cosine check in searchUsesEmbeddingsWhenTheyFinish. The other `allSatisfy` checks in the file already have a non-empty guard (an exact id list, or `!hits.isEmpty &&`).
    - magic-numbers-swift: removed `checkInterval` (the cause at the cited line). Also gave each numeric literal in the file a name, with the EventLogTests pattern: `holdLimitSeconds`, `mergeWaitLimitSeconds`.
    - reuse: removed the private `GatedEmbedder.wait`. The embed hold and `waitForStart` now call `EventLogTests.becomesTrue(within:_:)`. The callers still read the state after the call. The poll pause is now `EventLogTests.retryPause` (10 ms, was 5 ms).
  timestamp: 2026-10-14T18:47:39.820638+00:00
- actor: claude-code
  id: 01m4xvvr3znvsck8vhc5x3b088
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/Search/SearchReadinessTests.swift. `swift build --build-tests`: only the accepted SwiftPM "missing creator" warning. `swift test --filter SearchReadinessTests`: 3 passed. `swift test`: 1194 tests in 88 suites passed. 3 of 3 review findings checked.
    - next: /review
  timestamp: 2026-10-14T18:47:41.951312+00:00
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

## Review Findings (2026-10-14 13:39)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 8 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/Search/SearchReadinessTests.swift:72` `test-integrity/no-test-cheating` — The assertion that keyword hits have no cosine score passes when the keyword search returns no hits. The test never checks that keywordHits is non-empty, so the check is vacuously true and cannot fail for an empty result. Add `#expect(!keywordHits.isEmpty)` before line 72, as sessionIsReadyBeforeEmbeddings does at line 54, so the cosine check proves something about the keyword hits.
- [x] `Tests/FoundationModelsKanbanTests/Search/SearchReadinessTests.swift:98` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Tests/FoundationModelsKanbanTests/Search/SearchReadinessTests.swift:155` `reuse/reuse` — GatedEmbedder.wait reimplements the polling wait that already exists as EventLogTests.becomesTrue. Both poll a condition with a short sleep until a deadline. The new copy duplicates the deadline and sleep loop, so a fix to one (for example, a change to the pause or the deadline handling) will not reach the other. Replace the body of GatedEmbedder.wait with a call to EventLogTests.becomesTrue(within: limit, condition), or move becomesTrue to a shared test helper and call it from both suites. Note that becomesTrue returns a Bool and does not throw on timeout, so the callers that need the outcome (waitForStart, the embed hold) must still read the state after the call, as they already do.
