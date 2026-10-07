---
comments:
- actor: wballard
  id: 01m4c4z3s2ppt1yazq32htgc4v
  text: |-
    Research done.
    - New file GraphQL/TaskOperationMutations.swift holds the 8 mutations; Schema.swift adds `.addTaskOperationMutations()`. Some helpers in TaskMutations.swift (`nextOrdinal`, `columnRef`, `storedRef(of:)`, `tagRefs`) and ColumnActorMutations.swift (`nextColumnOrder`, `PatchValue.integer`) go from fileprivate to internal so that the new file can use them.
    - `WorkingCopy.apply` drops the parts of a patch that change nothing (`PatchInput.changes(afterFolding:)`). Thus assign/tag of an edge that exists, unassign/untag of an absent edge, and undelete of a live task write nothing with no extra code.
    - deleteTask/undeleteTask reuse `changeDeleted(to:ofType:as:context:_:)`. Readiness already ignores a dependsOn edge to a tombstone (plan.md §3.3 rule 3), which is the port of the Rust test_delete_removes_from_dependencies.
    - Rust move: a before/after neighbor that is not in the target column appends at the end. Decision here: a neighbor ref that names no task at all gives NOT_FOUND (the same as every other forgiving ref, plan.md §4.4 "the message must tell the model how to correct the call"); a live neighbor that is not in the target column appends at the end (the Rust rule).
    - Rust tag/untag with an empty list is an error. The error catalog of plan.md §4.4 has no code for it, and the GraphQL field returns the task, so the caller sees that nothing changed. Here an empty list writes nothing.
    - untagTask matches tags after the rename redirect: an edge or a marker whose tag ends at the same tag as the input is removed. A name that names no tag removes nothing (Rust test_untag_task_absent_tag_returns_thin_ack).
    - moveTask to a slug that no column has (live or tombstone) makes the column: name = slug words in title case, order = one more than the terminal column (Rust slug_to_name). A tombstoned column gives NOT_FOUND (use undeleteColumn).
  timestamp: 2026-10-07T21:40:29.602239+00:00
- actor: wballard
  id: 01m4c5bzbrz2j3y70cqcxp5ymc
  text: 'TDD RED: Tests/FoundationModelsKanbanTests/Mutations/TaskOperationTests.swift (34 test cases). `swift test --filter TaskOperationTests` compiles and fails on assertions (the 8 mutation fields are not in the schema yet). AddUpdateTaskTests helpers that the new suite reuses are now internal (doneColumn, alice, bob, addActors, unknownActor, markerSlug, unknownTask, updateTask, dependsOn, taskULIDs, lastPatch, actorRefs, tagRefs, list, addedTasks).'
  timestamp: 2026-10-07T21:47:31.064269+00:00
- actor: wballard
  id: 01m4c61j8crkcwdktpb0j19e6p
  text: |-
    ### implement — changed
    - evidence: `swift test --filter TaskOperationTests` gives 35 tests, all pass (RED first: the tests failed on their assertions before the mutations existed). `swift test` gives 758 tests in 44 suites, all pass. The build has no new warnings. Periphery (`-- --build-system native`) shows no finding in the changed files. No line is longer than 120 characters.
    - files: new `Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift` (8 mutations, 3 input types, `TaskPlacement`, `BoardStore.changeTask`, `WorkingCopy.columnRef(forMoveTo:)` / `move` / `untag`, `Graph.ordinal(placing:inColumn:moving:)`, `Slug.titleCaseName`). `Schema.swift` adds `.addTaskOperationMutations()`. Shared helpers became internal so that the new file uses them and does not copy them: `columnRef(atSlot:)`, `tasks(inColumn:excluding:)`, `nextOrdinal`, `storedRef(of:)`, `tagRefs(named:)` (TaskMutations.swift), `nextColumnOrder` and `PatchValue.integer` (ColumnActorMutations.swift). New `Graph.tagRef(redirectedFrom:)` (TagMarkers.swift) is now also used by `ensureLiveTag` (TagMutations.swift).
    - test fix: `threeTasks(in:)` now holds the temporary directory, so that the repo stays on disk while the test runs.
    - next: review
  timestamp: 2026-10-07T21:59:18.540979+00:00
