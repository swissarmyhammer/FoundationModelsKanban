---
comments:
- actor: wballard
  id: 01m4cd7srbqznqcgrqv6r0jcqg
  text: |-
    Research notes (implement step):
    - Inputs: the global event list of the board (`WorkingCopy.liveEvents`, the committed log; the same list that `Board.history` reads). `UndoneState(of:)` gives the undone state. Only one board is loaded now (`KanbanGraph.session`), so "search only the loaded boards" is the current board. The `board` input of plan.md §4.2 is for the cross-repo card ^s3e6hrm; this card names only `txn` and `force`.
    - Inverse (plan.md §6.5): for each node of the target transaction, fold the node events of the transactions before the target (txn order, the same order as `History`) and fold again with the target events. The inverse is the net change back: `set` old / `unset`, `add` <-> `remove`, `delete` back, and the reversed body diff. A node with no events before the target is new: `delete: true` when a mutation made it explicitly, else no inverse.
    - The log does not record which field made a patch. The side-effect rule reads the `ops` of the target: a new node is explicit only when `ops` has a mutation that makes that node type (`addTask`, `addComment`, `addColumn`, `addActor`, `addTag`, `renameTag`). The board, the session actor of the transaction (the envelope `actor`), and the default columns of an auto-init (the board is new in the same transaction) are always side effects. A tag `delete: false` is a side effect unless `ops` has `addTag` or `undeleteTag`. These rules apply only to an original transaction; for an undo or a redo transaction each change is reversed.
    - Conflict: later transactions that are not undone, and that are not an undo or redo of a transaction after the target (their effect cancels a later change), and that change the same property, the same set member, or the tombstone state of the same node, or that make an edge to a node that the target made. Body: a conflict only when the reversed diff does not apply exactly (a new `UnifiedDiff` check that reuses the hunk applier of `DiffApply.swift`).
    - Graph rules: `COLUMN_NOT_EMPTY` before a column tombstone (inverse patches with a column delete run last), `DEPENDENCY_CYCLE` and `TAG_RENAME_CYCLE` after the patches. These checks are private helpers now; they become internal.
    - The written events get `undoes` through the event stamp. The result is the `Change` of the patches that the field kept (`ChangeBuilder`).
  timestamp: 2026-10-08T00:05:02.859227+00:00
- actor: wballard
  id: 01m4cdxqry6cnaqy7cgzpd33q5
  text: |-
    Implementation landed (TDD: UndoTests failed on assertions first, because the schema had no `undo` field; DiffApplyTests for `applies(exactlyTo:)` failed against a stub that gave `false`).
    - New: `Undo/Inverse.swift` (`InverseRule`, `BodyChange`, `NodeInverse`: the inverse table and the conflict test of one later patch), `Undo/UndoLog.swift` (`ReverseDirection`, `Sequence<Event>.groupedByTransaction()`, `UndoLog`: target, inverses, conflicts), `GraphQL/UndoMutations.swift` (`undo`/`redo` with `input UndoInput { txn: ID, force: Boolean }`, result `Change`, `BoardStore.reverse`, `WorkingCopy.reverse`, graph rule checks).
    - Changed: `Body/DiffApply.swift` (`UnifiedDiff.applies(exactlyTo:)` reuses the hunk applier), `Events/Replay.swift` (`NodeSnapshot`; `valueChanges`/`memberChanges` internal for reuse), `Tool/Commit.swift` (`apply(_:at:undoing:)` and `makeEvent(of:at:undoing:)` write `undoes`; `recording(operations:)` internal), `Undo/History.swift` (uses `groupedByTransaction()`), `GraphQL/Schema.swift` (adds `addUndoMutations()`), `MutationResolvers.swift` (`DefaultColumn` internal), `checkEmpty`, `checkNoCycle`, `checkNoRenameCycle` internal.
    - Tests: `Tests/.../Undo/UndoTests.swift` (21 tests; two of them run the 31 cases of `ChangeBuilderTests.mutationCases`), 3 new tests in `DiffApplyTests`. `ChangeBuilderTests.fixtureSession(inRepoAt:writing:)` is new; `baseSession` calls it.
    - Decisions to know: (1) The side-effect rule reads `ops` (see the research note). A call with `addColumn` and also a `moveTask` to a new column makes both columns explicit; the log cannot tell them apart. (2) `undoes` is only on the inverse patches of the field; the session actor patch of the same field has no `undoes`, and `UndoLog` takes the first non-nil `undoes` of a transaction. (3) A later undo/redo of a transaction after the target is not a conflict (it cancels a later change); this makes two undo calls in a row work when both calls changed the same property. (4) A forced undo of a body whose reversed diff does not apply writes the diff from the body now to the body before the transaction (undo wins), not a conflict block. (5) An inverse that changes nothing gives `NOTHING_TO_UNDO`. (6) A `txn` that is not in the log gives `NOTHING_TO_UNDO` (no other code fits in plan.md §4.4).
    - Discovery: the projection compare of the tests leaves out `Task.started`. `started` is the time of the first move out of the first column (plan.md §5.3 step 4); the log keeps that move after an undo, so an undo of `moveTask` does not clear `started`. All other tracked fields, `deleted` included, are equal after undo and after redo.
    - Known limit: two `undo` fields in one call both read the committed log, so the second field does not see the first one.
  timestamp: 2026-10-08T00:17:01.726300+00:00
