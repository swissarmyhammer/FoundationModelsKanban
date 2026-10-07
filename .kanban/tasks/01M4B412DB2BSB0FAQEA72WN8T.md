---
comments:
- actor: wballard
  id: 01m4c7krq68y4fjcdbs31ha3by
  text: |-
    Research notes (implement step):
    - Inputs: before/after `BoardView` (Commit.swift `CommitSession.live.graph` before and after `run`) and the events of one txn (the new ids in `live.events`). `Graph.actor(for:)` in BrokenMergeDisplay.swift already resolves a tombstoned actor.
    - Design: `Observe/ChangeBuilder.swift` builds a `Change`; `Observe/Change.swift` holds `Change`, `NodeUpdate`, `FieldChange`, the enums `NodeType`, `UpdateKind`, `UpdateSource`, and the schema part. `actor` and `NodeUpdate.node` resolve against the graph of the context at read time ("the node now"), so a later delete of the actor gives the tombstone.
    - Each node object gives the values of its public fields (`trackedFields`). A field change is a compare of these values before and after. `created` and `updated` are not field changes, because each patch changes `updated` and `Change.at` gives the time. A tag rename sets `renamedTo`, which is not a public field, so the update of the old tag has no field change.
    - DERIVED updates: each live node with no patch in the txn whose tracked values changed (tasks and the board summary in practice).
    - No root field returns `Change` yet (history and subscriptions are later cards). Graphiti puts each registered type in the schema, so the types show in the SDL. Tests call the resolvers in Swift and compare each FieldChange with `node(id:)` queries before and after on a copy of the `CommitSession`.
    - `updates(type:node:)` can throw for an ambiguous id, so it returns an optional (the GraphQLSwift non-null rule). `Change.actor` stays non-null as in plan.md §4.1 and §5.3 step 5, the same as `Comment.author`.
  timestamp: 2026-10-07T22:26:43.558840+00:00
- actor: wballard
  id: 01m4c88r04a1v90dqhkyfg5cm0
  text: |-
    Implementation landed (TDD: the 12 tests of ChangeBuilderTests failed on assertions against stubs first, 116 issues; then all passed).
    - New: `Sources/FoundationModelsKanban/Observe/Change.swift` (`Change`, `NodeUpdate`, `FieldChange`, `UpdatesArguments`, enums `NodeType`/`UpdateKind`/`UpdateSource`, resolvers, `addChangeTypes()`), `Sources/FoundationModelsKanban/Observe/ChangeBuilder.swift` (`ChangeBuilder`, `TrackedValue`, `TrackedFields`, `trackedFields` of the six node objects).
    - Changed: `GraphQL/Schema.swift` (`NodeObject.trackedFields` requirement, `PublicSchema` adds `addChangeTypes()`), `GraphQL/QueryResolvers.swift` (`BoardView.nodeObject(at:)` is internal; `CommentObject.authorSlot` is shared by `Comment.author` and the change compare).
    - Test helpers made internal for reuse (no copies): `TaskOperationTests` (todoSlug, newColumnSlug, doneSlug, feature, aliceInput, taskField, moveInput, tagsInput), `TagMutationTests` (bug, defect, tagSelection, greenInput, addTag(named:), renameTag), `CommentTests` (body, editedBody, addComment), `ColumnActorTests.addQA`.
    - Decisions to know: `Change.actor` and `NodeUpdate.node` resolve against the graph of the call context ("the node now"), so `history` (^bqrz2pf) gets the tombstone of a later deleted actor. `ChangeBuilder.change(of:markingUndone:)` takes the undone state from the caller; ^bqrz2pf computes it. `created`/`updated` are not field changes; the old tag of a rename gets a PATCH update with no field change, because `renamedTo` is not a public field. `Change.updates` is nullable (it resolves the `node` filter and can throw); `Change.actor` stays `Actor!` as plan.md §4.1 says.
    - No root field gives `Change` yet; the types are in the SDL. History and subscriptions will expose them.
  timestamp: 2026-10-07T22:38:10.948290+00:00
- actor: wballard
  id: 01m4c88tswscb7v5mq5jc01xcx
  text: |-
    ### implement — changed
    - evidence: `swift test --filter ChangeBuilderTests` 12 tests (2 with 31 cases each) passed; `swift build --build-tests` + `swift test` 770 tests in 45 suites passed, only the accepted SwiftPM "missing creator" warning; `periphery scan --retain-public ... -- --build-tests --build-system native` no unused code. Files: Sources/FoundationModelsKanban/Observe/Change.swift, Sources/FoundationModelsKanban/Observe/ChangeBuilder.swift, Sources/FoundationModelsKanban/GraphQL/Schema.swift, Sources/FoundationModelsKanban/GraphQL/QueryResolvers.swift, Tests/FoundationModelsKanbanTests/Observe/ChangeBuilderTests.swift, Tests/FoundationModelsKanbanTests/Mutations/{TaskOperationTests,TagMutationTests,CommentTests,ColumnActorTests}.swift
    - next: /review
  timestamp: 2026-10-07T22:38:13.820855+00:00
- actor: wballard
  id: 01m4c8mqy6cx05kdjkwv2k2nzq
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (a34a66c): 3 findings (3 confirmed, 4 refuted). Sources/FoundationModelsKanban/Observe/ChangeBuilder.swift:263, Tests/FoundationModelsKanbanTests/Observe/ChangeBuilderTests.swift:322, Tests/FoundationModelsKanbanTests/Observe/ChangeBuilderTests.swift:331
    - next: Correct the 3 findings in the "Review Findings (2026-10-07 17:41)" section. Then do the review again.
  timestamp: 2026-10-07T22:44:44.102563+00:00
