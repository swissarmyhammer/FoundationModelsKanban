---
comments:
- actor: wballard
  id: 01m4czse88rnw712t83tgsn0t4
  text: |-
    Picked up. Research done. Findings:
    - The one commit path is `CommitSession.run` -> `runReading` -> `commit(_:along:)`. It locks and checks only the boards with kept patches. A board that a graph rule only reads is not locked now, so the cross-board cycle rule of §5.4 step 4.4/5.1 is open.
    - `WorkingCopy.checkNoCycle` uses `Readiness(of: graph, inBoard: key).cycle(throughTaskAt:)` with `RelatedBoards.unavailable`. Thus a cycle through a different board is not found. `Readiness.cycle` has no other caller.
    - The field bodies get only `(work, resolver, time)`. The store holds the related boards as the run sees them (`BoardStore.reading`).
    - `undo`/`redo` (`BoardStore.reverse`) run on the current board only, with `runMutation(named:at:)`, and record `boards: nil` in the Change. `UndoInput` has no `board` field.
    - `RelatedBoards` holds the session of each loaded related board by canonical path; `BoardStore.target(of:)` resolves a board key and records a load request when the board is not loaded.
    - `KanbanGraph.close()` stops the file watchers, and a later call still reads the graphs in memory. Two engines on the same repos, with the watchers of the second one closed, give a deterministic stale read for the concurrent cycle test, with no timing.
    Plan: (1) a cross-board dependency walk that reads the other boards through `RelatedBoards` and records the canonical path of each board it reads in the working copy; (2) the commit locks and checks the read boards too (one commit path, read-only boards get a working copy with no patches); (3) `reverse` searches the current and the loaded boards, then reverses the transaction in each board of its `boards` list in one field, all or nothing, with `NOT_FOUND` for a missing board; (4) `board` field on the undo input.
  timestamp: 2026-10-08T05:29:15.272101+00:00
- actor: wballard
  id: 01m4d0n6gpnzgq83d6n15htv64
  text: |-
    ### Design choices (not in plan.md)
    - Cross-board cycle walk: new `DependencyWalk` (Derived/DependencyWalk.swift) replaces `Readiness.cycle(throughTaskAt:)`. It reads the board of the field from the working graph, and each other board from `RelatedBoards`. It records the canonical path of each other board that it reads. `WorkingCopy.checkNoCycle` uses it.
    - The `DEPENDENCY_CYCLE` path shows a task of the board of the field as `^shortid`, and a task of a different board as its full URI.
    - `WorkingCopy` gets `otherBoards` (the related boards as the graph rules of a field read them; `runField(as:reading:_:)` and `runField(as:on:reading:_:)` set it at the start of each field) and `readBoards` (the paths that a graph rule of a kept field read).
    - One commit path: `CommitSession.run` adds a working copy with no patch for each read board that the run did not change (`readOnlyWork`), and `commit(_:along:)` locks and checks each board that has patches or that a graph rule read. Only the changed boards are appended. The engine stores the session of each read board after the attempt, so a rerun sees the changed files.
    - `undo`/`redo`: the store searches the board of the `board` input field, else the current board and the loaded related boards (`BoardStore.loadedTargets`), takes the newest target, and reads the `boards` value of the transaction for the other boards. `BoardStore.runField(as:inEach:_:)` runs the field in each board one after the other, and restores all working copies when one board throws (all or nothing). A board where the inverse writes nothing is not an error; the field gives `NOTHING_TO_UNDO` only when no board changed. The returned `Change` is the change of the first board, with the node updates of the other boards added.
    - `KanbanGraph.relatedBoards(updating:...)` now installs the loaded related boards also when the run asks for no board. Before, a run with no request got no loaded board, so `undo` with no `txn` could not search the loaded boards.
    - Dead code removed: `BoardStore.runMutation(named:at:_:)` (current board only) and `ReverseRequest`. `Event.recording(operations:boards:)` is now `recording(operations:changing:inBoard:)`, shared by the commit and the undo change.
    - Tests: `KanbanGraphTests.makeGraph` and `GitGraphFixture.makeGraph` get a `mintingFrom` parameter, and `GitGraphFixture.secondEngineIDs` gives a second engine ids that sort after the first engine. Two engines with one `FixedULIDSource` mint the same ids, and then an undo of engine 2 wrote events with the txn of the original call (first failure of the `undo(txn:, board:)` test).
    - The concurrent cycle test is deterministic: the second engine loads both boards and then `close()` stops its file watchers, so only the commit check under the locks can see the write of the first engine. A mutation check (lock only the changed boards) made this test fail, so the read-board lock is load-bearing.
  timestamp: 2026-10-08T05:44:24.854527+00:00
