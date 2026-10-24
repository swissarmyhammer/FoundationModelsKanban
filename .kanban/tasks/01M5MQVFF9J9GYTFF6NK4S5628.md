---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5nrk32bmzka83wk6rvbzc4d
  text: |-
    Research done. Findings:
    - The template is commit 00a3101 (moveTasks, deleteTasks, undeleteTasks, divergence.md §20). Each mutation body runs in one `runMutation`/`changeNode` call, so all patches of the body are one transaction and one `undoChange` reverses them.
    - `moveTask` resolver (TaskOperationMutations.swift) uses `WorkingCopy.columnRef(forMoveTo:)`, `Graph.ordinal(placing:inColumn:moving:resolvingWith:)` and `WorkingCopy.move(_:to:placingAt:at:)` (fileprivate). `Placement` and `TaskPlaceInput` are internal and give the place fields; `SchemaBuilder.placeFields(describedBy:)` gives their schema.
    - `addComment` (CommentMutations.swift) writes `addNode(.comment(mintULID()), setting: [task, author], body:)`. The author default is `context.store.sessionActor.ref`.
    - Board order is `ColumnOrder(of:).slots`; the column where a task shows is `ColumnOrder.displaySlot(of:)`. The column before is the slot before that one.
    - Name rewrite (FoundationModelsExtras NameMatcher): step 1 exact name, then case/style, number, verb synonyms, alias table, one-letter spelling. No standard verb synonym names `reject`, and no mutation key is one letter from `rejecttask`, so the alias `rejectReview` -> `rejectTask` (byType "Mutation") names one mutation only. In `RejectTaskInput`, the `inEachInput` alias `comment` -> `body` does not apply, because the input has no `body` field; the exact name `comment` matches in step 1.
    - KanbanError needs two new cases: an empty comment, and a task in the first column with no `column`. The error lists of EndpointConventionTests and KanbanErrorTests must get them.
    - Plan: new file GraphQL/RejectTaskMutation.swift; a shared `WorkingCopy` helper for a comment node, used by addComment and rejectTask; tests in Tests/FoundationModelsKanbanTests/Mutations/RejectTaskTests.swift; divergence.md §21.
  timestamp: 2026-10-24T01:32:18.891767+00:00
- actor: claude-code
  id: 01m5ns81eb53yqyffvy1h14k0q
  text: |-
    Implementation landed (not committed).
    - New file Sources/FoundationModelsKanban/GraphQL/RejectTaskMutation.swift: `RejectTaskInput` (id, comment, column, ordinal, before, after; no board, no ifVersion), the resolver, `WorkingCopy.reject`, and `Graph.columnRef(before:namedBy:)` for the default column (the column before the display column in `ColumnOrder`).
    - The comment patch now comes from one shared helper `WorkingCopy.addComment(to:by:saying:at:)` in CommentMutations.swift; `addComment` and `rejectTask` both call it.
    - `KanbanContext.changeTask` and `WorkingCopy.move(_:to:placingAt:at:)` changed from fileprivate to internal, so that the new file can call them.
    - Two new error codes: `EMPTY_COMMENT` (the decode of the input throws it, so the field writes nothing) and `NO_PREVIOUS_COLUMN` (task in the first column with no column). A missing comment is `String!`, so it gives `GRAPHQL_VALIDATION_FAILED`.
    - Aliases: `rejectReview` -> `rejectTask` (Mutation table). `RejectTaskInput.comment` aliases: body, message, text, reason, feedback, note, notes. No tie: AliasTableTests rows and the rejectReview test pass with no AMBIGUOUS_NAME.
    - Schema descriptions, tool description, SDL golden (GRAPHQL_GOLDEN_RECORD=1), and divergence.md §21 are updated.
    - What did not work at first: the test helper dropped its `TemporaryDirectory`, so the engine lost its repo ("No such file or directory"). The helper now returns the directory in its tuple, the same as `TaskOperationTests.threeTasks(in:)`.
    - Discovery: the `changes` event lists the comment (CREATED) before the task (UPDATED).
  timestamp: 2026-10-24T01:43:45.355151+00:00
- actor: claude-code
  id: 01m5ns81v87d4attdvaah01sbg
  text: |-
    ### implement — changed
    - evidence: `swift test`: 1801 tests in 150 suites passed; only the accepted SwiftPM "missing creator" warning. 15 files: Sources/FoundationModelsKanban/GraphQL/RejectTaskMutation.swift (new), CommentMutations.swift, Errors.swift, FieldAliases.swift, Schema.swift, SchemaDescription+Mutations.swift, TaskOperationMutations.swift, Tool/KanbanTool.swift, Tests/Fixtures/kanban.graphql, Tests/FoundationModelsKanbanTests/Mutations/RejectTaskTests.swift (new), GraphQL/AliasTableTests.swift, GraphQL/KanbanErrorTests.swift, divergence.md, and the task files.
    - next: /review
  timestamp: 2026-10-24T01:43:45.768444+00:00
