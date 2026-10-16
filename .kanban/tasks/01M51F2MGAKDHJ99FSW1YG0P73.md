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
- actor: claude-code
  id: 01m51t2d1s4y8nc4g3mh0zwrhw
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (bd16070). 3 findings, 3 confirmed, 1 refuted. Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:253, Sources/FoundationModelsKanban/Tool/KanbanHost.swift:858, Tests/FoundationModelsKanbanTests/Tool/KanbanHostTests.swift:293. No finding is about concurrency (gate waits, lock order, or continuations).
    - next: Correct each open item in the "Review Findings (2026-10-16 02:23)" section. Then run /review again. The task stays in review.
  timestamp: 2026-10-16T07:33:20.569709+00:00
- actor: claude-code
  id: 01m51t2yxc9y5x79d6vq1r8q3g
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — BoardEngine, KanbanHost, KanbanGraph, BoardGates, SessionFeeds, 3 test files, divergence.md §16 Gap 6
    - test: green — swift test, 1567 passed (3 of 5 full runs; 2 runs had only 60 s time limits under load, failing suites passed alone); IntegrationTests 3 passed
    - commit: bd16070
    - review: findings — Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:253, Sources/FoundationModelsKanban/Tool/KanbanHost.swift:858, Tests/FoundationModelsKanbanTests/Tool/KanbanHostTests.swift:293
  timestamp: 2026-10-16T07:33:38.860838+00:00
- actor: claude-code
  id: 01m51v3j4tjb3b2dvn8gvvbt88
  text: |-
    Review findings (2026-10-16 02:23) corrected. All 3 items are now `- [x]`.

    - KanbanGraph.swift `duplication/duplication`: new private helper `runningOnBoard(postingPlansTo:_:)` holds the nesting `followingMovedBoards { holdingGates(startingWith:) { publishingChanges(of:postingPlansTo:) { ... } } }`. `execute` calls it with its context. `subscribe` calls `host.register(self)` first, then calls the helper with nil. The gate order is the same. The helper adds no wait inside the gate. The closure is a non-escaping `@Sendable`, the same as the other helpers. No other copy of the nesting is in the file.
    - KanbanHost.swift `reuse/reuse`: `WeakView` and `WeakEngine` are replaced by one `private struct Weak<Object: AnyObject> { weak var object: Object? }`. `views` is `[ObjectIdentifier: Weak<KanbanGraph>]` and `retiredEngines` is `[Weak<BoardEngine>]`. No typealias. `SubscriberPlace` in ChangeFeed.swift also holds a weak reference, but it also holds an id and is in a different file. I did not change it.
    - KanbanHostTests.swift `reuse/reuse`: `movedEngineAppliesNoFileOfNewRepo` now calls `PathRepo.moveAndMakeNewRepo(at:movingOldRepoInto:keyedBy:)`. That helper already takes the staging folder, so I did not extend it. The test host now uses a `ScanKeyReader`, so the helper can give the new repo a different key, as in a real replace. I did not move the helper: the two test files are in one test target, so the helper is visible. The project also keeps shared helpers in their suite files (for example `PathRefCacheTests.replaceRepo`).

    Tests: `swift build --build-tests` is clean. KanbanHostTests, ReplacedRepoTests, and KanbanGraphTests: 41 tests in 3 suites passed. Full `swift test` runs (the load average was 93 to 129): run 1 and run 2 failed only on the 60-second time limits, plus watcher-wait expectations in the tests that hit the limit. Run 3 also failed only on time limits. After each failed run, the failing suites passed alone (94 tests in 9 suites, then 165 tests in 18 suites). Run 4 passed: 1567 tests in 126 suites, 0 issues. The only warning was the allowed SwiftPM "missing creator" warning. No run hung. Logs are in the scratchpad folder (full2.log, failing.log, full3.log, failing2.log, full4.log).
  timestamp: 2026-10-16T07:51:27.130610+00:00
- actor: claude-code
  id: 01m51v3m9zrsb9ra7n53pf2trk
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Sources/FoundationModelsKanban/Tool/KanbanHost.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanHostTests.swift. Targeted suites: 41 tests passed. Full `swift test`: 1567 tests in 126 suites passed on run 4 (runs 1 to 3 failed only on time limits under load, and the failing suites passed alone). Only the allowed "missing creator" warning. 3 of 3 review findings checked.
    - next: /review (the task stays in doing).
  timestamp: 2026-10-16T07:51:29.343506+00:00
