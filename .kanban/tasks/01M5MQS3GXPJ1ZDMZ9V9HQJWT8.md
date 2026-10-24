---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5p0p4qjf45wawtr6vz0mqz9
  text: |-
    Research and implementation notes.

    - The `KanbanGraph` init that takes `embeddingWith` is internal (the test init). The public path of the embedder is `KanbanHost.configure(locator:embedder:)`. Thus the filter model goes the same way: `configure(locator:embedder:filterModel:)` (default `nil`), `HostConfiguration.filterModel`, `EngineLoad.filterModel`, `BoardEngine.filterModel` (nonisolated let), and the internal `KanbanGraph(..., embeddingWith:, filterModel:)` init. divergence.md §17 "The engine part" records this.
    - The call gives `FilterAgent(model: engine.filterModel)` to `KanbanContext.filterAgent` (a `var` with the default `FilterAgent(model: nil)`, so `CommitTests.callContext` stays correct).
    - Seam for ^6rxda32: protocol `FilterTranslator.translate(_:notAFilterBecause:on:for:using:)` in `Sources/FoundationModelsKanban/Filter/FilterAgent.swift`. It gets the text, the INVALID_FILTER error of the text, the BoardView, the session actor (for the "me" rule of ^j48gsq3), and the model. `PendingFilterTranslator` gives FILTER_MODEL_MISSING. The loop task replaces the `translator` constant of `FilterAgent` and the test `englishWithModelGoesToTranslator`.
    - `FILTER_MODEL_MISSING` is `indirect case filterModelMissing(filterError: KanbanError)`; its message ends with the INVALID_FILTER message of the text.
    - `board: ID` uses `NodeID?`. The new `BoardStore.loadedView(ofBoard:)` is now shared by `Query.cursor` and `translateFilter` (no behavior change of `cursor`).
    - Test double: `Tests/FoundationModelsKanbanTests/Filter/SpyLanguageModel.swift` (records the count of generation calls, sends no answer). ^6rxda32 needs a scripted model with answers and prompts; it can extend this file.
    - `KanbanGraphTests.makeGraph` and `ColumnActorTests.makeFixtureGraph/respondWritingNothing` now take an optional filter model.
    - The tool description does not name translateFilter (§17: the agent of a session writes the filter language).
  timestamp: 2026-10-24T03:53:47.506381+00:00
- actor: claude-code
  id: 01m5p0pcnfdznbr6zm8qz8xhaz
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` has no warning except the accepted mlx Metal and SwiftPM "missing creator" warnings; `swift test`: 1847 tests in 158 suites passed, 0 failed. SDL golden recorded with GRAPHQL_GOLDEN_RECORD=1. 20 files: new Sources/FoundationModelsKanban/Filter/FilterAgent.swift, Sources/FoundationModelsKanban/GraphQL/TranslateFilterField.swift, Sources/FoundationModelsKanban/GraphQL/SchemaDescription+FilterAgent.swift, Tests/FoundationModelsKanbanTests/Filter/SpyLanguageModel.swift, Tests/FoundationModelsKanbanTests/Filter/TranslateFilterTests.swift; changed Errors.swift, Schema.swift, SchemaDescription.swift, ChangeCursor.swift, BoardEngine.swift, KanbanGraph.swift, KanbanHost.swift, Tests/Fixtures/kanban.graphql, KanbanErrorTests.swift, ColumnActorTests.swift, KanbanGraphTests.swift, README.md, divergence.md (§17 "The engine part"), and the card files.
    - next: /review
  timestamp: 2026-10-24T03:53:55.631167+00:00
- actor: claude-code
  id: 01m5p0xc79wz151928jebr00dw
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 8e6efd4). 0 findings, 0 confirmed, 1 refuted, 21 attempts, 0 failed. The engine reviewed 15 files. It did not review 5 files: 2 files in .kanban/ (ignore rule), and README.md, Tests/Fixtures/kanban.graphql and divergence.md (no validator matches these files).
    - next: The task is in done. Card ^6rxda32 (the translator loop) can start.
  timestamp: 2026-10-24T03:57:44.553862+00:00
- actor: claude-code
  id: 01m5p0y0nzs3we5asvnqw52mmr
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 18 files, filterModel through KanbanHost.configure, translateFilter query, FilterTranslator seam
    - test: green — swift test, 1847 tests in 158 suites
    - commit: 8e6efd4
    - review: clean — 0 findings (1 refuted)
  timestamp: 2026-10-24T03:58:05.503821+00:00
depends_on:
- 01M5MQSBS3E7J746F17Z794J91
position_column: done
position_ordinal: ffbb80
title: 'Filter agent: add filterModel to the engine and the translateFilter query'
---
## What

Add the engine part of the filter agent (divergence.md §17), with no model call yet.

- Add `filterModel: (any LanguageModel)? = nil` (the FoundationModels `LanguageModel`) to the public `KanbanGraph` init, next to `embedder`. Carry it through `HostConfiguration`, `KanbanHost.configure(locator:embedder:)` and `BoardEngine`, in the same way as `embedder`.
- Add the error code `FILTER_MODEL_MISSING` to `S/GraphQL/Errors.swift`.
- Add the query `translateFilter(board: ID, text: String!): FilterTranslation!` and the type `FilterTranslation { filter: String, message: String, attempts: Int! }`, with schema descriptions in `SchemaDescription`.
- The query writes nothing: no event, no undo entry.
- When `text` parses with `FilterParser` (and each name resolves, see the name-check task), give it back with `attempts: 0`. Do not call the model.
- When `text` does not parse and there is no model, give `FILTER_MODEL_MISSING`.
- When there is a model, call a translator seam (a protocol or closure) that the loop task fills. Until then, the seam can give `FILTER_MODEL_MISSING`.

## Acceptance criteria

- [x] `KanbanGraph(..., filterModel:)` compiles, and the default is `nil`.
- [x] `translateFilter` is in the schema with descriptions.
- [x] A text that parses gives `{ filter: <text>, attempts: 0 }`, and the model is not called.
- [x] A text that does not parse, with no model, gives `FILTER_MODEL_MISSING`.
- [x] The call writes no event and pushes no undo entry.

## Tests

- Unit tests in `T/` for each criterion above. Use a spy model that records each call.
- `swift test` passes with no new warnings. #kanbanviewkit #filter-agent