---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4zdw3makpf1z9bhbkq1cnz7
  text: |-
    Research done. Findings:
    - The multi-board commit already exists. BoardStore (S/GraphQL/Schema.swift) has runField(as:in:) for one target board and runField(as:inEach:) for many boards, with a restore of `work` and `relatedWork` on failure. All patches of one call share one stamp, so one txn. The commit records the keys of the other changed boards in `boards` of each event, so the cross-board undo (UndoMutations.swift) reverses both boards with no new code.
    - Source board: MutationBoard.holding(id). Target board: MutationBoard.named(board). target(of:) gives .current or .related(RelatedWork).
    - A related Rust board stops each call that reaches it with INCOMPATIBLE_BOARD (KanbanGraph.checkUnreadableBoards). The move must write nothing then.
    - TaskMutations.swift `write(_:toTask:inBoard:at:)` makes marker tags, applies the task patch, runs the cycle check, and gives the dependency warnings. It is fileprivate now; the plan is to make it and TaskChange internal for reuse.
    - ensureLiveTag (TagMutations.swift) makes a missing tag with a name and color, or makes a tombstone live.
    - Task.assignees reads only resolved slots, so an assignee stored as a remote URI (the card rule) does not show in Task.assignees on the target board. This is the decided behavior of the card; a follow-up task records the read side.
    Plan: new file S/GraphQL/TaskTransferMutations.swift with copyTask, plus a `board` field on MoveTaskInput. When `board` names the same board as the task, moveTask does the old in-board move (forgiving).
  timestamp: 2026-10-15T09:21:42.538874+00:00
- actor: claude-code
  id: 01m4zew3tazjxytkzzkyg6m5w7
  text: |-
    Implementation landed. Notes for the next agent:
    - New file S/GraphQL/TaskTransferMutations.swift: `copyTask`, `TaskPlacementFields` + `TaskPlacementInput` (shared input fields of MoveTaskInput and CopyTaskInput, with a `board` field), `BoardStore.transfer(_:as:at:)`, `BoardStore.isBoard(_:holdingTask:)`, `TaskCopy`, `StoredRef.carried(from:to:)`, `WorkingCopy.addCopy` and `retire`.
    - `BoardStore.runAtomically(_:)` (Schema.swift) keeps all steps of one field or none; `runField(as:inEach:)` now uses it.
    - `moveTask`: `column` is now optional (no column keeps the column where the task shows). A `board` that names the board of the task does the old in-board move. A different board calls the transfer.
    - The transfer writes the new task first (its URI is needed for the pointer line), then the body line "Moved to <uri>" and the tombstone on the old board. One stamp, so one txn; the commit records `boards`, so the existing cross-board undo reverses both boards with no undo change.
    - `TaskChange` and `WorkingCopy.write` in TaskMutations.swift are now internal, for reuse (marker tags, cycle check, dependency warnings).
    - Alias table: MoveTaskInput and CopyTaskInput share `taskPlacement`, with board aliases toBoard, targetBoard, destination, repo.
    - A related Rust board already stops the call with INCOMPATIBLE_BOARD (KanbanGraph.checkUnreadableBoards); the test shows no log of the current board changes.
    - TDD: CrossRepoTransferTests (15 tests) were RED first (fields missing from the schema), then GREEN. The test `moveTaskWithNoColumnKeepsColumn` was written after the optional-column code, so it did not fail first.
    Follow-up tasks: ^x020t0g (Task.assignees does not show a remote assignee URI), ^yf3bpss (decide what a move does with comments).

    ### implement — changed
    - evidence: `swift test` 1407 tests in 110 suites passed, 0 failures, only the accepted SwiftPM "missing creator" warning. Files: S/GraphQL/TaskTransferMutations.swift (new), S/GraphQL/TaskOperationMutations.swift, S/GraphQL/TaskMutations.swift, S/GraphQL/Schema.swift, S/GraphQL/SchemaDescription.swift, S/GraphQL/FieldAliases.swift, Tests/.../CrossRepo/CrossRepoTransferTests.swift (new), Tests/.../Mutations/TaskOperationTests.swift.
    - next: /review
  timestamp: 2026-10-15T09:39:11.306529+00:00
- actor: claude-code
  id: 01m4zfh32sj1qghtdh0knhnx14
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 8 files
    - test: green — swift test, 1407 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: ce587ff
    - review: findings — Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift:154, Sources/FoundationModelsKanban/GraphQL/TaskTransferMutations.swift:206, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoTransferTests.swift:45
  timestamp: 2026-10-15T09:50:38.681847+00:00