- actor: wballard
  id: 01m4c6dzy8ebmwnnp505mh3eee
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (7ae963b); 3 findings (3 confirmed, 2 refuted) — Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift:119, Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift:416, Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift:455
    - next: correct the 3 open items in the "Review Findings (2026-10-07 17:02)" section, then review again. The task stays in review.
  timestamp: 2026-10-07T22:06:05.768163+00:00
- actor: wballard
  id: 01m4c6ecrzga8z3yzp55e6rmmg
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 8 files (GraphQL/TaskOperationMutations.swift, Schema, TaskMutations, ColumnActorMutations, TagMutations, Tags/TagMarkers, TaskOperationTests, AddUpdateTaskTests)
    - test: green — swift test, 758 passed; build warnings only the 2 accepted kinds
    - commit: 7ae963b
    - review: findings — Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift:119, Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift:416, Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift:455
  timestamp: 2026-10-07T22:06:18.911524+00:00
- actor: wballard
  id: 01m4c6hawnwwzdmp34jcgmm2bk
  text: |-
    Picked up the 3 open review findings. Research:
    - Finding 1 cause: each resolver reads `context.store` and `context.clock()` itself before `store.changeTask` / `store.changeNode`. The same prefix is in TaskOperationMutations (5 resolvers incl. changeAssignee), TaskMutations (addTask, updateTask), TagMutations (addTag, updateTag, renameTag), CommentMutations (addComment, updateComment), ColumnActorMutations (addColumn, updateColumn, addActor, updateActor, changeDeleted). Fix: `KanbanContext.changeTask(_:named:_:)` calls `store.changeTask` with `clock()`, and `KanbanContext.changeNode(named:_:)` calls `store.changeNode` with `clock()`. All resolvers use them.
    - Finding 2: `WorkingCopy.tagRefs` must keep a URI ref as is (no redirect, no ensureLiveTag), and a name needs its `TagName` for the `set` of the name. Thus the shared resolver helper gives a `TagReference` (`.node(LocalRef)` or `.name(TagName)`), with an `includingTombstones` parameter. `tagRefs` adds the tag of a `.name`. `untag` uses `TagReference.ref`.
    - Finding 3: `TaskPlacement` becomes `.end` or `.beside(LocalRef, side:)`, so `Graph.ordinal` finds the neighbor index one time before the switch on the side.
  timestamp: 2026-10-07T22:07:55.285114+00:00
- actor: wballard
  id: 01m4c6rza070r0nqzgym929gmp
  text: |-
    Fixed the 3 review findings (2026-10-07 17:02). All are checked.
    - Finding 1 (duplication, clock and store prefix): new `KanbanContext.changeNode(named:_:)` (ColumnActorMutations.swift) is the one place that reads `clock()` and calls `store.changeNode`. New fileprivate `KanbanContext.changeTask(_:named:_:)` (TaskOperationMutations.swift) resolves the task ref and calls `changeNode`. `BoardStore.changeTask` is removed, because no caller stays. All resolvers with the prefix now use the context helpers: moveTask, completeTask, changeAssignee, tagTask, untagTask, addTask, updateTask, addTag, updateTag, renameTag, addComment, updateComment, addColumn, updateColumn, addActor, updateActor, changeDeleted. The `let operation = ...` lines that only shortened the call line are gone.
    - Discovery: the `body` closure goes to the `BoardStore` actor. Through a helper, Swift 6 region isolation gives "sending 'body' risks causing data races". The fix is a `sending` parameter on the two context helpers.
    - Finding 2 (reuse, tag name-or-URI branch): new `RefResolver.tag(named:includingTombstones:) -> TagReference` (TaskMutations.swift) holds the one branch. `TagReference` is `.node(LocalRef)` for a URI or `.name(TagName)` for a name or a slug, and `ref` gives the local ref. `tagRefs` keeps the URI ref as is and adds or revives the tag of a name (the old behavior). `untag` uses `tag(named:includingTombstones: true).ref`. `RefResolver.tagRef(named:)` is removed.
    - Finding 3 (duplication, neighbor index guard): `TaskPlacement` is now `.end` or `.beside(LocalRef, side: NeighborSide)`. `Graph.ordinal(placing:inColumn:moving:)` finds the neighbor index one time in a guard before the switch on the side.
    - Not changed: `MutationResolvers.swift` (changeBoard) and `PatchSchema.swift` (patch) still read `context.clock()`. They are not in the named mutation files, and each has one call with a different shape.
  timestamp: 2026-10-07T22:12:05.568234+00:00
