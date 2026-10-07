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