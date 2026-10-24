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
position_column: doing
position_ordinal: '80'
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