- actor: claude-code
  id: 01m51x2q2yp0ktz2wqcg8kefns
  text: |-
    ### test - green
    - evidence: swift build completed. It gave only the allowed SwiftPM "missing creator" warning. Full swift test run 1: 9 failures. All 9 were "Time limit was exceeded: 60.000 seconds" with machine load near 100. Four suites run alone (66 tests): pass. Full swift test run 2: 1567 tests in 126 suites passed. 0 failures, 0 skipped, no new warnings.
    - note: No source change was made. No time limit was changed.
    - next: review
  timestamp: 2026-10-16T08:25:56.574963+00:00
- actor: claude-code
  id: 01m51x47a62r8bejb01rapgje2
  text: |-
    ### commit - changed
    - evidence: Iteration 2 commit of the review fixes. Files: KanbanGraph.swift, KanbanHost.swift, KanbanHostTests.swift, and the task files in .kanban/tasks/. The commit subject is "fix(host): address review findings for the replaced-repo engine (^1yg0p73)". The sha is in the final report of this step.
    - not staged: Package.resolved, .kanban/mcp.17281.log
    - next: review
  timestamp: 2026-10-16T08:26:45.958132+00:00
- actor: claude-code
  id: 01m51xhvhntn213r0jjzqx4qdd
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (ac4a1d4). All 3 items of the 2026-10-16 02:23 section are checked. 1 new finding (1 confirmed, 1 refuted): Sources/FoundationModelsKanban/Tool/KanbanHost.swift:694 `reuse/reuse` — the prune of dead weak entries in the view table is a second copy of the prune of `retiredEngines`.
    - next: Move the dead-entry prune into one shared helper (for example a method on `Weak` collections). Call it for the view table and for `retiredEngines`. Then run the review again. The task stays in review.
  timestamp: 2026-10-16T08:34:12.661067+00:00
- actor: claude-code
  id: 01m51xj8rdkycdfh5dmvc172jd
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — KanbanGraph.swift (runningOnBoard helper), KanbanHost.swift (generic Weak), KanbanHostTests.swift (PathRepo helper)
    - test: green — swift test, 1567 passed (second full run; first had only 60 s time limits under load)
    - commit: ac4a1d4
    - review: findings — Sources/FoundationModelsKanban/Tool/KanbanHost.swift:694
  timestamp: 2026-10-16T08:34:26.189452+00:00
- actor: claude-code
  id: 01m51xzsaf9qvw2wrtdmeqrfap
  text: |-
    Review finding (2026-10-16 03:27) corrected. The item is now `- [x]`.

    - KanbanHost.swift `reuse/reuse`: `Weak` now has `isAlive` (`object != nil`). This is the one shared test for a dead entry. Two `fileprivate` extensions use it: `Array.removeGoneObjects()` where `Element == Weak<Object>` (calls `removeAll`), and `Dictionary.removeGoneObjects()` where `Value == Weak<Object>` (keeps the live entries with `filter`). `retire(_:)` calls `retiredEngines.removeGoneObjects()` and then appends the new entry. `publish(_:)` calls `views.removeGoneObjects()`. No other prune of dead weak entries is in the file. `close()` reads `retiredEngines.compactMap(\.object)` and then sets the list to empty: that is a take of the live engines, not a prune, so it stays.
    - `fileprivate` is necessary: `Weak` is private at file scope, and `KanbanHost` calls the methods from a different type, so `private` members of the extensions cannot compile.
    - TDD: this is a refactor with no change of behavior. The current tests cover both prune paths (retired engines in ReplacedRepoTests and KanbanHostTests, views in each publish). No new test.

    Tests: `swift build --build-tests` clean (only the allowed SwiftPM "missing creator" warning). KanbanHostTests and ReplacedRepoTests: 28 tests in 2 suites passed. Full `swift test` run 1: 1567 tests in 126 suites passed, 0 failures, no time-limit failures.
  timestamp: 2026-10-16T08:41:49.135661+00:00
- actor: claude-code
  id: 01m51xztvf62qtgscezcmkx8m2
  text: |-
    ### implement — changed
    - evidence: 1 file — Sources/FoundationModelsKanban/Tool/KanbanHost.swift. KanbanHostTests and ReplacedRepoTests: 28 tests in 2 suites passed. Full `swift test`: 1567 tests in 126 suites passed on the first run. Only the allowed "missing creator" warning. 1 of 1 open review finding checked.
    - next: /review (the task stays in doing).
  timestamp: 2026-10-16T08:41:50.703749+00:00