- actor: wballard
  id: 01m4c6s11zh5dacfmfcz5m0pep
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift, TaskMutations.swift, TagMutations.swift, CommentMutations.swift, ColumnActorMutations.swift. `swift build --build-tests` has no errors. `swift test` gives 758 tests in 44 suites, all pass. The only build warning is README.md kind 1 (`missing creator for mutated node ... mlx-swift_Cmlx.bundle`). No line is longer than 120 characters.
    - next: review
  timestamp: 2026-10-07T22:12:07.359430+00:00
depends_on:
- 01M4B4002GZV6E43G5CQ74BJNZ
- 01M4B3W0VAAWGYQ8F9621807Z9
- 01M4B4AQ1Z7DFQ4NP52RYF7RN1
position_column: doing
position_ordinal: '80'
title: 'Mutations: move, complete, assign, tag, delete tasks'
---
## What
The other task mutations. The basis is plan.md §4.2, §6 (moveTask, completeTask), and §6.1.
- `moveTask(id!, column!, ordinal, before, after)`: ordinal priority is an explicit `ordinal`, then `before`/`after` a neighbor, then append at the end. A missing column is created (name = slug in title case).
- `completeTask(id!)`: move to the terminal column, after the last ordinal there.
- `assignTask` / `unassignTask(id!, actor!)`: `add`/`remove` on `assignees`.
- `tagTask` / `untagTask(id!, tags!)`: `add`/`remove` on the tag edges; an unknown tag in `tagTask` writes a tag `set` patch; `untagTask` also removes a matching `#marker` from the body with an `edit` patch.
- `deleteTask` / `undeleteTask(id!)`: `delete: true`/`false`. An undelete of a live task writes nothing.

## Acceptance Criteria
- [x] Each move rule puts the task at the expected position.
- [x] `untagTask` on a marker tag removes the marker; a tag on an edge and in a marker stays until both are removed.
- [x] `deleteTask` hides the task in lists, and `undeleteTask` brings it back.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Mutations/TaskOperationTests.swift`: port the Rust move, complete, assign, tag, and archive dispatch tests (archive mapped to delete).
- [x] Run `swift test --filter TaskOperationTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-07 17:02)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 8 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift:119` `duplication/duplication` — The same three-line start is repeated in four task mutation resolvers. Each one takes the store, the clock, and the mutation name from the context, then calls store.changeTask with the task id and the same closure shape. A change to how the clock or the store is read must be made in every copy. Add one helper that takes the context, the id, the mutation name, and the body, and calls store.changeTask with context.clock(). Each resolver then keeps only its own body.
- [x] `Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift:416` `reuse/reuse` — The new RefResolver.tagRef(named:) repeats the name-or-URI branch of WorkingCopy.tagRefs(named:resolvingWith:at:). Both split a name from a tag URI, normalize the name with TagName(normalizing:), and resolve a URI with nodeRef(for:ofType: .tag). A future change to tag name rules must now be made in two places. Extract the shared branch into one resolver helper, for example one that takes includingTombstones and returns the LocalRef of a name or URI. Have tagRefs call it and then add the tag, and have tagRef(named:) call it with includingTombstones: true. Keep the add-or-revive step only in tagRefs.
- [x] `Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift:455` `duplication/duplication` — In Graph.ordinal(placing:inColumn:moving:), the .after case repeats the same guard as the .before case: look up the neighbor index in tasks, and return end when it is missing. Both copies must change together if the lookup rule changes. Extract a helper, for example func neighborIndex(of neighbor: LocalRef, in tasks: [TaskNode]) -> Int?, and call it from both cases. Alternatively, resolve the index once before the switch, since both cases need it.
