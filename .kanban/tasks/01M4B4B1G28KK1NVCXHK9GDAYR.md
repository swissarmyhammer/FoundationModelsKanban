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
- actor: wballard
  id: 01m4by90pjgxfsh83dthnvaby2
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD; 2 findings (2 confirmed, 2 refuted) — Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift:102, Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift:153
    - next: Correct the 2 findings in the Review Findings (2026-10-07 14:40) section. Then run the review again.
  timestamp: 2026-10-07T19:43:34.098318+00:00
- actor: wballard
  id: 01m4by9a6v1bs72d5tz9s2dtr6
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 4 files (GraphQL/ColumnActorMutations.swift, MutationResolvers.swift, Schema.swift, ColumnActorTests.swift)
    - test: green — swift test, 616 passed, 0 warnings
    - commit: 36a507e
    - review: findings — Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift:102, Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift:153
  timestamp: 2026-10-07T19:43:43.835859+00:00
- actor: wballard
  id: 01m4byfya6www199y8stz95p4e
  text: |-
    Review findings (2026-10-07 14:40) corrected.
    - Finding 1: KanbanGraphTests.execute(_:variables:on:) now has `variables: [String: Map] = [:]`. Its 14 existing callers do not change. KanbanGraphTests.swift now imports GraphQL for Map. The ColumnActorTests helper (now respond(to:with:onFixtureIn:)) calls it after makeFixtureGraph.
    - Finding 2: new private helper makeFixtureGraph(in:) writes the fixture and makes the engine. respond, the no-write path, addedActorIsListed, and undeleteActor call it.
    - Same cause, other places in the file: failure(of:after:in:) and respondWritingNothing(to:after:in:) both had the same setup, signature snapshot, and no-write check. That is now one private helper runWritingNothing(after:in:_:).
    - Reuse: the body diff now comes from ReplayTests.diff(from:to:). The two copies of the "set + body edit" patch are now one helper, bodyPatch(of:setting:).
    - Other rules: the first argument of each helper now has a label (respond(to:), respondWritingNothing(to:), setting(name:order:), setting(name:color:)). Each member that only this file uses is now private. No line is longer than 120 characters.
    - Did not change: id(of:). QueryFixture.id(of:) uses DependencyMarkersTests.boardKey, not KanbanGraphTests.boardKey, so it is not the same work.

    ### implement — changed
    - evidence: swift test --filter 'ColumnActorTests|KanbanGraphTests': 32 tests in 2 suites pass. Full swift test: 616 tests in 38 suites pass, 0 compiler warnings.
    - files: Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift
    - next: /review
  timestamp: 2026-10-07T19:47:21.030285+00:00
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

## Review Findings (2026-10-07 14:40)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift:102` `reuse/reuse` — The new helper `execute(_:variables:onFixtureIn:)` repeats the body of the existing `KanbanGraphTests.execute(_:on:)`. That helper runs `graph.execute(query:variables:operationName:nil)` with fixed empty variables. The new helper is a near-match that was not extended. A parameter for the variables would let one helper serve both. Two parallel copies can drift apart. Give `KanbanGraphTests.execute(_:on:)` a `variables: [String: Map] = [:]` parameter, and call it from the new helper after `makeGraph`. Or keep only the fixture setup in `ColumnActorTests` and call the extended `KanbanGraphTests.execute` directly.
- [x] `Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift:153` `reuse/reuse` — The new helper `executeWritingNothing` repeats the fixture setup of the helper that sits beside it. Lines 153-154 write the fixture and make the graph, the same two steps as `execute` at lines 107-108. Two copies of the setup can drift apart. Move the fixture write and the graph creation into one private helper, such as `makeFixtureGraph(in:)`. Call it from `execute`, `executeWritingNothing`, and the other tests that need the same setup.