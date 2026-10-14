---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4xk7fdxjc7yhkc3b2f2wgvj
  text: |-
    Research done. Findings:
    - KanbanGraph (S/Tool/KanbanGraph.swift) now holds all state: current board (loadState, watchState), relatedBoards, scanState, gate, feed, search. CommitSession (S/Tool/Commit.swift) holds the session actor; the actor must move to the view, because one engine serves many sessions.
    - RelatedBoards and ChangeRound key boards by canonicalPath of the repo folder. canonicalPath resolves symlinks but not letter case. The host table must key by device and inode.
    - Many tests build a KanbanGraph through the internal init (KanbanGraphTests.makeGraph, GitGraphFixture) and some tests make two graphs on one repo to act as two processes. Plan: keep the internal init; it makes a private test host that close() of that view closes. The public init goes away; README, ReadmeExamplesTests and IntegrationTests move to KanbanHost.shared.session.
    - Design: KanbanHost (public actor, shared, internal init) keeps the engine table by FolderIdentity (load task stored before the first await), the scan indexes, and the live views. BoardEngine (actor) owns the session, watcher, serial gate, search and change feed of one board. KanbanGraph becomes the session view: working directory, actor, default engine, reached related engines. A call holds the gates of its boards in identity order; when the commit needs a board whose gate it does not hold, the call releases all gates, takes the larger set in order, and runs again.
    - The feed: each engine owns one ChangeFeed; each subscriber records the view that owns it, because a view resolves keys from its own current board. After an operation, the changes go to each live view, so a write in session A reaches session B at once.
    - The shared host needs the locator and the embedder: add configure(locator:embedder:) before the first board loads.
  timestamp: 2026-10-14T16:16:49.085929+00:00
- actor: claude-code
  id: 01m4xm979d5e4s8q0jfjtm3mrh
  text: |-
    Implementation landed (first pass), tests running:
    - New: S/Tool/KanbanHost.swift (public actor, `shared`, internal init, `session(workingDirectory:actor:)`, `configure(locator:embedder:)`, engine table by FolderIdentity with the load task stored before the first await, scan indexes, weak view registry, publish to views), S/Tool/BoardEngine.swift (engine actor: session, watcher, gate, feed; parallel load of key + files after the watcher starts; watcher moves to .kanban when it appears), S/Tool/BoardGates.swift (HeldGates in identity order, GateShortfall, CommitAdmission), S/Tool/FolderIdentity.swift (stat device+inode), S/Observe/SessionFeeds.swift (the feeds of one view; subscribers owned by the view).
    - Changed: KanbanGraph is now the session view (public init removed; internal test init makes a private host that close() closes). CommitSession has no actor: run(actingAs:...) and an admission hook before each commit. ChangeFeed subscribers carry an owner. README example 1 and 5 use KanbanHost.shared.
    - Discovery: a test host with the fixed ULID source gives each engine its own copy of the source, so two boards of one host mint the same ids. The worktree merge test uses SystemULIDSource for that reason.
    - Discovery: the files tool echoes the whole file on each edit; keep edits of large files few.
  timestamp: 2026-10-14T16:35:14.861863+00:00
- actor: claude-code
  id: 01m4xn0z6b5ctwrqhp10vjbtg2
  text: |-
    ### implement — changed
    - evidence: swift build --build-tests clean (only the accepted SwiftPM warning). swift test --filter KanbanHostTests: 13/13 pass. Full swift test: 1182 tests in 86 suites pass, 0 failures.
    - files: new S/Tool/KanbanHost.swift, S/Tool/BoardEngine.swift, S/Tool/BoardGates.swift, S/Tool/FolderIdentity.swift, S/Observe/SessionFeeds.swift, Tests/.../Tool/KanbanHostTests.swift, Tests/.../Tool/CommitSessionTestRun.swift; changed S/Tool/KanbanGraph.swift, S/Tool/Commit.swift, S/Observe/ChangeFeed.swift, S/Observe/ChangeSubscription.swift, S/GraphQL/Schema.swift, README.md, Tests (CommitTests, KanbanGraphTests, ReadmeExamplesTests), IntegrationTests (BoardSmokeTests, ModelVariablesTests).
    - open: the IntegrationTests package build could not run here: SwiftPM cannot remove IntegrationTests/.build/checkouts/FoundationModelsMetadataRegistry (permission denied). The two integration files now call KanbanHost.shared.session and are not compiled yet.
    - note: divergence.md §16 proposal text says "real path"; the code keys by device and inode, as the hard rules say. ARCHITECTURE.md does not exist.
    - next: /review
  timestamp: 2026-10-14T16:48:13.003757+00:00