- actor: claude-code
  id: 01m51y5e1cm50kyfe5h0h7js5f
  text: |-
    ### test — green
    - evidence: swift build exit 0. swift test exit 0. Swift Testing: 1567 tests in 126 suites passed (51.4 s). XCTest: 0 tests, 0 failures. 0 failed, 0 skipped, 0 issues. Only warning: the allowed SwiftPM "missing creator" warning. Log files: scratchpad build.log and test1.log.
    - next: review
  timestamp: 2026-10-16T08:44:54.188853+00:00
- actor: claude-code
  id: 01m51y60064vzc8d5nejkk8mq4
  text: |-
    ### commit — changed
    - evidence: iteration 3 commit. Files: Sources/FoundationModelsKanban/Tool/KanbanHost.swift and the task files in .kanban/tasks/. The sha is in the git log subject "refactor(host): share the prune of dead weak entries (^1yg0p73)".
    - next: /review
  timestamp: 2026-10-16T08:45:12.582660+00:00
- actor: claude-code
  id: 01m51yh76rmnysnncyqshqvtyk
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (f40a1d8). 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. 1 file reviewed (Sources/FoundationModelsKanban/Tool/KanbanHost.swift). 2 .kanban/ files are excluded by .reviewignore. All prior Review Findings items are checked (4 of 4).
    - next: none. The task moved to done.
  timestamp: 2026-10-16T08:51:20.408662+00:00
- actor: claude-code
  id: 01m51yhma26tp7rqwv3sw2dk7t
  text: |-
    ### finish iteration 3 — clean
    - implement: changed — KanbanHost.swift (shared removeGoneObjects prune)
    - test: green — swift test, 1567 passed
    - commit: f40a1d8
    - review: clean — 0 findings
  timestamp: 2026-10-16T08:51:33.826155+00:00
position_column: done
position_ordinal: ff9580
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

## Review Findings (2026-10-16 02:23)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 8 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `divergence.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:253` `duplication/duplication` — The new nesting in `subscribe` repeats the nesting of `execute`: `followingMovedBoards { holdingGates(startingWith:) { publishingChanges(of:postingPlansTo:) { ... } } }`. Only the context argument (nil here, the caller's context in `execute`), the inner call, and the `host.register` line differ. The move-following and gate-holding logic can drift out of sync between the two copies, and a fix to one will miss the other. Extract a private helper, for example `runOnBoard(postingPlansTo:, _ operation: @Sendable (HeldGates, BoardEngine) async throws -> Value)`, that wraps `followingMovedBoards`, `holdingGates`, and `publishingChanges`. Call it from `execute` with the context and from `subscribe` with nil, passing only the inner call as the closure. Keep `host.register(self)` before the helper call in `subscribe`.
- [x] `Sources/FoundationModelsKanban/Tool/KanbanHost.swift:858` `reuse/reuse` — WeakEngine reimplements the existing WeakView holder: the same single weak optional reference with the same doc shape. A second copy means two weak-holder types that must be kept in step, when one generic weak wrapper would serve both. Replace WeakEngine and WeakView with one generic holder, for example `private struct Weak<Object: AnyObject> { weak var object: Object? }`, and use `[Weak<BoardEngine>]` for retiredEngines (KanbanHost.swift:48). Keep WeakView's name at its call sites through a typealias if that reads better.
- [x] `Tests/FoundationModelsKanbanTests/Tool/KanbanHostTests.swift:293` `reuse/reuse` — The new test moves the repo folder, makes a new repo folder, and writes a fixture into it by hand. A shared helper already does this sequence. Two copies of the same move-and-replace steps will drift apart when one is fixed. Call `PathRepo.moveAndMakeNewRepo` (or the `PathRepo` helper it uses) from ReplacedRepoTests.swift instead of the hand-written move and folder setup. If that helper does not fit the test's need for a separate staging directory, extend it with a parameter for the staging location, and call the extended helper.

## Review Findings (2026-10-16 03:27)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Sources/FoundationModelsKanban/Tool/KanbanHost.swift:694` `reuse/reuse` — The view table is pruned of dead weak entries inline, the same way `retiredEngines` is pruned at line 278. This is a second copy of the same prune logic, not a call to a shared helper. Move the dead-entry prune into a helper shared with line 278, for example a method on `Weak` collections, and call it here.