- actor: wballard
  id: 01m4d0n9ph7ff63qr9bhxhxe98
  text: |-
    ### implement — changed
    - evidence: new Sources/FoundationModelsKanban/Derived/DependencyWalk.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoUndoTests.swift (5 tests), Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCycleTests.swift (2 tests); changed Tool/Commit.swift, Tool/KanbanGraph.swift, GraphQL/Schema.swift, GraphQL/UndoMutations.swift, GraphQL/TaskMutations.swift, GraphQL/MutationResolvers.swift, CrossRepo/RelatedBoards.swift, Derived/Readiness.swift, Tests/.../Tool/KanbanGraphTests.swift, Tests/.../Tool/GitGraphFixture.swift. All 7 new tests failed first on assertions. `swift build --build-tests`: only the accepted SwiftPM "missing creator" warning. Periphery: no unused code. Full `swift test --skip-build` 3 times with a 120 s limit: 939 tests in 63 suites passed each time (about 9 s, 15 s, 9 s).
    - next: /review
  timestamp: 2026-10-08T05:44:28.113406+00:00
- actor: wballard
  id: 01m4d10nfd1xqqpyjmfz99mpvt
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (17ff8b9), 3 findings (3 confirmed, 1 refuted) — Sources/FoundationModelsKanban/GraphQL/UndoMutations.swift:154, Sources/FoundationModelsKanban/GraphQL/UndoMutations.swift:210, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoUndoTests.swift:141
    - next: Do the 3 items in "Review Findings (2026-10-08 00:47)". Then run the review again. The task stays in review.
  timestamp: 2026-10-08T05:50:40.621644+00:00
- actor: wballard
  id: 01m4d111mvdg8x5hrkv32bmkv7
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 13 files (new Derived/DependencyWalk.swift, CrossRepoUndoTests.swift, CrossRepoCycleTests.swift)
    - test: green — swift test 3 runs with a 120 s limit, 939 passed each (9.98 s, 11.33 s, 14.93 s); build warnings only the 2 accepted kinds
    - commit: 17ff8b9
    - review: findings — Sources/FoundationModelsKanban/GraphQL/UndoMutations.swift:154, Sources/FoundationModelsKanban/GraphQL/UndoMutations.swift:210, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoUndoTests.swift:141
  timestamp: 2026-10-08T05:50:53.083049+00:00
- actor: wballard
  id: 01m4d1em7t1eb32kqh8edx44wk
  text: |-
    ### Review findings 2026-10-08 00:47: what changed
    - Finding 1 (try?): the new `BoardStore.reverseTarget(of:named:in:)` in UndoMutations.swift uses `do throws(KanbanError) { ... } catch .nothingToUndo { return nil }`. All other errors go to the caller unchanged. `newestTarget` uses it. `UndoLog.target(of:named:by:)` throws only `.nothingToUndo` today, so no behavior changes and no extra redo error test is necessary. I also checked the other `try?` in the files of the last commit. Schema.swift `node(for:readingFirst:)` had `try? view(ofBoardNamed:)`, which hid every board lookup error. It now catches only `.boardNotFound`. These `try?` stay, because each error that they discard is the expected "not a URI" or "not this board" case: `NodeURI(parsing:)` in Schema.swift and MutationResolvers.swift (all NodeRefError means "not a URI"), and the `storedRef(... .board)` probe in `resolution(ofBoardNamed:)` (all errors mean "not the current board"; the next lookup reports `boardNotFound`).
    - Finding 2 (reuse): `Change.replacingNodeUpdates(_:)` in Observe/Change.swift is the only full copy of the fields. `keeping(only:)` (History.swift) and `adding(updatesOf:)` (UndoMutations.swift) call it.
    - Finding 3 (redo coverage): new test `redoWithBoardReachesBoardThatIsNotLoaded`. Engine 1 adds a lib task and closes. Engine 2 runs `undo(txn, board)` and closes. Engine 3 (new `GitGraphFixture.thirdEngineIDs`) runs `redo(txn: <undo txn>, board)`. The test asserts `delete == false` and `undoes == undo txn`. The `txn` of redo is the undo transaction, because that is the transaction that redo reverses. RED: before I added the redo call, the test failed with 2 issues. GREEN after the redo call.
    - Engines are closed now: each test in CrossRepoUndoTests and CrossRepoCycleTests closes each engine that it makes (new private helpers `addLibTask(withEngineClosedIn:)`, `reverse(_:transaction:onNewEngineIn:mintingFrom:)`, `addAndUndoLibTask(in:)`).
    - Timing: the Swift Testing total is about 9.7 to 10.8 s. The suite "Design: replay of random public mutation sequences" (about 9 to 10 s) sets that total, not the cross-repo tests (about 4 to 5 s in parallel).
  timestamp: 2026-10-08T05:58:18.106461+00:00
