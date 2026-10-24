---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5nx254gb4jx31f8k4j86nv3
  text: 'Research: the live graph kept only a global event list, so a timeline read had to scan or replay it. Decision (recorded in divergence.md §23): LiveGraph keeps NodeLogs (events by node + undo targets). A load groups once, a commit merges its new events, a reload groups again. Task.timeline reads only the logs of the task and of its comments through NodeLogReading (a test counts the reads). The fold runs one transaction at a time (TransactionStep in Replay.swift) and folds again in id order only when a merge interleaves events. Values are the stored fields (TaskObject.storedFields, reuses FieldChange); the column is a MOVE entry with from/to Column. The undone state comes from the undo targets, so it is the same as Change.undone. after takes a cursor `<txn>:<place>` or a bare txn (forgiving, like history(since:)).'
  timestamp: 2026-10-24T02:50:26.832631+00:00
- actor: claude-code
  id: 01m5nxgjz5kc153403n4bbcpvn
  text: |-
    ### implement — changed
    - evidence: swift test: 1829 tests in 155 suites passed, 0 failed; only the accepted SwiftPM "missing creator" warning. 26 files: new Events/NodeLogs.swift, Undo/TaskTimeline.swift, GraphQL/SchemaDescription+Timeline.swift, Tests Undo/TaskTimelineTests.swift, Events/NodeLogsTests.swift; changed LiveGraph, RelatedBoards (BoardSource.logs), Commit, Replay (TransactionStep), UndoneState, ChangeBuilder (storedFields, UpdateKind init), Change (shared actor resolve), QueryResolvers, BrokenMergeDisplay (allComments), Schema, FieldAliases, KanbanTool (timeline example), divergence.md §23, kanban.graphql golden, and test helpers.
    - criteria: moves, field changes, comments with actor (timelineGivesMovesFieldsAndComments, ListMembers, CommentChanges); paging first/after (PagesWithFirstAndAfter, AfterTakesTransaction, NegativeFirst); reads only task + comment logs (timelineReadsOnlyLogsOfTaskAndComments with a counting reader on a board of 11 tasks); undone (MarksUndoneTransaction).
    - next: /review
  timestamp: 2026-10-24T02:58:19.749384+00:00
- actor: claude-code
  id: 01m5nxv7n275nzvr0xg3bt8d4w
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (f5e1f41). 4 findings (4 confirmed, 4 refuted): Sources/FoundationModelsKanban/Events/Replay.swift:119, Sources/FoundationModelsKanban/Undo/TaskTimeline.swift:69, Tests/FoundationModelsKanbanTests/Undo/TaskTimelineTests.swift:144, Tests/FoundationModelsKanbanTests/Undo/TaskTimelineTests.swift:211
    - next: Implement a correction for each open item in "## Review Findings (2026-10-23 21:59)". Then run the review again.
  timestamp: 2026-10-24T03:04:08.610162+00:00
- actor: claude-code
  id: 01m5nxvyap3esw9fahwbtvnggz
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 26 files, Task.timeline and NodeLogs, divergence.md §23
    - test: green — swift test, 1829 tests in 155 suites
    - commit: f5e1f41
    - review: findings — Sources/FoundationModelsKanban/Events/Replay.swift:119, Sources/FoundationModelsKanban/Undo/TaskTimeline.swift:69, Tests/FoundationModelsKanbanTests/Undo/TaskTimelineTests.swift:144, Tests/FoundationModelsKanbanTests/Undo/TaskTimelineTests.swift:211
  timestamp: 2026-10-24T03:04:31.830680+00:00
- actor: claude-code
  id: 01m5ny5x1sen5p4s1mpkpgr8fx
  text: 'Review findings corrected. (1) Replay.swift: removed the stored property `TransactionStep.txn`; nothing read it. The first event of a step gives the transaction. (2) TaskTimeline.swift: `TimelineCursor.init(parsing:)` uses the named constant `partCount` and reads the parts with `first` and `last`, so no index literals stay. (3) One `TaskOperationTests.doneMove(of:)` helper; RejectTaskTests and TaskTimelineTests both call it, and the two private copies are gone. TaskListMutationTests has an older inline move to done that this task did not add; it stays as it is. (4) `timelineGivesListMembers` now runs tagTask and then untagTask, and expects two FIELD entries, newest first: `removed` holds the tag id, then `added` holds the tag id. Checks: swiftlint `no_magic_numbers` (allowed 0, 1, -1, 100) reports nothing on the new files of the task; periphery reports nothing in them.'
  timestamp: 2026-10-24T03:09:58.201673+00:00