- actor: claude-code
  id: 01m5nsafap6pmv9g8cagh2jy6f
  text: |-
    ### test — green
    - evidence: swift build --build-tests and swift test. Swift Testing: 1801 tests in 150 suites passed, 0 failed, 0 skipped. XCTest: 0 tests, 0 failures. The only warning is the SwiftPM "missing creator" warning, which is accepted.
    - next: review
  timestamp: 2026-10-24T01:45:05.110789+00:00
- actor: claude-code
  id: 01m5nsga6s065jvhrt3zzwezkg
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (52e6e4a); 4 findings, 4 confirmed, 0 refuted — Sources/FoundationModelsKanban/GraphQL/FieldAliases.swift:116 (duplication/duplication), Sources/FoundationModelsKanban/GraphQL/FieldAliases.swift:116 (reuse/reuse), Tests/FoundationModelsKanbanTests/Mutations/RejectTaskTests.swift:115 (reuse/reuse), Tests/FoundationModelsKanbanTests/Mutations/RejectTaskTests.swift:139 (completeness/invariant-propagation)
    - next: implement the 4 open items in the "Review Findings (2026-10-23 20:45)" section. The task stays in review.
  timestamp: 2026-10-24T01:48:16.473078+00:00
- actor: claude-code
  id: 01m5nsh2sd3kvy3qmsjrx4zwt7
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 13 files, rejectTask with alias rejectReview, divergence.md §21
    - test: green — swift test, 1801 tests in 150 suites
    - commit: 52e6e4a
    - review: findings — Sources/FoundationModelsKanban/GraphQL/FieldAliases.swift:116 (2), Tests/FoundationModelsKanbanTests/Mutations/RejectTaskTests.swift:115, Tests/FoundationModelsKanbanTests/Mutations/RejectTaskTests.swift:139
  timestamp: 2026-10-24T01:48:41.645463+00:00
- actor: claude-code
  id: 01m5nssjbwzf23j7gvknf1522r
  text: |-
    Review findings fixed (not committed). The task stays in doing.
    - FieldAliases.swift: new private static func `taskPlacementWithoutBoard(merging:)`. `taskBlockPlacement` and `taskReject` both call it. No other copy of the board-removal step is in the file.
    - New shared test helper `KanbanGraphTests.runWithoutTransaction(_:on:)`, next to `withoutTransaction(_:)`. The private `run(_:on:)` copies in RejectTaskTests and TaskListMutationTests are removed. The one inline copy of the same expression, in TaskOperationTests (the untagTask test), now calls the shared helper. A search found no other copy of the helper in Tests/.
    - RejectTaskTests: new tests `rejectTaskPlacesTaskAfterNeighbor` (after the second task gives the order second, first, third; an append would give second, third, first) and `beforeAndAfterGiveConflictingPlacement` (expects `.conflictingPlacement(fields: ["before", "after"])` and no write, through `ColumnActorTests.failure`). The before test now also compares the full response. New helpers `rejectedResponse(of:inColumn:)` and `threeTasksWithFirstInDone(in:)`.
    - TDD note: the two new tests cover behavior that already exists, so they passed on their first run. A RED run was not possible.
    - Tool note: the `replace_all` option of the files edit op replaced only one match for each call. The Self.run call sites were changed with one perl substitution.
  timestamp: 2026-10-24T01:53:19.740744+00:00
