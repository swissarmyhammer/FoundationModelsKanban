---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4yehgd18k97n7h1mqx5vgg1
  text: 'Research done. Each key lookup (dependency readiness, node(id:), undo boards(of:)) goes through KanbanGraph.resolution(of:current:): first the cached scan index, then BoardLocator.resolution(ofFolderAt:) for a path, then host.currentScanIndex. A path outside the scan places resolves only in the folder step, and nothing records it, so a later key ref of that board gives NOT_FOUND. Plan: the host keeps the copies that a call reached by a path (key + worktree top). The key lookup asks the scan index first (first copy in scan order, the plan §6.6 rule), then the copies reached by a path, in the sort order of the path. Test fixture: CrossRepoWriteTests.makeOutsideFolder (sandbox/outside/other, origin new-lib), never the .kanban/ of this repo.'
  timestamp: 2026-10-15T00:14:09.313572+00:00
- actor: claude-code
  id: 01m4yf35c898mjbhkmb8y162b5
  text: |-
    Implementation landed (TDD). RED: 5 of the 6 new tests in PathBoardKeyTests failed before the change (key ref NOT_FOUND, node null, ready false, undo NOT_FOUND). The test "scanCopyComesBeforePathCopy" passed before the change. It is a guard of the order rule: a copy in the scan index comes before a copy that a call reached by a path. GREEN: all 6 pass after the change.

    Change: KanbanHost keeps `pathCopies` (canonical worktree top -> BoardCopy). `recordPathCopy(_:)` records each `.copy` that BoardLocator.resolution(ofFolderAt:) gives in KanbanGraph.resolution(of:current:). `pathCopy(namedBy:)` resolves a key or board URI only after the current scan index has no copy with the key. Copies with the same key resolve in the sort order of the canonical path. A copy whose folder is gone does not match. BoardIndex.boardKey(in:) is now internal (it was private), so the host can parse the key the same way.

    Full `swift test` (one run): 1281 tests, 11 issues, all `BoardWatcherError.streamNotStarted` in IncompatibleBoardTests and TagMutationTests. Those two suites pass alone (40 tests, `swift test --skip-build --filter "IncompatibleBoardTests|TagMutationTests"`). At the time of the run the machine load average was about 65, and a FoundationModelsAgents swift test process was running. The FSEvents stream limit applies to the whole system. The /test step must confirm that the suite is green.
  timestamp: 2026-10-15T00:23:47.848715+00:00
- actor: claude-code
  id: 01m4yf37vd1rr0bsbdpy3yqeqz
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/Tool/KanbanHost.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift, Tests/FoundationModelsKanbanTests/CrossRepo/PathBoardKeyTests.swift (new, 6 tests pass). Full suite: 11 streamNotStarted issues in 2 suites that this change does not touch. Those 2 suites pass alone.
    - next: /test, to confirm the full suite is green, then /review
  timestamp: 2026-10-15T00:23:50.381931+00:00
