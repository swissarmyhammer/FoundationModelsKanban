---
depends_on:
- 01M4B3Z67TC96REJGDHD2DFH0R
- 01M4B3YYXT069TKADQ93CBAA93
- 01M4B3ZDK527CRVKQQRT87RGHJ
position_column: todo
position_ordinal: '9e80'
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

## Acceptance Criteria
- [ ] With no embedder, a search for a word in the title ranks that task first, and `cosine` is null.
- [ ] With a fake embedder, `cosine` is set; with a failing embedder, the search still returns results.
- [ ] After `addTask`, a search finds the new task; `filter` and the deleted and done rules apply.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Search/TaskSearchTests.swift`.
- [ ] Run `swift test --filter TaskSearchTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.