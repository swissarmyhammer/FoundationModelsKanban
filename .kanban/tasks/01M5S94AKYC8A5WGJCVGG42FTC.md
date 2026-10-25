---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5s9dv27vgexjsg5b4e8rgsa
  text: |-
    Research done.
    - One call is one transaction: each patch that a field body of `KanbanContext.runMutation` / `changeNode` writes goes into one txn (the same path that `moveTasks` uses). Thus the renumber writes one `updateNode` per changed column in the body of `moveColumn`.
    - Task rule for two place fields: `Placement.init(from:)` throws `CONFLICTING_PLACEMENT` at decode time. Its message names `ordinal` and tasks, so a column move needs its own message. Plan: a new case `KanbanError.conflictingColumnPlacement(after:before:)` with the same code `CONFLICTING_PLACEMENT`, thrown when `after` and `before` are not neighbours (the check needs the graph, so the resolver throws it; the field still writes nothing).
    - Task rule for no place field: `Placement.end`, the end of the column. Column form: the end of the board (after the terminal column).
    - P1: a ref that names no task puts the task at the end, with `NEIGHBOR_NOT_FOUND`. Column form: the end of the board, with the same code. The warning text of `Placement.neighborNotFoundWarning` gets the node type and the container as parameters, so that the two messages share one function.
    - Board order: `ColumnOrder` sorts by (order, slug). Terminal column = last.
    - SDL golden file: `Tests/Fixtures/kanban.graphql` (EndpointConventionTests). Alias tables: `KanbanFieldAliases.byType`; `AliasTableTests` covers rows.
  timestamp: 2026-10-25T10:24:15.943277+00:00
- actor: claude-code
  id: 01m5sa43wsyxvj3zfre8b77h1n
  text: |-
    Implementation landed (divergence.md §25).
    - New file `Sources/FoundationModelsKanban/GraphQL/MoveColumnMutation.swift`: `moveColumn`, `MoveColumnInput`, the place rules, and `ColumnRenumber`. It is a new file beside `RejectTaskMutation.swift`, because `ColumnActorMutations.swift` is already long. `Schema.swift` adds it after `addColumnActorMutations()`.
    - Place rules (agree with moveTask): no place = after the terminal column; a ref that names no live column = after the terminal column + `NEIGHBOR_NOT_FOUND` (P1); `before` + `after` that are neighbors = between; not neighbors = `CONFLICTING_PLACEMENT` with the new case `KanbanError.conflictingColumnPlacement(after:before:)` (own message, because the task message names `ordinal`); a ref to the column itself or the same place = write nothing.
    - `Placement.neighborNotFoundWarning` now takes the node type and the container, so tasks and columns share one function. `NeighborSide` is internal now.
    - Renumber: keep the largest set of columns whose (order - place) does not go down; ties prefer the set without the moved column. Others get evenly spread integers between kept neighbors, or a step of 1 at the ends. This gives "only the moved column changes" for a gap, minimal changes otherwise, and a strict board order. Orders can become negative (before a first column with order 0).
    - Discovery: tests must hold the `TemporaryDirectory` in a local; a `try TemporaryDirectory()` passed inline is freed before the engine reads the log (`fileSystem ... No such file or directory`).
    - SDL golden file regenerated with `GRAPHQL_GOLDEN_RECORD=1 swift test --filter EndpointConventionTests`.
  timestamp: 2026-10-25T10:36:25.881133+00:00
- actor: claude-code
  id: 01m5sa44bwc99wkb6t30dmx9jt
  text: |-
    ### implement — changed
    - evidence: `swift test` — 1892 tests in 164 suites passed, 0 failures, no warnings other than the allowed ones. 11 files: Sources/FoundationModelsKanban/GraphQL/MoveColumnMutation.swift (new), Errors.swift, FieldAliases.swift, Schema.swift, SchemaDescription+Mutations.swift, TaskOperationMutations.swift; Tests/FoundationModelsKanbanTests/Mutations/MoveColumnTests.swift (new), GraphQL/KanbanErrorTests.swift, GraphQL/AliasTableTests.swift; Tests/Fixtures/kanban.graphql; divergence.md (§25).
    - next: /review
  timestamp: 2026-10-25T10:36:26.364479+00:00