- actor: claude-code
  id: 01m4xnr69gmwht93sva8kn0t14
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — KanbanHost, BoardEngine, BoardGates, FolderIdentity, SessionFeeds + tests
    - test: green — swift test, 1182 passed, 0 failed, 0 skipped; IntegrationTests 2 passed (separate scratch path)
    - commit: 126dd30
    - review: findings — Sources/FoundationModelsKanban/Observe/SessionFeeds.swift:64 (duplication/duplication), Sources/FoundationModelsKanban/Observe/SessionFeeds.swift:64 (reuse/reuse), Sources/FoundationModelsKanban/Tool/BoardEngine.swift:255, Sources/FoundationModelsKanban/Tool/BoardEngine.swift:283, Sources/FoundationModelsKanban/Tool/BoardEngine.swift:338, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:261
  timestamp: 2026-10-14T17:00:53.936317+00:00
- actor: claude-code
  id: 01m4xnynph2kzh7ebabvegk2wt
  text: |-
    Picked up for the 6 review findings. Plan:
    - endedEvents (2 findings): one shared `ChangeEvent.endedStream()` in Observe/ChangeFeed.swift. SessionFeeds and KanbanResolver (ChangeSubscription.swift) both call it. ChangeSubscription.swift is in this change (commit 126dd30 changed it), so the second copy goes now, not as a separate task.
    - BoardEngine.apply: after each await, check that the engine is not closed before it stores state (the moved watch, and the session). A closed engine ends the moved watch and applies nothing. Seam: internal `adopt(_:)` so a unit test can prove the closed case without a timing race.
    - StartedWatcher: one `init(watching:)` that both movedWatch and BoardWatcher.started(onBoardAt:) call.
    - EngineLoad.liveGraph: `defer` the boardLoadDidFinish call. Test: a log file with no read permission makes the load fail after the start.
    - KanbanGraph.close(): SessionFeeds.finish() ends the subscribers of the view now and keeps the feeds, so a later subscribe works. The view registers with the host again when a subscription starts. Doc states this.
  timestamp: 2026-10-14T17:04:26.321704+00:00
- actor: claude-code
  id: 01m4xp7nvczj805yqdfprwj28d
  text: |-
    ### implement — changed
    - evidence: TDD. RED: 3 new KanbanHostTests failed for the expected reasons (load observer had no finish on a failed load; a subscribe after close() got 0 events; adopt() kept a moved watch on a closed engine). GREEN: the 3 pass. Full `swift test`: 1185 tests in 86 suites pass, 0 failures; build shows only the accepted SwiftPM "missing creator" warning.
    - files: Sources/FoundationModelsKanban/Observe/ChangeFeed.swift (new `ChangeEvent.endedStream()`), Observe/ChangeSubscription.swift (private copy removed, calls the shared helper), Observe/SessionFeeds.swift (copy removed; `finish()` now ends the subscribers of the view that run now and keeps the feeds; the closed state is gone), Tool/BoardEngine.swift (`adopt(_:)` and `isClosed`: a closed engine ends a moved watch and stores no applied session; `StartedWatcher.init(watching:)` used by `movedWatch` and `BoardWatcher.started(onBoardAt:)`; `defer` for `boardLoadDidFinish`), Tool/KanbanGraph.swift (`subscribe` registers the view with the host again; `close()` and `subscribe` docs state the exact behaviour), Tool/KanbanHost.swift (`register` doc), Tests/FoundationModelsKanbanTests/Tool/KanbanHostTests.swift (3 new tests).
    - note: finding 1 asked for the ChangeSubscription.swift copy as a separate task. Commit 126dd30 changed that file, so it is in this change, and finding 2 asked to call the helper from both places. Both copies now call `ChangeEvent.endedStream()`; no separate task is necessary.
    - note: the closed check in BoardEngine.apply also guards the session store after the second wait (the same cause as finding 3, in the same function).
    - next: /review
  timestamp: 2026-10-14T17:09:21.388230+00:00
