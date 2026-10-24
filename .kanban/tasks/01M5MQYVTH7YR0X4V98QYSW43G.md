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

- [ ] `Task.timeline` gives the moves, the field changes and the comments of the task, with the actor of each.
- [ ] Paging works with `first` and `after`.
- [ ] The call reads only the logs of the task and of its comments (a test with a board of many tasks checks it, for example with a counting log reader).
- [ ] An undone change shows as undone.

## Tests

- Unit tests in `T/` for each criterion.
- `swift test` passes with no new warnings. #kanbanviewkit