- actor: claude-code
  id: 01m5safvd85q58q8p09zcw7gd4
  text: |-
    ### implement — changed

    The coordinator's safety correction is done:
    - No before and no after now gives the new code MISSING_PLACEMENT (KanbanError.missingColumnPlacement), and the call writes nothing.
    - One bad ref beside a good ref: the call uses the good ref and adds the NEIGHBOR_NOT_FOUND warning for the bad ref.
    - No good ref: the call gives NOT_FOUND (nodesNotFound for two refs) and writes nothing.
    - The schema description and divergence.md §25 now tell the terminal rule.
    - The error tests compare full responses and check that the board did not change.

    Evidence: full `swift test` passed 1896 tests in 164 suites. The only warning is the SwiftPM "missing creator" warning. The golden SDL is up to date. The task stays in doing, with no commit.
  timestamp: 2026-10-25T10:42:50.408840+00:00
position_column: doing
position_ordinal: '80'
title: Add moveColumn to put a column between two neighbours in one write
---
## Request

KanbanViewKit asks for this. `UpdateColumnInput.order` is an integer sort key, and two columns with the same order sort by slug. When two neighbour columns have adjacent orders (for example 3 and 4), no integer is between them. Thus one `updateColumn` write cannot put a column between them. The client must then change the order of several columns, with several writes and several undo steps.

## Decision

Option (a) of the request: a positional mutation. It has the same form as the placement of `moveTask`, so that columns and tasks move the same way. One call gives one transaction, thus one `undoChange` reverses the full move.

```graphql
moveColumn(input: { id: ID!, before: ID, after: ID }): Column
```

- `id`, `before`, and `after` are column refs, with the same forgiving resolution as each other column ref (`RefResolver`: a full URI, `column/<slug>`, the slug, or a name).
- `after: X` puts the column directly after X. `before: Y` puts the column directly before Y. When the call gives both refs and they are neighbours, the column goes between them. When the call gives both refs and they are not neighbours, use the same rule as the `before`/`after` placement of tasks (`Placement`, `GraphQL/TaskOperationMutations.swift`). Record the rule in divergence.md.
- A ref that names no column: use the same behaviour as the task placement (`NEIGHBOR_NOT_FOUND` warning, divergence.md P1), so that the input stays forgiving.
- No `before` and no `after`: give the same result as the task placement for this case, or a clear error that tells the caller to give one ref. Choose the form that agrees with `moveTask`.
- A ref to the column itself, or a move that does not change the place: write nothing. The call is not an error.

## Renumber rule

- When an integer is between the orders of the two new neighbours, change only the order of the moved column. Use a value between the two orders.
- When no integer is between them (adjacent or the same orders), change the orders in the same transaction so that the board order is strict. Change as few columns as possible. Each other column keeps its place in the board order.
- After the move, no two live columns have the same order. Thus the order of the board does not depend on the slug tie.
- The terminal column is the column with the highest order. A move can make a different column terminal only when the caller puts a column after the terminal column. Record this in the schema description.

## Subtasks

- [x] Add `moveColumn` and `MoveColumnInput`, with schema descriptions and field aliases like the other column inputs (`GraphQL/ColumnActorMutations.swift`, `FieldAliases.swift`, `SchemaDescription+Mutations.swift`).
- [x] Keep `order` on `addColumn` and `updateColumn` with no change.
- [x] Tests (compare full responses):
  - Move a column between two neighbours with adjacent orders (for example 3 and 4). Check the full column list and orders after the move.
  - Move a column into a gap, where only the moved column changes.
  - Move a column after the terminal column, and before the first column.
  - Neighbours with the same order (a slug tie).
  - One `undoChange` of the move gives back all the orders as they were before.
  - A ref that names no column, and a move that does not change the place.
- [x] divergence.md: record `moveColumn`, the renumber rule, and the placement rules. Do not edit plan.md.

## Acceptance

- One `moveColumn` call puts a column at an exact place, also between columns with adjacent orders.
- One `undoChange` reverses the full move.
- `updateColumn(order:)` works as before.
- The full test suite is green, with no new warnings.
#kanbanviewkit