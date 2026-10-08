---
comments:
- actor: wballard
  id: 01m4cxqpsethf2d0afz8c294wx
  text: |-
    Research done. Findings:
    - Each public mutation goes through `BoardStore.runMutation(named:at:_:)` (initBoard, updateBoard) or `BoardStore.changeNode(named:at:_:)` / `KanbanContext.changeNode` (all node mutations, incl. `changeTask` and `changeDeleted`). Undo uses `runMutation` on the current board only (cross-board undo is ^s3e6hrm).
    - `BoardStore` holds one `WorkingCopy` (current board). `RelatedBoards` holds read-only `BoardSnapshot` values that the engine installs from `relatedBoards.mapValues(\.session.snapshot)`. A related board that is not enabled is still loaded (empty live graph), so auto-init in `runMutation` works on a working copy of it.
    - `CommitSession.commit` already locks through `EventLog.lock(sortedByKey:)`, which takes a `[BoardKey: EventLog]` dictionary. Two copies of one repo have the same key, so a dictionary drops one lock.
    - `Event.boards` exists (`[String]?`, nil for one board). `ChangeBuilder` already reads it.
    - `RefResolver` with the key of the target board already gives a local ref for a URI of its own key and `.remote(uri)` for a different key, so the stored-ref rule holds when the resolver of a field uses the key of the board that the field writes to.
    - `BoardStore.knownSessionActor` is computed for the current board only. addTask in a related board needs the value of that board.
    Plan: per-board working copies in `BoardStore`, one shared `EventStamp` (same txn, increasing ids) moved between the working copies, `ops` recorded in the working copy of the current board, and one generalized `CommitSession.commit` that locks, checks, appends and adopts each changed board. The engine gets the committed related sessions back through a second closure.
  timestamp: 2026-10-08T04:53:21.326460+00:00
- actor: wballard
  id: 01m4cypb9m5sk9m1z5fvynsazk
  text: |-
    ### Design choices (not in plan.md)
    - Each related board that a call changes gets its own working copy in `BoardStore.relatedWork`, by the canonical path of its repo. All working copies of a call use one `EventStamp`, so they share one `txn` and the event ids increase across the boards.
    - The `ops` of the call are recorded in the working copy of the current board, and each board writes the same `ops` list.
    - There is one commit path: `CommitSession.commit(_:along:)`. It locks each changed board in key order, then in path order for two copies with the same key. Then it checks each board, appends to each board, and adopts each new live graph.
    - `boards` holds the sorted keys of the other changed boards. It does not hold a key that is the same as the key of the board, and it is `nil` when the call changes one board.
    - The engine gets the new sessions of the related boards through a closure (`RelatedBoardStore`). Thus the file watcher of a related board finds no change for the write of this process.
    - `knownSessionActor` moved from `BoardStore` to `WorkingCopy`, so that the actor rule of `addTask` applies in each board.
    - `renameTag`: a full URI in `from` names its own board. The `board` field applies only when `from` is a name or a slug.
    - `MutationBoard` gives the board of a mutation: `.named(board field)` for a new node, and `.holding(id)` for an existing node (the key of a full URI).
    - The test "A query on a related repo with no .kanban/ writes nothing" passed before the change, because the existing read path already wrote nothing.
  timestamp: 2026-10-08T05:10:05.364565+00:00
- actor: wballard
  id: 01m4cypdas3yw12vk9m0srwj38
  text: |-
    ### implement — changed
    - evidence: new files CrossRepoWriteTests.swift and CrossRepoFixture.swift; changed Commit.swift, Schema.swift, MutationResolvers.swift, ColumnActorMutations.swift, TaskMutations.swift, TaskOperationMutations.swift, TagMutations.swift, CommentMutations.swift, UndoMutations.swift, RelatedBoards.swift, BoardLock.swift, KanbanGraph.swift, CrossRepoReadTests.swift, EventLogTests.swift. `swift build --build-tests`: no new warnings. Periphery: no unused code. Full `swift test --skip-build` 3 times: 932 tests in 61 suites pass each time (about 7 s each).
    - next: /review
  timestamp: 2026-10-08T05:10:07.449378+00:00
- actor: wballard
  id: 01m4cz0jp3p4066mvc9r08cq5t
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (85198b5); 1 finding (1 confirmed, 1 refuted) — Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoFixture.swift:37 (reuse/reuse)
    - next: implement the open item in "Review Findings (2026-10-08 00:12)", then review again.
  timestamp: 2026-10-08T05:15:40.611076+00:00
- actor: wballard
  id: 01m4cz0tektg0xk6dtdfh13nf3
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 12 source files and 4 test files (new CrossRepoWriteTests.swift and CrossRepoFixture.swift)
    - test: green — swift test 3 runs with a 120 s limit, 932 passed each; build warnings only the 2 accepted kinds
    - commit: 85198b5
    - review: findings — Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoFixture.swift:37
  timestamp: 2026-10-08T05:15:48.563416+00:00
