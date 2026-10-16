---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m51qhn6zezme62pwmnvhdmhg
  text: |-
    Research done.

    - Engines are keyed by FolderIdentity (device and inode) in KanbanHost.engines. BoardEngine.root is a fixed `let`. The view tables (relatedBoards, SessionFeeds) and the change feed paths use root.canonicalPath as the key. Thus to "follow" a moved folder, root must change, and each view table must move. That is large. A reload at the new path gives the correct root with no change to the tables.
    - The old engine reads the new repo in two places: BoardEngine.apply (watcher batch, inside the gate) and the commit check (CommitSession.commit -> applyChangedFiles under the lock). It writes the new repo in CommitSession.commit. The view calls `admit` before each commit attempt, so `admit` is the place to stop a write.
    - A view keeps its current engine in boardState and its related engines in relatedBoards. A call does not resolve the current board again, and the related sessions go into each run from relatedBoards (withLoadedBoards). Thus a view can write through the old engine.
    - Deadlock rule (^je3gkw8): code that holds an engine gate must not wait for the end of a watch consumer task (BoardWatch.end). Use BoardWatch.stop. The host must not call engine.close (it calls end) from a path that a gate holder can reach.
    - ReplacedRepoTests and PathRepo (Tests/.../CrossRepo/ReplacedRepoTests.swift) give the fixture: a repo of a path ref outside the scan place, and replace() that moves the old repo to staging and makes a new repo at the same path. The helper newBoardChangesOfOldEngine gets the old engine through host.relatedEngine(ofBoardAt: oldFolder); after this change the host removes the old engine, so the helper must keep the old identity itself.
    - The 0nkvw6d tests need the subscribers of a view to move to the new engine of the path. So the old feed must not finish before the view moves them.

    Plan: the host retires an engine whose folder is not at its root any more (removes it from the table, stops its watcher with no wait, keeps its feed open). The engine checks its identity before each batch. The view checks its engines before each call and before it publishes, and puts the engine of the path in their place (or drops a related board that cannot load). `admit` refuses a commit to an engine whose folder moved, and the call runs again on the new engines (forgiving).
  timestamp: 2026-10-16T06:49:14.719179+00:00
- actor: claude-code
  id: 01m51rdkj7bdxskj1mjygsyhh5
  text: |-
    Implementation landed (TDD: 4 new tests failed first for the expected reasons, then passed).

    Decision (recorded in divergence.md §16, Gap 6): the host retires an engine whose folder is not at its root path any more. It does not follow the folder, because the root path is the key of the view tables and of the change feed. A later call that reaches the old folder at its new path loads a new engine. A view that still holds the old engine routes to the new engine (forgiving, the write is not lost).

    - BoardEngine: `isAtRoot` (one stat), `retire()` (stops the watch with `stop()`, no wait; feed stays open), new state `.retired`, `isClosed` became `isStopped` (closed or retired). `apply` checks `readsRoot()` before the read and before it stores; on a mismatch the engine retires and calls the new `reportRetirement` closure (EngineLoad).
    - KanbanHost: `retire(_:)` (table removal + engine.retire), `retireEngines(replacedBy:)` after each load, weak list of retired engines that `close()` closes.
    - KanbanGraph: `followingMovedBoards(_:)` wraps execute/subscribe; `followMovedBoards()` runs before each call and in `publish`; `admit` throws `MovedBoards` (new, BoardGates.swift) before a write to a moved engine; the call runs again (max 3 runs, then EventLogError.fileSystem). `resolveBoard` uses `feeds.replace` so subscribers of the current board move too.
    - SessionFeeds: `remove(forBoardAt:)` for a related board that cannot load at its path any more.
    - Tests: KanbanHostTests.movedEngineAppliesNoFileOfNewRepo; ReplacedRepoTests oldEngineDoesNotApplyNewBoard (card test), writeOfCurrentBoardGoesToNewRepo, writeDuringReplaceGoesToNewRepo. Helper `newBoardChangesOfOldEngine` now takes the old identity from the folder in staging, because the host lets go of the old engine. `EventLogTests.becomesTrue` now takes an async check (extended, not copied).

    Deadlock check: no retirement step waits for an engine gate or for a watch task. The engine calls the host from inside its gate the same way it calls `publish`; the host only edits its table and calls `retire()`, which uses `BoardWatch.stop()`.

    Interesting: the RED run of movedEngineAppliesNoFileOfNewRepo showed the old engine really applied the new repo's files (event count changed), so the bug was real, not only a theory.
  timestamp: 2026-10-16T07:04:30.535548+00:00
