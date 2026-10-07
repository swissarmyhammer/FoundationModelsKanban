---
depends_on:
- 01M4B3ZDK527CRVKQQRT87RGHJ
- 01M4B4AJGSQDJ4PCBP2W5XQJKR
- 01M4B406Z7RVSBJKKJ8KJW0CY2
- 01M4B40CFSF002B4DKM3T8J6GV
- 01M4B4B57JFX8HA0B45MMDQ1SQ
- 01M4B4B1G28KK1NVCXHK9GDAYR
position_column: todo
position_ordinal: 9d80
title: 'Change model: NodeUpdate and FieldChange'
---
## What
Describe what one transaction changed. The basis is plan.md §4.1 (`Change`, `NodeUpdate`, `FieldChange`), §5.3 step 5, and §6.7 (Kind, Fields, Derived updates).
- `Sources/FoundationModelsKanban/Observe/ChangeBuilder.swift`: from the projection before and after a transaction, make a `Change` (`txn`, `at`, `actor`, `ops`, `boards`, `undone`, `undoes`) with one `NodeUpdate` for each changed node of all six types. A `Change` actor that is a tombstoned actor returns the tombstone.
- `kind`: `CREATED` (first patch), `DELETED` (`delete: true`), `RESTORED` (`delete: false`), `UPDATED`. `NodeUpdate.node` for `DELETED` is the tombstone with `deleted` set.
- `FieldChange`: public field name; `before`/`after` for a single value; `added`/`removed` for a list; for `body` only `diff` (from the body before the transaction to the body after it), with null `before`/`after`.
- Derived updates: compare the derived fields and the read-time tags of each task (and `Board.summary`) before and after; add a `NodeUpdate` with `source: DERIVED` for each node whose values changed.
- Add the GraphQL types `Change`, `NodeUpdate`, `FieldChange` to the schema.

## Acceptance Criteria
- [ ] For each public mutation, the `Change` has one `NodeUpdate` for each changed node, with the correct `kind`, and `FieldChange` values that equal a query before and after.
- [ ] `completeTask` on A gives `DERIVED` updates for a task B that depends on A (`ready`, `blockedBy`, `virtualTags`) and for the board (`summary`); a tag rename gives `DERIVED` `tags` updates.
- [ ] The `actor` of a `Change` made by an actor that was later deleted returns the tombstone.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Observe/ChangeBuilderTests.swift`.
- [ ] Run `swift test --filter ChangeBuilderTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.