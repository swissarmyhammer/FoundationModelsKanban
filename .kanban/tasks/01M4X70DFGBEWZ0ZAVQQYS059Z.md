---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4xzjakwy3msxwn01edj596z
  text: |-
    Research done.
    - The apply path for the watcher is still `CommitSession.apply(watchedPaths:)` in Sources/FoundationModelsKanban/Tool/Commit.swift. `BoardEngine.apply(_:)` (Tool/BoardEngine.swift) calls it for each batch.
    - Today a full compare starts only when a path of the batch is the `.kanban/` directory (`EventLog.isBoardDirectory(at:)`). Other paths go to `LiveGraph.changedRefs(among:)`, which keeps only paths that `EventLog.ref(ofFileAt:)` maps to a node log. A path such as `.kanban/tasks` maps to no ref, so the batch changes nothing.
    - When a directory is moved away, the reported path does not exist on disk any more. Thus the check must not read the disk. Plan: add `EventLog.isNodeDirectory(at:)`: the name is the log directory name of a node type and the parent is the board directory. Share the type lookup with `ref(ofFileAt:)` so the logic is not copied. In `apply(watchedPaths:)`, a board directory or a node directory starts the full compare.
    - `LiveGraph.changedRefs()` (full) reads each node directory; a missing directory gives no refs and no error (`EventLog.items(in:)` uses `runIfPresent`).
    - FSEvents stream uses `kFSEventStreamCreateFlagFileEvents`; a directory rename reports the directory path only.
  timestamp: 2026-10-14T19:52:27.516082+00:00
- actor: claude-code
  id: 01m4xzvebvryqdk6kx648fc7yd
  text: |-
    Implementation landed (TDD).
    - RED: `nodeDirectoryBatchReadsEachChangedFile` failed with `applied → []`; `movedTaskDirectoryChangesLaterQuery` (real FSEvents, moves `.kanban/tasks` out to `<repo>/moved/.kanban/tasks`, appends a title there, moves it back) timed out on its wait for the expected query response. `fileBatchReadsOnlyThatFile` passed at once: it pins the existing single-file behavior (acceptance criterion 2).
    - GREEN: `EventLog.isNodeDirectory(at:)` (no disk read, so a moved-away path also counts) and a private `nodeType(ofDirectoryAt:)` that `ref(ofFileAt:)` now shares. `CommitSession.apply(watchedPaths:)` starts the full compare for the board directory or a node directory.
    - The watcher test waits for the effect (the query reaches the new title after an applied batch), not for any event. All new tests are in `BoardWatcherTests`, which has the `.watcherBudget` trait. Fixtures are temporary folders only.
    - Full `swift test`: 1223 tests in 90 suites passed; the only build warning is the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-14T19:57:26.267037+00:00
- actor: claude-code
  id: 01m4xzvh9d8a4eypk44nb7j6bh
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/Events/EventLog.swift, Sources/FoundationModelsKanban/Tool/Commit.swift, Tests/FoundationModelsKanbanTests/Observe/BoardWatcherTests.swift; `swift test` 1223 tests in 90 suites passed
    - next: /review
  timestamp: 2026-10-14T19:57:29.261282+00:00
position_column: doing
position_ordinal: '80'
title: Start the full compare when the watcher reports a directory inside .kanban
---
## What
divergence.md S7 (§7, and §15 "S7: fix"). The watcher can miss files when a tool moves a whole directory, because FSEvents can report only the directory. This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Change: in S/Tool/Commit.swift:346, a reported path that is a directory inside `.kanban/` (for example `.kanban/tasks/`) starts the full compare of the board files, the same as a report of `.kanban/` itself. This is part of the "file watch detection to allow manual poking of files" rule in §16.

## Acceptance Criteria
- [x] When `.kanban/tasks/` is moved away and back (or replaced by a different folder), the live graph shows the new task files.
- [x] A report of a single file still applies only that file.

## Tests
- [x] A test that moves `.kanban/tasks/` (for example rename it out, then rename a changed copy in) and checks that the live graph changes.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.