- actor: claude-code
  id: 01m4ygmt845dxpk3np4cct6naa
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 4 files
    - test: green — swift test, 1281 passed, 0 failed, 0 skipped; IntegrationTests 2 passed (the implementer's 11 streamNotStarted failures did not reproduce; FSEvents stream limit is system-wide, see ^swk9c8n)
    - commit: d72f34f
    - review: findings — Sources/FoundationModelsKanban/Tool/KanbanHost.swift:55
  timestamp: 2026-10-15T00:50:54.852753+00:00
- actor: claude-code
  id: 01m4ygvbw306gk90kycr2xzsdf
  text: 'Picked up the review finding (KanbanHost.swift:55, pathCopies is never refreshed). Decision from the orchestrator: a path copy follows the same invalidation as the scan index, through a file watch, with no git on reads. Research: the scan index forgets a repo on ScanChange.repo (repo folder, its .git entry, or .git/config) and on ScanChange.place (the place, or lost events). WatchedPlace(watching: parent) already maps those paths of a child folder to .repo(<canonical path of the child>). Plan: when the host records a path copy, it starts a BoardWatch (the same shared shape as placeWatches and unloadableBoards, so ^swk9c8n can fold it in) on the parent folder of the worktree top, and it drops the copy on .repo(<top>) or .place(<parent>). The host reports the change to BoardScanObserver, so a test can wait for the effect. A closed host records no path copy (no watcher can follow it), and close() ends each watch and clears pathCopies. A watch that cannot start gives no record and a swift-log warning, the same as markUnloadable.'
  timestamp: 2026-10-15T00:54:29.507174+00:00
- actor: claude-code
  id: 01m4yh6y7k2hydtp5swcq8pkwg
  text: 'Finding fix landed (TDD). RED: changedOriginForgetsOldKey hit the 1-minute time limit (the old key still resolved, so no change ever ended the wait), and closedHostForgetsPathCopies failed (the key still resolved after close). GREEN: both pass. Change: KanbanHost.pathCopies now holds PathCopy (copy + BoardWatch). recordPathCopy starts a BoardWatch on the parent folder of the worktree top (the same BoardWatch(of: StartedWatcher) shape as placeWatches, so ^swk9c8n can fold it in). The new WatchedPlace.keyChange(ofRepoAt:in:) gives the first .repo(<top>) or .place(<parent>) change, the same changes on which BoardIndex.forgetting forgets a key. On that change the host removes the entry, calls the new BoardScanObserver.pathCopyDidChange, and stops the watcher. Reads run no git. A closed host records no path copy, and close() ends each path-copy watch and clears pathCopies. A watch that cannot start gives no record and a swift-log warning. Known limit: a change between the key read in BoardLocator.resolution(ofFolderAt:) and the start of the watch is not seen; the next path call reads the key again. ^xxv6d0a will change the path-ref read path. Full swift test: 1283 tests in 99 suites passed; the only build warning is the accepted SwiftPM "missing creator" warning.'
  timestamp: 2026-10-15T01:00:48.755013+00:00
- actor: claude-code
  id: 01m4yh70hsfacgtx7v17br85wn
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/Tool/KanbanHost.swift, Sources/FoundationModelsKanban/CrossRepo/ScanChange.swift, Tests/FoundationModelsKanbanTests/CrossRepo/PathBoardKeyTests.swift (2 new tests), Tests/FoundationModelsKanbanTests/CrossRepo/ScanCacheTests.swift (ScanRecorder.pathCopyDidChange). swift test: 1283 passed, 0 failed.
    - next: /test, then /review
  timestamp: 2026-10-15T01:00:51.129147+00:00
- actor: claude-code
  id: 01m4yh76h4v32j6cqrgxpv2rjy
  text: 'Correction to the comment above: the task that will change the path-ref read path is ^58v2scm ("Keep the result of a path board ref in memory, so a repeated path ref runs no git"), not "^xxv6d0a".'
  timestamp: 2026-10-15T01:00:57.252784+00:00
- actor: claude-code
  id: 01m4yhktraeg5pswbfc2gb0f5a
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 4 files (1 finding fixed: path copies follow the scan-index invalidation through a file watch; cleared on close)
    - test: green — swift test, 1283 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: 5912239
    - review: findings — Sources/FoundationModelsKanban/Tool/KanbanHost.swift:459, Sources/FoundationModelsKanban/Tool/KanbanHost.swift:477, Tests/FoundationModelsKanbanTests/CrossRepo/ScanCacheTests.swift:315
  timestamp: 2026-10-15T01:07:51.178684+00:00
- actor: claude-code
  id: 01m4yhxm32j8rz9msmyj6n4esn
  text: |-
    Fixed the 3 findings of 2026-10-14 20:04. The cause is removed in the whole file, not only on the lines in the findings.
    1. KanbanHost.swift `duplication/duplication` (watch-failure log): the new `private static func logWatchFailure(_ message: Logger.Message, path: String, error: any Error)` holds the shared metadata. All three catch blocks (markUnloadable, watch(_:), recordPathCopy) call it. KanbanHost.swift now imports Logging, so that it can name Logger.Message.
    2. KanbanHost.swift `duplication/duplication` (watch wiring): the new `makeFolderWatch(of:sendingBatchesTo:)` starts the StartedWatcher. It calls the new `makeWatch(of:sendingBatchesTo:)`, which is the only place that has the weak-self capture and the BoardWatch(of:) wiring. The receiver gets `(KanbanHost, [URL])`. makePlaceWatch and makePathCopyWatch call makeFolderWatch. makeUnloadableWatch had the same weak-self wiring on a BoardWatcher.started(onBoardAt:) watcher, so it calls makeWatch directly. The label `sendingBatchesTo` agrees with the label of BoardWatch(of:sendingBatchesTo:). BoardEngine.swift did not change.
    3. ScanCacheTests.swift `reuse/reuse`: ScanRecorder.pathCopyDidChange(_:) now calls scanPlaceDidChange(change).
    TDD note: this is a refactor with no change of behavior, so no new test can fail first. The existing PathBoardKeyTests, ScanCacheTests, and unloadable-board tests cover the changed paths.
    Rules note: the dump-validators file is 12098 lines, and most of it is tool mechanics for other languages. I read the code-hygiene head and the full duplication, reuse, and swift rule sections. I did not read the tool-mechanics sections for other languages.
    Verification: `swift build --build-tests` gives only the accepted SwiftPM "missing creator" warning. One `swift test --skip-build` run: 1283 tests in 99 suites passed.
  timestamp: 2026-10-15T01:13:12.034793+00:00
- actor: claude-code
  id: 01m4yhxpd767pn6ev182ty3yqf
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsKanban/Tool/KanbanHost.swift (logWatchFailure, makeFolderWatch, makeWatch; 3 catch blocks and 3 watch makers use them), Tests/FoundationModelsKanbanTests/CrossRepo/ScanCacheTests.swift (pathCopyDidChange calls scanPlaceDidChange). swift test: 1283 passed, 0 failed; only the accepted SwiftPM "missing creator" warning.
    - next: /test, then /review
  timestamp: 2026-10-15T01:13:14.407959+00:00
depends_on:
- 01M4X6XKP0Y832GDRHQ1MG22VF
position_column: doing
position_ordinal: '80'
title: Put a board that a call reached by a path into the key index
---
## What
divergence.md X4 (§1.1, §11 bugs; K8 stays as work). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem: a board that the call reached only by a path to a folder outside the scan places (for example `board: "/x/notes"`, where `/x/notes` is a git repo) does not go into the scan index (S/Tool/KanbanGraph.swift:703-721). A path into a folder that the scan finds is in the index. Results: a task on that board is done, but a task that depends on it stays BLOCKED; `node(id:)` with a URI of that board gives null; undo with no `board` field, of a transaction that also changed that board, gives `NOT_FOUND`. Undo with `board: "/x/notes"` works.

Note: after the task "Put the board only in a git repo", a `board:` path must be inside a git repo. This task applies to such a path outside the scan places.

Change: when a call reaches a board by a path, add that board (its key and its worktree top) to the key index of the host (or the locator), so that a later URI with that key resolves to it. Use the same order rule as for other copies with the same key.

## Acceptance Criteria
- [x] After a call with `board: "<path outside scan places>"`, a URI with the key of that board resolves to it.
- [x] A task that depends on a done task on that board is READY.
- [x] `node(id:)` with a URI of that board gives the node.
- [x] Undo with no `board` field, of a transaction that also changed that board, reverses both boards.

## Tests
- [x] The three results above, each as a test (these are also listed in the K14 missing tests).
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-14 19:46)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/Tool/KanbanHost.swift:55` `completeness/invariant-propagation` — The new pathCopies store keeps a board key that was read once, at record time. The scan index is refreshed when a file watcher sees a change, but pathCopies is never refreshed. If the origin of a path-reached repo changes, the old key still resolves to that folder. Watcher events also do not remove the entry, and only a missing folder does. This is a second store of board keys that the invalidation path does not reach. Decide whether a path copy must follow the same invalidation as the scan index. If it must, re-read the key of the recorded folder when a watcher for it sees a change, or drop the entry on that change. If stale keys are accepted by design, document that in divergence.md X4 and add a test that pins the chosen behaviour. Clear pathCopies in close() if the host must not keep copies after close.

## Review Findings (2026-10-14 20:04)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/Tool/KanbanHost.swift:459` `duplication/duplication` — The new catch block in recordPathCopy repeats the watch-failure logging of two earlier blocks in the same file. Each block logs a fixed message with the same path and error metadata when a file watcher cannot start. The three copies differ only by the message text and the path value, so a change to the logging format must be made in three places. Extract a private helper, for example `logWatchFailure(_ message: String, path: String, error: any Error)`, that calls Log.kanban.warning with the shared metadata. Call it from the three catch blocks, passing each one's message and path. This is low severity: the blocks are short, so only apply it if the helper also serves the makePathCopyWatch extraction suggested earlier.
- [x] `Sources/FoundationModelsKanban/Tool/KanbanHost.swift:477` `duplication/duplication` — makePathCopyWatch repeats the wiring of makePlaceWatch (KanbanHost.swift:403): it starts a StartedWatcher on a folder, wraps it in a BoardWatch, and passes a weak-self closure that forwards each batch to a handler. Only the watched value and the handler differ. The same logic now lives in two places, so a fix to the watch wiring must be made twice. Extract one private helper, for example `makeFolderWatch(of folder: URL, onBatch: @escaping @Sendable ([URL]) async -> Void) throws(BoardWatcherError) -> BoardWatch`, that builds the StartedWatcher and BoardWatch. Call it from makePlaceWatch and makePathCopyWatch, passing each one's closure. Leave BoardEngine.swift unchanged.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/ScanCacheTests.swift:315` `reuse/reuse` — ScanRecorder.pathCopyDidChange(_:) has the same body as scanPlaceDidChange(_:): it yields the change to changeSink. The new method reimplements an existing method of the same class instead of calling it. Have pathCopyDidChange call scanPlaceDidChange(change), or make both delegate to one private record(_:) helper. The two protocol requirements can share one implementation.