- actor: claude-code
  id: 01m5ny5xfkgc44k9cdh1c9hgb3
  text: |-
    ### implement — changed
    - evidence: swift build --build-tests: exit 0, only the accepted SwiftPM "missing creator" warning. swift test: 1829 tests in 155 suites passed, 0 failed. 5 files: Sources/FoundationModelsKanban/Events/Replay.swift, Sources/FoundationModelsKanban/Undo/TaskTimeline.swift, Tests/FoundationModelsKanbanTests/Mutations/TaskOperationTests.swift, Tests/FoundationModelsKanbanTests/Mutations/RejectTaskTests.swift, Tests/FoundationModelsKanbanTests/Undo/TaskTimelineTests.swift. 4 of 4 findings checked; 4 of 4 acceptance criteria checked.
    - next: /review
  timestamp: 2026-10-24T03:09:58.643687+00:00
position_column: doing
position_ordinal: '80'
title: 'Add Task.timeline: the history of one task with no full replay (KANBAN-13)'
---
## What

The full card of KanbanViewKit and the Task inspector of Testudo show the history of a task. The definition is KANBAN-13 in `../TestudoApp/features/packages/foundationmodels-kanban.md` (D45, D56).

Today `Board.history(filter:)` gives the changes of the board, and the filter tests each node update. There is no field on the task, and the call reads the history of the whole board.

## Work

- Add `Task.timeline(first:, after:)`: the entries of the history of the task, newest first, with paging.
- Each entry gives: the time, the actor, the `txn`, and the kind: a column move (from, to), a field change (name, before, after), or a comment (added, changed, removed, with the comment).
- Read only the log of the task and the logs of its comments. Do not replay the full event log of the board for each call.
- An undone transaction shows as undone, in the same way as `Change.undone`.
- Use the existing types of `S/Observe/Change.swift` (`FieldChange`, the actor resolve) where they fit. Do not make a second set of change types.
- Add schema descriptions, update the tool description, and record the shape in `divergence.md`.

## Acceptance criteria

- [x] `Task.timeline` gives the moves, the field changes and the comments of the task, with the actor of each.
- [x] Paging works with `first` and `after`.
- [x] The call reads only the logs of the task and of its comments (a test with a board of many tasks checks it, for example with a counting log reader).
- [x] An undone change shows as undone.

## Tests

- Unit tests in `T/` for each criterion.
- `swift test` passes with no new warnings. #kanbanviewkit

## Review Findings (2026-10-23 21:59)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 22 file(s) reviewed, 4 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `Tests/Fixtures/kanban.graphql` — no validator matches this file
> - `divergence.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/Events/Replay.swift:119` `code-hygiene/dead-code-swift` — var.instance `txn` is assignOnlyProperty.
- [x] `Sources/FoundationModelsKanban/Undo/TaskTimeline.swift:69` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Tests/FoundationModelsKanbanTests/Undo/TaskTimelineTests.swift:144` `reuse/reuse` — The new `doneMove(of:)` helper reimplements an existing helper with the same body. The new copy is a private static function in `TaskTimelineTests`, so the existing copy cannot be called from here. Two copies of the same test setup will drift apart. Move the shared body to one helper in `TaskOperationTests`, which already owns `taskField`, `moveInput`, and `doneSlug`. Have both `RejectTaskTests.doneMove` and this `doneMove` call it, or delete the copy that is not needed.
- [x] `Tests/FoundationModelsKanbanTests/Undo/TaskTimelineTests.swift:211` `completeness/inverse-operation-coverage` — The test name says the timeline gives the added and the removed members of a list field. The body only runs a tag mutation (add). No removal is run, so the removed side is never exercised. The expected JSON always has `removed: []`, so a bug in the removed-member path would still pass this test. Add a step that removes the tag (for example, the untag mutation, as `TaskOperationMutations` `untag` does) before the timeline query. Then expect a second FIELD entry whose `removed` list holds the tag ID. Or rename the test so it claims only the added members.