- actor: claude-code
  id: 01m51rdvhk5hbkcyrf2534hhne
  text: |-
    ### implement — changed
    - evidence: 9 files — Sources/FoundationModelsKanban/Tool/BoardEngine.swift, Sources/FoundationModelsKanban/Tool/KanbanHost.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Sources/FoundationModelsKanban/Tool/BoardGates.swift, Sources/FoundationModelsKanban/Observe/SessionFeeds.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanHostTests.swift, Tests/FoundationModelsKanbanTests/CrossRepo/ReplacedRepoTests.swift, Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift, divergence.md. `swift test`: 1567 tests in 126 suites passed; only the accepted SwiftPM "missing creator" warning.
    - next: /review (task stays in doing).
  timestamp: 2026-10-16T07:04:38.707594+00:00
- actor: claude-code
  id: 01m51seczzrzb8kyc7dcbmkdbv
  text: |-
    ### test - green
    - evidence: swift build clean (only the allowed SwiftPM "missing creator" warning). Full swift test: 6 runs. Run 1 and run 4 had only 60-second time-limit failures (machine load average about 120). The failing suites alone then passed (54 tests and 60 tests). Runs 2, 3, 5 passed 1567 tests in 126 suites, 0 failures, 0 skipped, no hang. ReplacedRepoTests and KanbanHostTests alone, 5 runs, 28 tests each, all passed. IntegrationTests with --scratch-path: 3 tests in 3 suites passed. No hang seen; no code changed.
    - next: review. Logs are in the scratchpad folder (full1..5.log, rk1..5.log, integ.log).
  timestamp: 2026-10-16T07:22:25.151349+00:00
- actor: claude-code
  id: 01m51sfs9nebbnw3h5m27c6gmq
  text: |-
    ### commit — changed
    - evidence: local commit "fix(host): close the engine of a replaced repo and send its calls to the new engine (^1yg0p73)". Files: BoardEngine.swift, KanbanHost.swift, KanbanGraph.swift, BoardGates.swift, SessionFeeds.swift, KanbanHostTests.swift, ReplacedRepoTests.swift, EventLogTests.swift, divergence.md, and the .kanban/tasks/ files. The sha is in git log. Not pushed.
    - next: review
  timestamp: 2026-10-16T07:23:10.517110+00:00
position_column: doing
position_ordinal: '80'
title: Stop the engine of a replaced repo from reading the files of the new repo at the same path
---
## What
Found during ^0nkvw6d. This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

When a user moves a repo away and makes a new repo at the same path, the host loads a new engine for the new folder identity. The old engine stays in `KanbanHost.engines` until the host closes. Its `root` is still the old path, and its file watcher (FSEvents, by path) stays on that path. Thus the old engine can apply the log files of the new repo to its old live graph, and its commit path writes to `<path>/.kanban/` of the new repo when a different view still holds the old engine.

^0nkvw6d makes each session view replace the engine of the path, and drop the changes of the old engine (`BoardChanges.identity`). The old engine itself still runs.

## Change
- Decide what the host does with the engine of a folder identity that is not at its path any more: close it and remove it from the table, or move its root to the new path of the old folder.
- A view that still holds the old engine must not write to the new repo.

## Acceptance Criteria
- [x] After a repo is replaced at the same path, no engine applies or writes the files of the new repo except the engine of the new folder identity.

## Tests
- [x] A test replaces the repo of a path ref, writes to the new board, and checks that the old engine does not apply the new log files.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.