- actor: claude-code
  id: 01m4zgacgzmprm69f0e5z17v4q
  text: |-
    Review findings of 2026-10-15 04:43 fixed. Notes for the next agent:
    - Finding 1 (silent nil): a nil target means "the engine did not load the board yet; the store records a request and runReading (Tool/Commit.swift) runs the call again". The run loop reads store.requests, not the response, so a throw on that first run is safe: the run after the load replaces the response. New BoardStore.loadedTarget(of:holding:) in S/GraphQL/Schema.swift throws notFound(type, id) for a `.holding` board and boardNotFound(reference, searchRoots) for a `.named` board when target(of:) gives nil. isBoard now gives Bool, transfer gives TransferredTask (not optional), moveTask has no `return nil`, and changeTask (same file, same cause) throws notFound when changeNode gives nil. The GraphQL fields stay `TaskObject?` so the schema nullability does not change.
    - Discovery: the default fixture store reads RelatedBoards.unavailable, which resolves each unknown ref at once to not-found. To reach the "not loaded yet" path a test needs RelatedBoards.loadable. BoardStore.fixture(of:inBoard:reading:) and GraphQLEngineTests.makeContext(reading:) now take that value (default .unavailable).
    - Tests (TDD): unloadedTargetBoardGivesNotFound and unloadedTaskBoardGivesNotFound were RED (response had no errors), then GREEN. missingTargetBoardGivesNotFound and missingTaskGivesNotFound (real repos) passed at once: that path already threw.
    - Finding 2: dependencyOnTargetBoardBecomesLocal passed at once (existing behavior). Mutation check: with the `.remote` branch of StoredRef.carried changed to `return self`, the test failed with the full URI; the line is restored.
    - Finding 3: the `field` helper is gone; the suite uses CommentTests.nodeField (the builder that TaskOperationTests.taskField wraps; taskField takes a ULID, the suite has full URIs). The same cause in the file, the `columnField` helper, is replaced by TaskOperationTests.moveInput(to:).

    ### implement — changed
    - evidence: `swift test` 1412 tests in 110 suites passed, 0 failures, only the accepted SwiftPM "missing creator" warning. Files: S/GraphQL/Schema.swift, S/GraphQL/TaskTransferMutations.swift, S/GraphQL/TaskOperationMutations.swift, Tests/.../CrossRepo/CrossRepoTransferTests.swift, Tests/.../GraphQL/QueryFixture.swift, Tests/.../GraphQLEngineTests.swift.
    - next: /review
  timestamp: 2026-10-15T10:04:27.551472+00:00
depends_on:
- 01M4X6ZBTA66TCPVYM41QR0ACD
position_column: doing
position_ordinal: '80'
title: Add moveTask(board:) and copyTask to move or copy a task to a different board
---
## What
divergence.md Q21 (DECIDED: add it now; K1 not cut), E6 (DECIDED), G8, and §11 "Q21". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/). Code: S/GraphQL/TaskOperationMutations.swift.

Decided behavior:
- Add a `board` field on `moveTask` to move a task to a different board, and a new `copyTask` mutation to copy a task to a different board (with an optional target `column` and `before`/`after`, like `moveTask`).
- Write the events on both boards in one transaction, under the locks of both boards (take the locks in the fixed order of the host, so two sessions cannot deadlock).
- In the new task, each local ref (for example a `dependsOn` edge to a task on the old board, or an assignee) becomes a full `kanban://` URI where it points to the old board, so that the dependencies on the old board still resolve. Column refs map to the target board.
- E6: a move or a copy keeps all tags. Swift makes each missing tag on the target board. (This is different from Rust, which drops them.) A tag marker in the body also makes the tag on the target board.
- A move tombstones the old task. E6: a move also adds a line to the old task body that points to the new URI, so that dependents on the old board can find it.
- Undo of a move or a copy reverses both boards.
- A target board that is an incompatible (Rust) board gives `INCOMPATIBLE_BOARD` and writes nothing (see the Q6 task).

## Acceptance Criteria
- [x] `moveTask(id: X, board: "<other repo>")` makes the task on the other board and tombstones `X` on the old board, in one transaction.
- [x] The old task body has a line with the new task URI.
- [x] `copyTask(id: X, board: "<other repo>")` makes a copy and keeps `X`.
- [x] Dependencies of the moved task on the old board still resolve (as full URIs).
- [x] Missing tags are made on the target board.
- [x] `undo` of a move restores both boards.

## Tests
- [x] Move and copy across two repos.
- [x] Dependencies still resolve after a move.
- [x] Dependents on the old board (they find the pointer line; the old task is a tombstone, so it is ignored for readiness).
- [x] Undo of a move across boards.
- [x] A tag that the target board does not have is made there (edge tag and marker tag).
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-15 04:43)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 8 file(s) reviewed, 8 not reviewed.

> 8 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 8 file(s)

- [x] `Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift:154` `completeness/public-output-contract` — When the board of the task cannot be read, moveTask returns nil with no error. The GraphQL field is nullable, so the caller gets null and no error code. The resolver doc says it throws notFound when no live task has the id, and that an error gives null for this field only. The silent nil hides the error that the doc says must be raised. Throw the matching error instead of returning nil. Use `KanbanError.notFound(type: .task, reference: ...)` when the task is missing, and `KanbanError.boardNotFound(reference:searchRoots:)` when the named board is missing. Add a test that moves a task to an unknown board and asserts the error code, and one that moves a missing task and asserts notFound.
- [x] `Sources/FoundationModelsKanban/GraphQL/TaskTransferMutations.swift:206` `completeness/inverse-operation-coverage` — `StoredRef.carried(from:to:)` has two directions. The local-to-full-URI direction (line 204) is exercised by `dependenciesResolveAfterMove`. The remote-to-local direction (line 206), where a full URI that names the target board becomes a local ref, has no test in the reviewed files. A regression there would leave a dependency on the target board stored as a full URI on that board. Add one test in CrossRepoTransferTests: on the lib board, add a task that depends on a task in the app board, then move or copy the app task to lib and assert that the new task's `dependsOn` edge to the old lib-board task is now a local ref, so it resolves without a board prefix.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoTransferTests.swift:45` `reuse/reuse` — The new `field` helper builds a mutation call with an `input` argument and an `id` selection. This repeats the shape of the existing `taskField` helper, which takes the operation, task, input, and a selection. The copy is a near-match that was not extended. Call `TaskOperationTests.taskField(operation, of: task, with: input, selecting: "{ id }")`, or move a shared field builder to a common test helper and use it from both suites. Remove the duplicate `field` body.
