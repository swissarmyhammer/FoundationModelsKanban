---
comments:
- actor: wballard
  id: 01m4bxgy3qmnvbse8m2y3am83a
  text: |-
    Research done.
    - Rust tests to port: dispatch/tests/board_columns.rs (add, update, delete column, order), dispatch/tests/actors_tags.rs (add, update, delete, list actor, ensure), column/add.rs (duplicate, default order = max order + 1), column/delete.rs (not empty, not found), actor/add.rs (duplicate).
    - Difference from Rust: Rust addActor(ensure) updates a changed name or color. The card says ensure returns the existing actor and writes nothing. The card wins.
    - A resolver that throws a KanbanError gives a GraphQL error without extensions.code today (the code mapping is the task "Errors: code coverage through execute"). The tests read the KanbanError from GraphQLError.originalError, through a CommitSession run, as TaskQueryFixture.kanbanError does.
    - Plan: the new mutations go in GraphQL/ColumnActorMutations.swift, so MutationResolvers.swift stays a sensible size. runMutation and MutationName become internal. The board patch init becomes a shared node patch init (set values plus the body diff), so the body diff code is not copied.
    - COLUMN_NOT_EMPTY counts the live tasks that Column.tasks shows (ColumnObject.isHolder), so the count in the message is the count that the agent sees.
    - A slug that names a tombstone also gives DUPLICATE_ID: the agent must use undeleteColumn or undeleteActor. A patch on a tombstone would not make it live.
    - Not done here: null-to-clear for an update field (plan.md §6). BoardInput does not do it either. The tri-state input decode is a shared need of updateTask (task ^…0002GZV6E43G5CQ74BJNZ).
  timestamp: 2026-10-07T19:30:25.015408+00:00
- actor: wballard
  id: 01m4by0exnfby3r8snp7fp7s3b
  text: |-
    Implementation landed.
    - New file GraphQL/ColumnActorMutations.swift: the 8 mutations, their input types, BoardStore.changeNode, and the WorkingCopy add/update/setDeleted helpers. A delete of a column always checks plan.md §3.3 rule 5 in setDeleted.
    - MutationResolvers.swift: MutationName and runMutation are now internal. The board patch init is now the shared PatchInput(changing:setting:body:from:). New Graph helpers node(for:), hasNode(_:), body(of:); the session actor check uses hasNode.
    - Schema.swift: PublicSchema adds addColumnActorMutations().
    - Correction to the first comment: the updateTask task is ^q74bjnz.
    - Plan divergence: plan.md §8 names only MutationResolvers.swift for mutations. The column and actor mutations are in their own file in the same GraphQL/ directory, so the file size stays sensible.

    ### implement — changed
    - evidence: swift test --filter ColumnActorTests: 22 tests pass (22 failed before the code, RED). Full swift test: 616 tests in 38 suites pass, no compiler warning. periphery scan -- --build-system native: no finding in the changed files.
    - files: Sources/FoundationModelsKanban/GraphQL/ColumnActorMutations.swift (new), Sources/FoundationModelsKanban/GraphQL/MutationResolvers.swift, Sources/FoundationModelsKanban/GraphQL/Schema.swift, Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift (new)
    - next: /review
  timestamp: 2026-10-07T19:38:53.749732+00:00
depends_on:
- 01M4B3ZQXZ1DKR1FVBDRCK1FP8
position_column: doing
position_ordinal: '8280'
title: 'Mutations: column and actor create, update, delete'
---
## What
Column and actor mutations. The basis is plan.md §4.2 and §6.
- `MutationResolvers.swift` (column and actor part): `addColumn`/`updateColumn`/`deleteColumn`/`undeleteColumn(id, name, order, body)` and `addActor`/`updateActor`/`deleteActor`/`undeleteActor(id, name, color, body, ensure)`.
- `addColumn` or `addActor` with a slug that exists gives `DUPLICATE_ID`, except `addActor(ensure: true)`, which returns the existing actor and writes nothing.
- `deleteColumn` on a column with live tasks gives `COLUMN_NOT_EMPTY`. An undelete of a live node writes nothing. Slugs follow the slug rule (`INVALID_SLUG`).
- `body` input: an `edit` patch with the diff; nothing if the text is equal.

## Acceptance Criteria
- [x] Each mutation writes the patches of the plan.md §4.2 table and returns the node.
- [x] `addColumn` with an existing slug gives `DUPLICATE_ID`; `addActor(ensure: true)` with an existing slug writes nothing.
- [x] `deleteColumn` on a column with a live task gives `COLUMN_NOT_EMPTY` and writes nothing.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift`: port the matching Rust dispatch tests.
- [x] Run `swift test --filter ColumnActorTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.