depends_on:
- 01M4X6X6PS5P524DW45RBSSWN2
- 01M4X6XKP0Y832GDRHQ1MG22VF
- 01M4X6YD33YTSBBTG8VZFWTRZR
- 01M4X6YRT3543TS3S5K6RGZMCJ
position_column: doing
position_ordinal: '80'
title: 'Add KanbanHost: one engine per board for each process, and a session view for each working directory'
---
## What
divergence.md §16 (M1, M2, Gap 2, L1, L6, X13, and the hard rules of the user). One ACP agent process runs many sessions at the same time. Each session has its own working directory. Now each session makes its own `KanbanGraph`, so N sessions load the same board N times, with N watchers, N search indexes, and N serial gates (M1). A write in one session reaches another session only after FSEvents reports it (M2). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/). The wiring in the ACP agent repo is a separate change (not in this task).

The user: "We really don't want one process loading up the same board multiple times, and we really want each session to know and work on its default board from its cwd." "it's really important to me that each board, its file watchers — are only loaded once per process." "it's also important to me that the boards are fully cached in memory." "I want the board to be in memory all the time with write through — and file watch detection to allow manual poking of files."

Hard rules (the design must make a second load impossible, not only unlikely):
- One host for each process: `KanbanHost.shared` (a public actor) is the only way to get a host. There is no public `init`.
- One identity for each board: the host keys each board by the file identity (device and inode) of the folder that holds `.kanban/`, not by its path text. A symlink, `/tmp` against `/private/tmp`, a `..` in the path, or a different letter case on APFS gives the same board.
- One engine for current and related boards: one table of engines in the host. Remove the split between the current session (`loadState`) and `relatedBoards` in S/Tool/KanbanGraph.swift:74,84. A board that is the current board of one session and a related board of another session is the same engine.
- One watcher for each board: the engine owns the watcher. The watcher starts and stops only with the engine. This includes the watcher on the repo folder before `.kanban/` exists (X13).
- Load once under concurrency: two sessions that open the same board at the same time wait for one load. The host stores the load task in its table before the first `await`.
- Fully cached: a loaded board stays in memory until the host closes. It does not unload when its last session closes. A read (a query, `nextTask`, a filter, search) reads no file and runs no `git`. The file watcher is the only way that changes from outside the process reach memory.
- Write through: a write goes to the log files and to memory in the same commit (as now, S/Tool/Commit.swift:525-552). Keep the signature compare under the lock (S/Tool/Commit.swift:537-540).
- Each engine has one live graph, one watcher, one serial gate, one search index, and one change feed. The host also keeps the board locator and the scan index, one time for the process.
- Locks across boards: a call that writes more than one board takes the gates of those boards in a fixed order (by file identity or by path), so two sessions cannot deadlock.

Session API:
- `host.session(workingDirectory:actor:)` returns a `KanbanGraph` view for one session. The view has its own actor and its own default board (the board of its working directory). A call that names no board goes to that board.
- The public API of the view does not change: `execute`, `subscribe`, `close`, and `KanbanTool.init(graph:)`. `close()` of a view releases its references only. It does not stop an engine.
- A write in one session goes to the shared engine, so each other session sees it at once.
- `host.session(...)` does these steps before it returns (Gap 2: detect and load at session start, and wait):
  1. `git rev-parse --show-toplevel` in the working directory gives the worktree top. Not in a git repo: no board, and each kanban call gives `NOT_A_REPO` (see the task "Put the board only in a git repo").
  2. A repo with no commit gets the empty first commit (M8).
  3. The key: the `origin` remote, else `local/<root commit>` (M7).
  4. The host finds the engine of `<worktree top>/.kanban/` by file identity, or makes it (one watcher).
  5. The host loads the board (the logs, the graph, the event list, and the keyword index) if it is not loaded yet, and waits. A second session on the same board waits for the same load.
- A board that cannot load (for example `INCOMPATIBLE_BOARD`, Q6) makes `host.session` fail with that error.
- Related boards still load when a call first reaches them, and then stay in memory.
- L1: after `git rev-parse --show-toplevel` gives the folder, run the key read (with M8), the watcher start, and the file load at the same time. The log does not store the key, so the load does not need it.
- L6: the host must not hold its actor during a load. It keeps a load task for each board in its table, and the load runs outside the actor. Sessions on different boards load at the same time.
- Keep `KanbanGraph.init(root:actor:locator:embedder:)` only if the tests need it; it must not make a second engine for a board that the host has.

