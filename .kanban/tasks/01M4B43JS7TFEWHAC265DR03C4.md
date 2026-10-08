---
comments:
- actor: wballard
  id: 01m4chqkyjksznkz2fk4dgr7z3
  text: |-
    Research done. Findings:
    - Test infra to reuse: `ChangeBuilderTests.baseSession(inRepoAt:)` (fixture task + done column + alice/bob + tag bug), `ColumnActorTests.result(of:in:)` (runs a document in a `CommitSession`), `LiveGraphApplyTests.expectEqualToFreshLoad` / `canonicalNodes`, `CommitTests.makeSession(of:mintingFrom:)`, field builders in AddUpdateTaskTests / TaskOperationTests / CommentTests / TagMutationTests, `UndoTests.bodyField` / `lines(_:changing:to:)`, `GitSandbox` (BoardKeyTests) for real origin changes, `SplitMix64` (UnifiedDiffTests).
    - `PatchInput.changes(afterFolding:)` (Replay.swift) gives the part of a patch that changes the node. The property "each mutation writes only the properties that change" is `event.patch.changes(afterFolding: earlier events) == event.patch` for each line on disk.
    - A union merge is simulated on disk: copy `.kanban/` of a base repo to a second repo, run calls in each, then append to each main log the lines of the branch log that main does not hold.
    - ULID caution: `FixedULIDSource` restarts its sequence, so a second session on one log must use a later time step, or event ids repeat. Two branch sessions with different time steps give different ids; their short ids can still match, so branches do not add tasks.
    - Existing unit tests already cover each piece (TagResolveTests cycle walk, BrokenMergeDisplayTests, DiffApplyTests conflict block, EventTests stored form). The new Design tests run end to end through GraphQL on real log files.
  timestamp: 2026-10-08T01:23:35.506948+00:00
- actor: wballard
  id: 01m4cjwjemhgwcm5j0hfyr4b31
  text: |-
    Implementation landed (tests only; no production change).
    - New files in Tests/FoundationModelsKanbanTests/Design/: ReplayPropertyTests.swift (also declares the `Design` namespace, so `swift test --filter Design` selects the suites), MergeTests.swift, PortabilityTests.swift, SchemaChangeTests.swift. 19 tests.
    - Replay property: 200 sequences from seed 0x5EED_4E91, 6 random calls each (16 kinds: addTask, updateTask title/body/dependsOn, moveTask, completeTask, assign/unassign, tag/untag, delete/undelete, addComment, renameTag, undo, redo), 8 sequences at a time. Three checks: fresh load equals live graph; each log line is a `patch` event whose each part changes the node (independent oracle on NodeSnapshot, not `PatchInput.changes`); shuffled lines load to the same graph and event list. A guard expects that each kind of call wrote in some sequence.
    - Merge: union merge on disk (copy `.kanban/`, append the missing lines). Cases: tags of both branches; rename + add bug gives defect; different body lines; same line gives one conflict block that is the same in both merge orders, CONFLICT + `#CONFLICT`, body update removes it; dependency cycle (also blocked by a done task); task in a column that the other branch deleted shows in the first column; rename cycle (task tag and Board.tags).
    - Portability: real git repos (GitSandbox), new origin and new directory name; logs unchanged, whole-board query equals the old one with the key replaced, edges of the dependent task resolve; no log line holds the key or `kanban://`; a full URI with the current key is stored as a local ref.
    - Helper reuse: made `ColumnActorTests.qaSlug` internal; added `TaskOperationTests.actorInput(naming:)` (aliceInput now uses it) and `CommentTests.taskQuery(of:selecting:)` (respond(toQueryOf:) now uses it).
    - Fail checks (each mutation was reverted; `git diff -- Sources` is empty): LiveGraph.adopt drops an event -> fresh-load test fails; Commit keeps the whole patch -> changing-patch test fails; NodeLog without sort -> shuffle test and same-line merge-order test fail; PropertyBag add replaces members -> tags merge fails; strict unknown-key replay -> unknown property test fails; ordinal default changed -> default test fails; ColumnOrder without live check -> deleted-column test fails; readiness without cycle walk -> cycle test fails; rename walk returns nil on cycle -> both rename-cycle tests fail; rename walk does not follow -> rename+add test fails; edit applies to empty body with no CONFLICT -> different-lines, CONFLICT, and body-update tests fail; RefResolver stores current-key dependsOn as remote -> no-key, local-ref, and both move tests fail; a write after the move (test-side) -> no-log-change test fails.
    - No production bug found by the property tests.
  timestamp: 2026-10-08T01:43:46.388625+00:00
- actor: wballard
  id: 01m4cjwnvxwgbxrpsj3t41qt6n
  text: |-
    ### implement — changed
    - evidence: 7 files — Tests/FoundationModelsKanbanTests/Design/{ReplayPropertyTests,MergeTests,PortabilityTests,SchemaChangeTests}.swift (new), Tests/FoundationModelsKanbanTests/Mutations/{ColumnActorTests,CommentTests,TaskOperationTests}.swift (helper reuse). `swift test`: 874 tests in 56 suites passed (7.4 s). `swift test --filter Design`: 19 tests in 5 suites passed. `swift build --build-tests`: only the accepted SwiftPM "missing creator" warning. periphery: No unused code detected.
    - next: review
  timestamp: 2026-10-08T01:43:49.885183+00:00
depends_on:
- 01M4B406Z7RVSBJKKJ8KJW0CY2
- 01M4B40CFSF002B4DKM3T8J6GV
- 01M4B4B57JFX8HA0B45MMDQ1SQ
- 01M4B41VDXZ3NKEG4554PVXWQN
position_column: doing
position_ordinal: '80'
title: Merge, portability, and replay property tests
---
## What
The tests in plan.md §11 that check the whole design, not one feature.
- `Tests/FoundationModelsKanbanTests/Design/ReplayPropertyTests.swift`: random sequences of public mutations; a fresh load of the logs gives the same projection as the live graph after the writes. Each public mutation writes only `patch` events with only the properties that change.
- `Design/MergeTests.swift`: simulate `union` merges of two branches (concatenate the lines of both sides):
  - two branches add different tags to one task → both tags;
  - one branch renames `bug` to `defect` while the other adds `bug` to a task → after the merge, the task shows `defect`;
  - two branches change different lines of one body → both changes; the same line → one conflict block, `#CONFLICT`, and a `body` update removes it;
  - broken merged states (half of a dependency cycle on each side; a column deleted on one side while a task moves into it on the other; a rename cycle) replay without error and show as plan.md §5.3 says.
- `Design/PortabilityTests.swift`: no log line holds the key of its own board; change the `origin` (and, in a second test, the directory name): the log files do not change, each `id` has the new key, and all edges resolve. A full URI with the current key in the input is stored as a local ref.
- `Design/SchemaChangeTests.swift`: a log with an unknown property replays; a new property on an old node gives its default value.

## Acceptance Criteria
- [x] The property test runs at least 200 random sequences with a fixed seed and passes.
- [x] Each merge case gives the result that plan.md §5.3, §5.5, and §6.2 describe.
- [x] The repo move changes no log file and keeps all edges.

## Tests
- [x] The four test files above.
- [x] Run `swift test --filter Design`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.