- actor: wballard
  id: 01m4cz8mwm0hqc7kvck6nehq4g
  text: |-
    Review finding reuse/reuse (CrossRepoFixture.swift:37) is fixed.
    - New shared test helper `GitGraphFixture.makeGraph(at:locatedBy:recordedBy:)` in Tests/FoundationModelsKanbanTests/Tool/GitGraphFixture.swift. `locatedBy` defaults to `.default` and `recordedBy` defaults to `nil`. It is now the only test helper that connects `BoardKey.read(fromRepoAt:)` to a `KanbanGraph`.
    - Removed `CrossRepoFixture.makeGraph` and `Design.PortabilityTests.makeGraph(at:)`. PortabilityTests, CrossRepoReadTests and CrossRepoWriteTests call `GitGraphFixture.makeGraph` now. The CrossRepoFixture doc comment names the new helper.
    - I searched the whole test target for `BoardKey.read(fromRepoAt:)` and `readingKeyWith:`. No other helper builds a KanbanGraph with the git key reader. `BoardLocatorTests.scan(around:with:)` connects the reader to a `BoardLocator` scan, not to a KanbanGraph, so it stays as it is.
    - Tool note: in the `files` tool, `edit file` with `replace_all: true` changed only the first match each time. Each match needed its own edit.
    - No test assertion or test behavior changed.
  timestamp: 2026-10-08T05:20:05.012517+00:00
- actor: wballard
  id: 01m4cz8qh4ybs74hrhk15dg1qy
  text: |-
    ### implement — changed
    - evidence: new Tests/FoundationModelsKanbanTests/Tool/GitGraphFixture.swift; changed CrossRepo/CrossRepoFixture.swift, CrossRepo/CrossRepoReadTests.swift, CrossRepo/CrossRepoWriteTests.swift, Design/PortabilityTests.swift. `swift build --build-tests`: pass, only the accepted SwiftPM "missing creator" warning. `swift test --skip-build` 3 times with a 120 s limit: 932 tests in 61 suites passed each time (about 7.0 s each).
    - next: /review
  timestamp: 2026-10-08T05:20:07.716251+00:00
- actor: wballard
  id: 01m4czf3rwtxvngawgtygbk0m6
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (2925688). 0 findings, 0 confirmed, 0 refuted. 5 files reviewed. All prior findings are checked.
    - next: none. The task is in done.
  timestamp: 2026-10-08T05:23:36.860314+00:00
- actor: wballard
  id: 01m4czf914p9317d3jwycbe1nx
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 5 test files (new Tool/GitGraphFixture.swift); 1/1 findings checked
    - test: green — swift test 3 runs with a 120 s limit, 932 passed each; build warnings only the 2 accepted kinds
    - commit: 2925688
    - review: clean — 0 findings
  timestamp: 2026-10-08T05:23:42.244751+00:00
depends_on:
- 01M4B421JA8K0E8GAC3EMWCZ5Z
- 01M4B4002GZV6E43G5CQ74BJNZ
position_column: done
position_ordinal: b180
title: 'Cross-repo writes: board field, enable, multi-board commit'
---
## What
Change related boards in one call. The basis is plan.md §6.6 and §5.4 (multi-board locks). The cross-board cycle check and cross-board undo are in a separate task.
- The optional `board` field on `initBoard`, `updateBoard`, `addTask`, `addColumn`, `addActor`, `addTag`, `renameTag`. A mutation on an existing node finds its board from the node.
- Enable a related repo: the first mutation on a repo with no `.kanban/` initializes its board (auto-init). A query on such a repo writes nothing.
- One call, many boards: one `txn`; each patch records the keys of the other boards in `boards`; locks in key order; the session actor rule in each board; a patch in board A that points to board B holds the full URI of the node with the current key of B.

## Acceptance Criteria
- [x] `addTask(board: "<related>")` writes to the related log; a related repo with no `.kanban/` gets a board on its first mutation.
- [x] One call that changes two boards writes one `txn` to both, and each patch has the key of the other board in `boards`.
- [x] A `dependsOn` edge from board A to board B is stored as a full URI with the key of B; no log line has the key of its own board.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoWriteTests.swift`, with two temporary git repos side by side.
- [x] Run `swift test --filter CrossRepoWriteTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-08 00:12)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 16 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoFixture.swift:37` `reuse/reuse` — The new `CrossRepoFixture.makeGraph(at:locatedBy:recordedBy:)` repeats the existing `PortabilityTests.makeGraph(at:)`, which already wraps `KanbanGraphTests.makeGraph` with the same `BoardKey.read(fromRepoAt:)` key reader. The new helper is a near-match that was written beside the old one, not an extension of it, so the key-reader wiring now lives in two places. Keep one `makeGraph` helper with the `locatedBy` and `recordedBy` parameters, and have the Portability helper call it (or move the parameters into the shared fixture and make the Portability call site use it). Do not change the unmarked Portability code in this change unless the merge is wanted; the fixture can at least delegate to a single shared definition.
