---
depends_on:
- 01M4B3ZQXZ1DKR1FVBDRCK1FP8
position_column: todo
position_ordinal: af80
title: 'Mutations: column and actor create, update, delete'
---
## What
Column and actor mutations. The basis is plan.md §4.2 and §6.
- `MutationResolvers.swift` (column and actor part): `addColumn`/`updateColumn`/`deleteColumn`/`undeleteColumn(id, name, order, body)` and `addActor`/`updateActor`/`deleteActor`/`undeleteActor(id, name, color, body, ensure)`.
- `addColumn` or `addActor` with a slug that exists gives `DUPLICATE_ID`, except `addActor(ensure: true)`, which returns the existing actor and writes nothing.
- `deleteColumn` on a column with live tasks gives `COLUMN_NOT_EMPTY`. An undelete of a live node writes nothing. Slugs follow the slug rule (`INVALID_SLUG`).
- `body` input: an `edit` patch with the diff; nothing if the text is equal.

## Acceptance Criteria
- [ ] Each mutation writes the patches of the plan.md §4.2 table and returns the node.
- [ ] `addColumn` with an existing slug gives `DUPLICATE_ID`; `addActor(ensure: true)` with an existing slug writes nothing.
- [ ] `deleteColumn` on a column with a live task gives `COLUMN_NOT_EMPTY` and writes nothing.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift`: port the matching Rust dispatch tests.
- [ ] Run `swift test --filter ColumnActorTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.