## Acceptance Criteria
- [ ] `KanbanHost.shared` exists and there is no public `init`.
- [ ] Many sessions on the same repo, on a symlink to it, and on a sibling repo that the first repo reaches as a related board give exactly one engine and one watcher for each board.
- [ ] Two sessions that start at the same time load the board one time.
- [ ] The board is loaded when `host.session` returns.
- [ ] A Rust board makes `host.session` fail with `INCOMPATIBLE_BOARD`.
- [ ] A write in session A shows in a read of session B at once, with no wait for FSEvents.
- [ ] `close()` of one view does not stop the board for another view, and the board stays loaded after the last view closes.
- [ ] A read runs no `git` and reads no file.
- [ ] Two sessions with different actors: `undo` with no argument in session B does not reverse the work of session A.
- [ ] Two boards load at the same time; the key read and the file load overlap.

## Tests
- [ ] Many sessions on one repo, a symlink, and a sibling related repo: one engine and one watcher for each board.
- [ ] Two sessions at the same time: one load.
- [ ] The board is loaded when `host.session` returns.
- [ ] A Rust board makes `host.session` fail.
- [ ] Two boards load at the same time; the key read and the file load overlap (use the worker observer or a test hook).
- [ ] Two worktrees are two engines with the same key.
- [ ] A git merge of two worktree branches gives the union of both boards.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-14 11:52)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 17 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/Observe/SessionFeeds.swift:64` `duplication/duplication` — The new `SessionFeeds.endedEvents()` is a verbatim copy of `KanbanResolver.endedEvents()`, including the doc comment. Both bodies are `AsyncStream { continuation in continuation.finish() }`. The two copies can drift apart, and the fix to one will be missed in the other. Extract one non-private helper that returns an ended `AsyncStream<ChangeEvent>`, for example a static on `ChangeFeed` or a free function next to `ChangeEvent`. Call it from `SessionFeeds.subscribe` and from `KanbanResolver.events`, and delete the private copy added at SessionFeeds.swift:64-66. Make the ChangeSubscription.swift copy call the shared helper as a separate task, since that file is outside this change.
- [x] `Sources/FoundationModelsKanban/Observe/SessionFeeds.swift:64` `reuse/reuse` — The new private static function endedEvents() in SessionFeeds reimplements the existing private static endedEvents() in KanbanResolver. Both return an AsyncStream<ChangeEvent> that finishes at once. Two copies must now be kept in step. Move the ended-stream helper to one shared place, for example a static on ChangeEvent or a file-level internal function in Observe/ChangeFeed.swift. Then call it from both KanbanResolver (ChangeSubscription.swift) and SessionFeeds.subscribe. Delete the copy in SessionFeeds.swift.
- [x] `Sources/FoundationModelsKanban/Tool/BoardEngine.swift:255` `completeness/invariant-propagation` — apply() stores the moved watch with watchState = .watching(moved) without checking for .closed. close() can run during the await in movedWatch, because actor calls can interleave. apply() then overwrites .closed, and the new watcher keeps running after close() returns. This breaks the close contract that a change applies nothing after close returns. After the await, check that watchState is still `.watching` before storing the moved watch. If the engine is closed, call `await moved.end()` and return without storing it.
- [x] `Sources/FoundationModelsKanban/Tool/BoardEngine.swift:283` `duplication/duplication` — `movedWatch` builds a `StartedWatcher` from `BoardWatcher(watching:)` and the same directory for both fields. `BoardWatcher.started(onBoardAt:)` builds the same value again. The two lines differ only by the variable name, so the construction is repeated in the same file. Add a small `StartedWatcher` initializer or a `BoardWatcher` static such as `watching(directory:)` that returns the started watcher for one directory. Call it from both `movedWatch` and `started(onBoardAt:)`. If the team prefers to keep one-line constructors inline, drop this finding.
- [x] `Sources/FoundationModelsKanban/Tool/BoardEngine.swift:338` `completeness/inverse-operation-coverage` — liveGraph() calls boardLoadDidStart before the load and boardLoadDidFinish after it. If LiveGraph.load throws, boardLoadDidFinish is never called. The observer then records a start with no matching finish for a failed load, so a test or other observer that pairs the two calls gets an unbalanced count. Call boardLoadDidFinish on every exit path, for example with `defer { configuration.loadObserver?.boardLoadDidFinish(at: root) }` placed right after the start call.
- [x] `Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:261` `completeness/public-output-contract` — close() unregisters the view from the host, and nothing registers it again. The doc says a later call of the view still runs. But a subscribe() that starts after close() on the same view gets no changes from other sessions or from the file watcher. Register the view again when a new subscription starts, or make close() end only the current subscriptions and keep the registration. Also correct the doc comment so it states the exact behaviour.