- actor: wballard
  id: 01m4cdxvy8dmhgkg7tg926w29s
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` (only the accepted SwiftPM "missing creator" warning) + `swift test --skip-build`: 836 tests in 49 suites passed (UndoTests 21, DiffApplyTests +3). `periphery scan --retain-public --quiet -- --build-tests --build-system native`: no item in the new or changed source code (only the items that were there before). Files: Sources/FoundationModelsKanban/Undo/Inverse.swift, Sources/FoundationModelsKanban/Undo/UndoLog.swift, Sources/FoundationModelsKanban/GraphQL/UndoMutations.swift, Sources/FoundationModelsKanban/Undo/History.swift, Sources/FoundationModelsKanban/Body/DiffApply.swift, Sources/FoundationModelsKanban/Events/Replay.swift, Sources/FoundationModelsKanban/Tool/Commit.swift, Sources/FoundationModelsKanban/GraphQL/Schema.swift, Sources/FoundationModelsKanban/GraphQL/MutationResolvers.swift, Sources/FoundationModelsKanban/GraphQL/ColumnActorMutations.swift, Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift, Sources/FoundationModelsKanban/GraphQL/TagMutations.swift, Tests/FoundationModelsKanbanTests/Undo/UndoTests.swift, Tests/FoundationModelsKanbanTests/Body/DiffApplyTests.swift, Tests/FoundationModelsKanbanTests/Observe/ChangeBuilderTests.swift
    - next: /review
  timestamp: 2026-10-08T00:17:05.992288+00:00
- actor: wballard
  id: 01m4ce8vfhsgbqapar9jrsdf5g
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (b23b7d9): 1 finding (1 confirmed, 4 refuted) — Tests/FoundationModelsKanbanTests/Undo/UndoTests.swift:217 (reuse/reuse)
    - next: implement the finding in the 2026-10-07 19:19 Review Findings section, then review again.
  timestamp: 2026-10-08T00:23:05.969889+00:00
- actor: wballard
  id: 01m4ce947gxc410r3s4tgtpk1n
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 15 files (Undo/Inverse.swift, Undo/UndoLog.swift, GraphQL/UndoMutations.swift, History, DiffApply, Replay, Commit, Schema, MutationResolvers, ColumnActorMutations, TaskMutations, TagMutations, UndoTests, DiffApplyTests, ChangeBuilderTests)
    - test: green — swift test, 836 passed; build warnings only the 2 accepted kinds
    - commit: b23b7d9
    - review: findings — Tests/FoundationModelsKanbanTests/Undo/UndoTests.swift:217
  timestamp: 2026-10-08T00:23:14.928654+00:00
- actor: wballard
  id: 01m4cec0bqqj1fvw319mvp8jrs
  text: |-
    Finding `UndoTests.swift:217` `reuse/reuse` is fixed.
    - New helper `CommitTests.field<Value>(_ keyPath: KeyPath<TaskNode, Value>, of task: LocalRef, in session: CommitSession)`. It is beside `CommitTests.title`. It reads one field of a task from the live graph of a session through `LiveGraphApplyTests.task`.
    - `CommitTests.title(of:in:)` now calls `field(\.title, ...)`. The title helper stays because many tests in CommitTests and UndoTests call it.
    - `UndoTests.body(of:in:)` is removed. Its 2 call sites now call `CommitTests.field(\.fields.body, of: .task(...), in: session)`.
    - Search in UndoTests.swift, ChangeBuilderTests.swift and DiffApplyTests.swift: no other helper reads one field of a task from the live graph. `titleField`/`bodyField` make `updateTask` mutation text. They do not read the graph, so they are a different shape.
  timestamp: 2026-10-08T00:24:49.271953+00:00
- actor: wballard
  id: 01m4cec1re2g6wx2n1azevctnn
  text: |-
    ### implement — changed
    - evidence: 2 files — Tests/FoundationModelsKanbanTests/Tool/CommitTests.swift, Tests/FoundationModelsKanbanTests/Undo/UndoTests.swift. `swift test`: 836 tests in 49 suites passed. The only build warning is the accepted mlx-swift "missing creator" warning.
    - next: /review
  timestamp: 2026-10-08T00:24:50.702826+00:00
- actor: wballard
  id: 01m4ceh0984zmr312v37e79fnm
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (bc6f53a). 0 findings (7 validator runs, 0 failed). All prior Review Findings items are checked.
    - next: none. The task is in done.
  timestamp: 2026-10-08T00:27:33.032864+00:00
- actor: wballard
  id: 01m4ceh6fk24bsdr1sdt2p6gn0
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 2 files (CommitTests.swift, UndoTests.swift); 1/1 finding checked
    - test: green — swift test, 836 passed; build warnings only the 2 accepted kinds
    - commit: bc6f53a
    - review: clean — 0 findings
  timestamp: 2026-10-08T00:27:39.379899+00:00
depends_on:
- 01M4B41N13P82QC4H6BBQRZ2PF
- 01M4B406Z7RVSBJKKJ8KJW0CY2
- 01M4B40CFSF002B4DKM3T8J6GV
- 01M4B4B57JFX8HA0B45MMDQ1SQ
- 01M4B4B1G28KK1NVCXHK9GDAYR
position_column: done
position_ordinal: a880
title: Undo and redo in one board
---
## What
Reverse a transaction by appending inverse patches. The basis is plan.md §6.5 and §12 items 12 and 27.
- `Sources/FoundationModelsKanban/Undo/Inverse.swift`: the inverse table: `set` → `set` old or `unset`; `unset` → `set` old; `add` ↔ `remove`; `delete: true` ↔ `delete: false`; `edit body` → the reversed diff; first patch of a node that a mutation made explicitly → `delete: true`; a node made as a side effect (unknown tag, new actor, new column in `moveTask`, auto-init board, a tag made live by a marker) → no inverse.
- `undo(txn, force)` and `redo(txn, force)` mutations. No `txn`: `undo` takes the newest transaction of the session actor that is not undone and has no `undoes`; `redo` takes the newest `undo` of the session actor that is not reversed. Search only the boards that are loaded. The written patches have `undoes` = the reversed `txn`.
- Conflict: a later transaction that is not undone changed the same property (or set member), or made an edge to a node that the transaction made → `UNDO_CONFLICT` with the later transactions. For a body, a conflict only if the reversed diff does not apply. `force: true` writes the inverse anyway. Graph rules still apply. Nothing to undo → `NOTHING_TO_UNDO`.
- Result: the `Change` that `undo`/`redo` wrote.

## Acceptance Criteria
- [x] For each public mutation, `undo` gives the same projection as before the call (except side-effect nodes), and `redo` gives the projection after it.
- [x] Two `undo` calls in a row reverse the two newest original calls.
- [x] Undo of a body change after a later change to other lines works; a conflict gives `UNDO_CONFLICT`, and `force` writes anyway.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Undo/UndoTests.swift`: all cases of plan.md §11 that name undo in one board (including `deleteTask` → `undo` → `redo`, and the side-effect tag case).
- [x] Run `swift test --filter UndoTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-07 19:19)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 15 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsKanbanTests/Undo/UndoTests.swift:217` `reuse/reuse` — The new helper `body(of:in:)` repeats the shape of `CommitTests.title(of:in:)`. Both read one field of a task from the live graph of a session through `LiveGraphApplyTests.task`. The field is fixed in each helper, so each new field needs a new copy. A near-match that is not extended creates a parallel copy. Make one helper that takes the field as a key path, for example `field<Value>(_ keyPath: KeyPath<...>, of task: ULID, in session:)`, and place it beside `CommitTests.title`. Then `title` and `body` are both calls to that helper. If the task fields are not one type, keep the two helpers and state in a doc comment why they differ.