- actor: claude-code
  id: 01m5nssjs2z7b61a691shf5rbc
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` exit 0; `swift test`: 1803 tests in 150 suites passed, 0 failed. The only warning is the accepted SwiftPM "missing creator" warning. 5 files: Sources/FoundationModelsKanban/GraphQL/FieldAliases.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift, Tests/FoundationModelsKanbanTests/Mutations/RejectTaskTests.swift, Tests/FoundationModelsKanbanTests/Mutations/TaskListMutationTests.swift, Tests/FoundationModelsKanbanTests/Mutations/TaskOperationTests.swift. 4 of 4 review findings are marked [x].
    - next: /review
  timestamp: 2026-10-24T01:53:20.162339+00:00
- actor: claude-code
  id: 01m5nsymjt96p9yas4841e59t1
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (24bf938): 0 findings, 0 confirmed, 0 refuted; 5 files reviewed. All 4 items in the 2026-10-23 20:45 Review Findings section are checked.
    - next: none. The task is in done.
  timestamp: 2026-10-24T01:56:05.850489+00:00
- actor: claude-code
  id: 01m5nsz3tv622rv7rhqj08fy28
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 5 files, the 4 findings fixed
    - test: green — swift test, 1803 tests in 150 suites
    - commit: 24bf938
    - review: clean — 0 findings, 4/4 earlier findings checked
  timestamp: 2026-10-24T01:56:21.467629+00:00
position_column: done
position_ordinal: ffb780
title: 'Add rejectTask: move a task back with a comment, in one transaction'
---
## What

The agent moves a task to Done itself, and the user does not accept each task (TestudoApp D92). The user can move a card back, with a comment that goes to the agent (D92 (e)). KanbanViewKit has the verb "reject with a comment" for this (its plan §3.4). There is no "accept" verb (decision of the user, 2026-10-23).

Today the client must send `moveTask` and `addComment` as two mutations.

## Work

- Add `rejectTask(input: {id, comment, column, before, after, ordinal})`.
- It adds the comment to the task (the actor of the call is the author) and moves the task, in one transaction. One `undoChange` reverses both.
- `comment` is required and must not be empty.
- The placement fields are the same as in `moveTask`. With no `column`, the task goes to the column before its current column in board order (from Done or Review, to the column before it). A task in the first column with no `column` gives a clear error.
- A move is never refused for a version conflict (KanbanViewKit D100): `rejectTask` takes no `ifVersion`.
- Add schema descriptions, update the tool description, and record the verb and the default column rule in `divergence.md`.

## Acceptance criteria

- [x] `rejectTask(input: {id, comment: "..."})` on a task in Done adds the comment and moves the task to the column before Done, in one transaction.
- [x] With `column: "doing"`, the task goes to Doing.
- [x] One `undoChange` removes the comment and moves the task back.
- [x] A missing or empty comment gives a clear error and writes nothing.
- [x] The `changes` event holds the moved task and the new comment.

## Tests

- Unit tests in `T/` for each criterion.
- `swift test` passes with no new warnings.

## Review Findings (2026-10-23 20:45)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 11 file(s) reviewed, 4 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `Tests/Fixtures/kanban.graphql` — no validator matches this file
> - `divergence.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/GraphQL/FieldAliases.swift:116` `duplication/duplication` — The new `taskReject` repeats the expression of the existing `taskBlockPlacement` (lines 106-107): `taskPlacement.filter { field != "board" }` followed by a `.merging(...)` of one extra alias table. The two blocks differ only by the merged value, so the shared step (drop the `board` alias from the placement aliases) is copied rather than named. The copies can drift: a change to how the `board` field is excluded must now be made in two places. Extract one helper, for example `private static func placementWithoutBoard(merging extra: [String: [String]]) -> [String: [String]] { taskPlacement.filter { field, _ in field != "board" }.merging(extra) { _, value in value } }`, and define `taskBlockPlacement` and `taskReject` as calls to it. Severity is low: the duplicated part is two short lines, so this is a judgment call. The `CodingKeys` pair flagged by the probe (RejectTaskMutation.swift:19 and TaskTransferMutations.swift:11) is a required key enum with different cases, so it is not reported.
- [x] `Sources/FoundationModelsKanban/GraphQL/FieldAliases.swift:116` `reuse/reuse` — The new taskReject alias table repeats the board-removal step of taskBlockPlacement. Both build taskPlacement.filter { field != "board" } and then merge one more entry. The same rule now exists in two places. A change to the placement aliases must be made in both, or the two tables can drift apart. Move the board-free placement aliases into one private static helper, for example taskPlacementWithoutBoard. Build taskBlockPlacement and taskReject from that helper, and merge the list or comment aliases into each.
- [x] `Tests/FoundationModelsKanbanTests/Mutations/RejectTaskTests.swift:115` `reuse/reuse` — The private helper `run(_:on:)` reimplements a wrapper that already exists. Its body, `KanbanGraphTests.withoutTransaction(try await CommentTests.run(field, on: graph))`, is the same as the `run(_:on:)` helper in TaskListMutationTests. Two copies of one wrapper will drift apart when the response shape changes. Move the wrapper to one shared place, for example a static helper on `CommentTests` or `KanbanGraphTests` next to `withoutTransaction`, and have RejectTaskTests and TaskListMutationTests both call it. Remove the two private copies.
- [x] `Tests/FoundationModelsKanbanTests/Mutations/RejectTaskTests.swift:139` `completeness/invariant-propagation` — The change makes rejectTask accept the same placement fields as moveTask (before, after, and column). Only the `before` path is tested. The `after` path and the CONFLICTING_PLACEMENT path (both before and after given) are not tested for rejectTask, so a broken sibling path would pass this suite. Add one rejectTask test that places the task after a neighbor, and one that passes both before and after and expects CONFLICTING_PLACEMENT with no write. This matches how moveTask is tested in TaskOperationTests.