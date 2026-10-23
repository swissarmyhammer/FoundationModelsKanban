---
assignees:
- claude-code
depends_on:
- 01M5MQSBS3E7J746F17Z794J91
position_column: todo
position_ordinal: '80'
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

- [ ] `KanbanGraph(..., filterModel:)` compiles, and the default is `nil`.
- [ ] `translateFilter` is in the schema with descriptions.
- [ ] A text that parses gives `{ filter: <text>, attempts: 0 }`, and the model is not called.
- [ ] A text that does not parse, with no model, gives `FILTER_MODEL_MISSING`.
- [ ] The call writes no event and pushes no undo entry.

## Tests

- Unit tests in `T/` for each criterion above. Use a spy model that records each call.
- `swift test` passes with no new warnings. #kanbanviewkit #filter-agent