- actor: wballard
  id: 01m4c8n1vkr75gjpdn19fmzgvh
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 9 files (Observe/Change.swift, Observe/ChangeBuilder.swift, Schema, QueryResolvers, ChangeBuilderTests, TaskOperationTests, TagMutationTests, CommentTests, ColumnActorTests)
    - test: green — swift test, 770 passed; build warnings only the 2 accepted kinds
    - commit: a34a66c
    - review: findings — Sources/FoundationModelsKanban/Observe/ChangeBuilder.swift:263, Tests/FoundationModelsKanbanTests/Observe/ChangeBuilderTests.swift:322, Tests/FoundationModelsKanbanTests/Observe/ChangeBuilderTests.swift:331
  timestamp: 2026-10-07T22:44:54.259126+00:00
- actor: wballard
  id: 01m4c8tbnr2p2vp59ab2dkgxj8
  text: |-
    Review findings (2026-10-07 17:41) corrected:
    - Finding 1 (duplication): `ChangeBuilder.swift` has two new shared helpers. `GraphNodeObject.nodeFields(named:adding:)` adds the `name` entry. `BoardObject`, `ColumnObject`, and the label helper call it, so the `("name", .single(Map(name)))` entry has one copy now. `LabelObject.labelFields(withColor:)` gives `name` and `color`. `ActorObject.trackedFields` and `TagObject.trackedFields` call it with `Map(color)`. Why the color goes in as a `Map` argument: the `Color` associated type is `String?` for an actor and `String` for a tag, so a generic body in `LabelObject` cannot call the `Map` initializer. Each type converts its own color, and the shared helper has the field list.
    - Findings 2 and 3 (doc-parameter-naming): the cause was in 4 functions, not 2: `deleteDoneField`, `deleteAliceField`, `deleteBugField`, `renameBugField`. In each one, the `- Parameter refs:` entry is removed. The prose now says that the field does not read the refs of the case, so the parameter has no name. I did not name the parameter `refs`, because that gives an unused parameter, which periphery reports. All other `- Parameter` entries in `ChangeBuilderTests.swift` and `ChangeBuilder.swift` match their internal parameter names.
  timestamp: 2026-10-07T22:47:48.152839+00:00
- actor: wballard
  id: 01m4c8tdnq9c4fch904h90jmv0
  text: |-
    ### implement — changed
    - evidence: `swift test` 770 tests in 45 suites passed (ChangeBuilderTests suite passed, 2 tests with 31 cases each). The only build warning is the accepted SwiftPM "missing creator" warning from mlx-swift. Files: Sources/FoundationModelsKanban/Observe/ChangeBuilder.swift, Tests/FoundationModelsKanbanTests/Observe/ChangeBuilderTests.swift
    - next: /review
  timestamp: 2026-10-07T22:47:50.199124+00:00
depends_on:
- 01M4B3ZDK527CRVKQQRT87RGHJ
- 01M4B4AJGSQDJ4PCBP2W5XQJKR
- 01M4B406Z7RVSBJKKJ8KJW0CY2
- 01M4B40CFSF002B4DKM3T8J6GV
- 01M4B4B57JFX8HA0B45MMDQ1SQ
- 01M4B4B1G28KK1NVCXHK9GDAYR
position_column: doing
position_ordinal: '80'
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
- [x] For each public mutation, the `Change` has one `NodeUpdate` for each changed node, with the correct `kind`, and `FieldChange` values that equal a query before and after.
- [x] `completeTask` on A gives `DERIVED` updates for a task B that depends on A (`ready`, `blockedBy`, `virtualTags`) and for the board (`summary`); a tag rename gives `DERIVED` `tags` updates.
- [x] The `actor` of a `Change` made by an actor that was later deleted returns the tombstone.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Observe/ChangeBuilderTests.swift`.
- [x] Run `swift test --filter ChangeBuilderTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-07 17:41)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 9 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/Observe/ChangeBuilder.swift:263` `duplication/duplication` — The `trackedFields` body of `TagObject` repeats the `ActorObject` body verbatim: the same `nodeFields(adding:)` call with the same `name` and `color` entries. A later change to the tracked fields of one type could leave the other out of step, so the tracked-field list for name and color should live in one shared helper. Add one shared helper on `GraphNodeObject`, for example `nameAndColorFields`, that returns `nodeFields(adding: [("name", .single(Map(name))), ("color", .single(Map(color)))])`. Have both `ActorObject.trackedFields` and `TagObject.trackedFields` call it, and delete the second copy.
- [x] `Tests/FoundationModelsKanbanTests/Observe/ChangeBuilderTests.swift:322` `swift/doc-parameter-naming` — The doc entry names `refs`, but the parameter is `_: CaseRefs`, which has no internal name. The documented name matches neither the internal name nor an external label, so DocC cannot resolve it. Remove the `- Parameter refs:` entry and keep the prose that says the field does not read the refs. Or name the parameter `refs` in the signature and document it as `- Parameter refs:`.
- [x] `Tests/FoundationModelsKanbanTests/Observe/ChangeBuilderTests.swift:331` `swift/doc-parameter-naming` — The doc entry names `refs`, but the parameter is `_: CaseRefs`, which has no internal name. DocC cannot resolve the entry. Remove the `- Parameter refs:` entry, or name the parameter `refs` in the signature and document that name.
