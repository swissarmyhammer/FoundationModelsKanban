---
assignees:
- claude-code
depends_on:
- 01M4X6ZBTA66TCPVYM41QR0ACD
position_column: todo
position_ordinal: '8780'
title: Start the search update early and make the session ready before the embeddings finish
---
## What
divergence.md §16, L4 (DECIDED). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/). Now `loadSession` loads the graph, then calls `updateSearch()` and waits (S/Tool/KanbanGraph.swift:567-577). `MetadataSearcher.update(items:)` waits until the embeddings of all tasks are done.

Decided behavior:
- Start the search update as soon as the task nodes exist, at the same time as the event merge and the other load work.
- The session is ready when the graph is loaded. `host.session(...)` waits for the files, the graph, the event list, and the keyword index (BM25 and trigram). It does not wait for the embeddings.
- The embeddings finish in the background. Until then, `searchTasks` uses the keyword scores (`MetadataSearcher+Search.swift:92-95`).

Dependency on another repo: `MetadataSearcher` is in `../FoundationModelsMetadataRegistry`. That package needs an API that updates the keyword index and returns, and then computes the embeddings in the background (for example `update(items:)` that returns after the keyword index, plus a way to wait for or observe the embeddings). Make that change in `../FoundationModelsMetadataRegistry` first (a separate commit in that repo), or, if you cannot, record the request and stop. Then use the new API here.

## Acceptance Criteria
- [ ] The search update starts before the event merge ends.
- [ ] `host.session` returns before a slow embedder finishes.
- [ ] `searchTasks` right after `host.session` returns gives keyword hits.
- [ ] When the embeddings finish, `searchTasks` uses them with no new load.

## Tests
- [ ] `host.session` returns before a slow embedder finishes, and `searchTasks` gives keyword hits at once.
- [ ] A test in `../FoundationModelsMetadataRegistry` for the new API (keyword index ready before embeddings).
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes (in this repo and in `../FoundationModelsMetadataRegistry`).

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.