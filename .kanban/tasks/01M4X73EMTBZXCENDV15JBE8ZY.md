---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4yn9a79wgx8z7zk5vxz2van
  text: 'Research done. The line refs on the card are old. The same-board check now is `UndoLog.conflicts(with:of:readingBodiesWith:)` (S/Undo/UndoLog.swift), called from `WorkingCopy.reverse(_:forcing:inBoard:at:)` in S/GraphQL/UndoMutations.swift. `NodeInverse.conflicts(with:)` (S/Undo/Inverse.swift) finds a later edge only as a `.local` ref, so an edge from a different board (stored as `.remote(NodeURI)`) is never seen, and body markers are not read at all. Plan: in `BoardStore.reverse`, before `runField`, collect the URIs of the nodes that the inverse of each board tombstones; then for each loaded board (and each board of the transaction) with a different key, ask its `UndoLog` for later transactions (not undone, not an undo of a later txn, the same filter as `conflicts`) that add a `.remote` edge to such a URI, or whose body edit adds a dependency marker (`DependencyMarkers.all`) with such a URI. Pass those transactions into `WorkingCopy.reverse`, so one `UNDO_CONFLICT` lists the same-board and the cross-board ones, and nothing is written. Test helpers to use: `CrossRepoFixture.SideBySide`, `CrossRepoFixture.addTask(dependingOn:on:)`, `CrossRepoWriteTests.addLibTask`, `UndeleteCycleTests.logTexts(of:)`, `ErrorCoverageTests.expectFailure`.'
  timestamp: 2026-10-15T02:12:00.873299+00:00
- actor: claude-code
  id: 01m4ynkex7crr2vqe5dks13agf
  text: 'Implementation landed. RED: the two conflict tests failed (undo wrote with no error); the no-edge test passed at once, because it guards the old behavior. GREEN after the change. `BoardStore.reverse` now calls `laterReferences(to:tombstonedIn:)` before `runField` (skipped when `force: true`). It collects the full URI of each node that the inverse tombstones in each board of the transaction, then asks the `UndoLog` of each loaded board and each board of the transaction (each one time, `eachOnce`, now shared with `boards(of:foundIn:among:)`) for later transactions that refer to a URI of a different board: `UndoLog.references(to:after:)` finds a `.remote` edge (`PatchInput.makesEdge(to:)`, now takes a `StoredRef` and is internal) or a body edit that adds a dependency marker of the URI (fold of the task body before and after the transaction, `DependencyMarkers.all`). The later-transaction filter is now one helper, `UndoLog.isLaterChange(_:than:)`, used by both `conflicts` and `references`. `WorkingCopy.reverse` takes the list as `alsoConflictingWith:` and gives one `UNDO_CONFLICT` with the same-board and cross-board transactions, sorted and each one time. Note: a second worktree copy with the same key as the tombstoned node is not read by this check (its edges are stored as local refs); that is the X5/S8 area and not on this card.'
  timestamp: 2026-10-15T02:17:33.351983+00:00
- actor: claude-code
  id: 01m4ynkh6pgt0ggz4qrdm78ywx
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/GraphQL/UndoMutations.swift, Sources/FoundationModelsKanban/Undo/UndoLog.swift, Sources/FoundationModelsKanban/Undo/Inverse.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoUndoConflictTests.swift (new). `swift test`: 1294 tests in 102 suites passed; only the accepted SwiftPM "missing creator" mlx warning.
    - next: /review
  timestamp: 2026-10-15T02:17:35.702109+00:00
- actor: claude-code
  id: 01m4yp2226jh35tpy7y8p08j85
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 4 files
    - test: green — swift test, 1294 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: 52cc435
    - review: findings — Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoUndoConflictTests.swift:54
  timestamp: 2026-10-15T02:25:31.718585+00:00
- actor: claude-code
  id: 01m4yph31fkws6tzrt4ktejntj
  text: 'Finding CrossRepoUndoConflictTests.swift:54 (completeness/inverse-operation-coverage) is fixed. Two new tests: `forcedUndoWithLaterEdgeFromOtherBoardTombstones` and `forcedUndoWithLaterBodyMarkerFromOtherBoardTombstones`. Each makes the same example as `expectConflict`, sends `force: true`, and expects no errors, a tombstone (`delete: true`) for lib#X in the lib log, and `undoes` = call 1. A new helper `expectTombstone(forcing:addingY:)` holds that body, and the old no-edge test now calls it too (`forcing: false`), so the file has no copied block. The input closures are now `edge(to:)` and `bodyMarker(of:)`, shared by the conflict tests and the forced tests. RED was a mutation check: I made `BoardStore.reverse` ignore the force flag, and both forced tests failed with UNDO_CONFLICT. Then I reverted the mutation, and the production source is now the same as HEAD. Do not repeat this: my first mutation called `laterReferences` inside the `runField` closure, and Swift stopped with "Fatal access conflict detected" (exclusivity). Compute any store read before `runField`. GREEN: the suite has 5 of 5 pass. Full `swift test`: 1296 tests in 102 suites pass. The only warning is the accepted SwiftPM "missing creator" mlx warning.'
  timestamp: 2026-10-15T02:33:44.239520+00:00
- actor: claude-code
  id: 01m4yph4egsbz1j9aczpwrybhq
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoUndoConflictTests.swift. `swift test`: 1296 tests in 102 suites passed, 0 failed; only the accepted SwiftPM "missing creator" mlx warning.
    - next: /review
  timestamp: 2026-10-15T02:33:45.680982+00:00
position_column: doing
position_ordinal: '80'
title: Add the undo conflict check across boards
---
## What
divergence.md X6 and R13 (§1.1, §11 bugs; K7 stays as work). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem: undo has no conflict check across boards. The rule (§6.5 of the design): a later edge to a node that the undo would tombstone is a conflict. Now this check is for the same board only (S/GraphQL/UndoMutations.swift:260-271). Example: call 1 adds `lib#X`. Call 2 adds `app#Y`, which depends on `X`. `undo(call1)` gives no `UNDO_CONFLICT`. It tombstones `X`, and `Y` becomes READY with no warning.

Change: when an undo would tombstone a node, also look for later edges to that node from tasks on the other loaded boards (edges and body markers with the full URI of the node). If one exists, give `UNDO_CONFLICT` (the same error as in one board) and write nothing.

## Acceptance Criteria
- [x] In the example, `undo(call1)` gives `UNDO_CONFLICT` and writes nothing.
- [x] The same with a body marker in `app#Y` in place of the edge.
- [x] An undo with no cross-board edge to the node works as before.

## Tests
- [x] The example with an edge (this is also in the K14 missing tests).
- [x] The example with a body marker.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-14 21:21)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoUndoConflictTests.swift:54` `completeness/inverse-operation-coverage` — The `force` path skips the cross-board check: `reverse` passes `isForced ? []` to `laterReferences` and the field then writes the undo in every board. No test proves that a forced undo of a transaction with a later cross-board edge writes the inverse. The only conflict tests use the non-forced path, so a regression in the force branch would pass the suite. Add one cross-repo test that runs the same example as `expectConflict` with `force: true`. It should expect success, a tombstone for `lib#X` in the lib log, and `undoes` set to the first transaction.