- actor: wballard
  id: 01m4d1eq7pyrrd7skpbg74pawt
  text: |-
    ### implement — changed
    - evidence: Sources/FoundationModelsKanban/GraphQL/UndoMutations.swift, Sources/FoundationModelsKanban/GraphQL/Schema.swift, Sources/FoundationModelsKanban/Observe/Change.swift, Sources/FoundationModelsKanban/Undo/History.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoUndoTests.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCycleTests.swift, Tests/FoundationModelsKanbanTests/Tool/GitGraphFixture.swift. `swift build --build-tests`: only the accepted SwiftPM "missing creator" warning. Periphery on Sources: no findings. Full `swift test --skip-build` 3 times, 120 s limit: 940 tests in 63 suites passed each time (9.695 s, 9.676 s, 10.772 s test time; 22.74 s, 15.88 s, 17.21 s wall time).
    - next: /review
  timestamp: 2026-10-08T05:58:21.174504+00:00
depends_on:
- 01M4B433B8HKKXX0A08K77YCNF
- 01M4B42D1RWYD5DV5CSMBNXMJ3
position_column: doing
position_ordinal: '8180'
title: 'Cross-repo: cycle check and cross-board undo'
---
## What
The cross-board rules that need many boards at one time. The basis is plan.md §3.3 rule 6, §6.5 (Scope, Many boards), and §6.6.
- `DEPENDENCY_CYCLE` across boards: the check reads all boards on the path; the commit check of §5.4 covers these boards (lock them and compare signatures).
- `undo`/`redo` of a transaction that spans boards: reverse it in each board, in one call. If one board is not found, write nothing and return `NOT_FOUND` with the board name.
- `undo`/`redo` with no `txn` search the current board and the loaded boards only, and do not load other boards. The `board` input field selects a board for `undo(txn:, board:)` in a board that is not loaded.

## Acceptance Criteria
- [x] One call that changes two boards is reversed by one `undo`.
- [x] With one board missing, `undo` gives `NOT_FOUND` and writes nothing.
- [x] Two processes that add the two halves of a cross-board cycle at the same time: one call gets `DEPENDENCY_CYCLE` after its commit check.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoUndoTests.swift` and `CrossRepoCycleTests.swift`, with two temporary git repos side by side.
- [x] Run `swift test --filter CrossRepoUndoTests` and `--filter CrossRepoCycleTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-08 00:47)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 13 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/GraphQL/UndoMutations.swift:154` `completeness/public-output-contract` — `try?` discards every error from `log.target(of:named:by:)`, not only the expected 'this board has no target' case. A malformed or otherwise failing lookup in one board is treated the same as an empty board. The caller then gets `NOTHING_TO_UNDO`, or the search silently moves to another board, and the real cause is hidden from the operator. Catch only the error that means 'no target in this board' and rethrow the others, for example with `do { ... } catch KanbanError.nothingToUndo { return nil }`, so that other errors reach the caller unchanged. If `target` throws only that error, make the search depend on its typed error rather than on `try?`.
- [x] `Sources/FoundationModelsKanban/GraphQL/UndoMutations.swift:210` `reuse/reuse` — The new Change.adding(updatesOf:) copies all eight fields of Change into a new Change, and changes only nodeUpdates. The same full field copy already exists in History.swift as Change.keeping(only:). The two copies differ only in how nodeUpdates is set. A second copy of the memberwise rebuild means that a new field of Change must be added in both places, or one copy drops it. Add one shared helper on Change, for example `func replacingNodeUpdates(_ updates: [NodeUpdate]) -> Change`, in Observe/Change.swift or History.swift. Then make keeping(only:) and adding(updatesOf:) call it. For example: `adding` becomes `replacingNodeUpdates(nodeUpdates + others.flatMap(\.nodeUpdates))`. This keeps one copy of the field list.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoUndoTests.swift:141` `completeness/inverse-operation-coverage` — The change gives `undo` a `board` field that reaches a related board that is not loaded. Only the undo direction is tested. `redo` shares the same `reverse` path and the same `boards(of:foundIn:)` and `searchedBoards(namedBy:)` lookups, but no test runs `redo` with a `board` field. The inverse direction of the new capability is unproven. A regression in redo's board lookup would pass the suite. Add a test that reverses the transaction with `undo` and a `board` field, then runs `redo` with the same `txn` and `board` field on an engine that has not loaded the related board. Assert that the redo event restores the task in the related repo.
