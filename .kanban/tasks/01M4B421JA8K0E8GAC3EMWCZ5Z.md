---
comments:
- actor: wballard
  id: 01m4cm02rr9m0x99e7k4et2y08
  text: |-
    Research done. Findings:
    - Today the engine is single-board. `KanbanGraph` holds one `CommitSession` and one watch state. `BoardStore` builds one `BoardView`. `Readiness` treats each `.unresolved(.remote(uri))` target as not done. `KanbanResolver.board(id:)` accepts only the current key or its board URI (through `RefResolver`). `Query.boards` does not exist yet.
    - Board views reach GraphQL from synchronous paths inside the `BoardStore` actor (each mutation result). A board load is async and can throw an I/O error. Thus resolvers must not load boards. Design: the resolvers read a per-call snapshot (`RelatedBoards`). A resolver that needs a board that is not in the snapshot records a request. `CommitSession.run` loads the requests (outside of the resolvers, so an I/O fault still throws from `execute`) and runs the call again before the commit. A snapshot with no loader (the query fixtures) answers each unknown request with `.notFound`.
    - `searchTasks`, `history`, and the new `Board.path` must read the board of their own view, not the current board. Thus `BoardView` gets a `BoardSource` (directory, search, events). `KanbanContext.search` goes away.
    - Tests: `GitSandbox` (BoardKeyTests) makes temporary repos and worktrees. `KanbanGraphTests.makeGraph` makes engines. `BoardWatcherTests.query(_:reaches:on:recordedBy:)` and `BatchRecorder` wait for a definite FSEvents signal.
  timestamp: 2026-10-08T02:03:09.976592+00:00
- actor: wballard
  id: 01m4cnx6hr8e9a4tt9k9tddvq3
  text: |-
    ### implement — changed

    Discoveries:
    - A resolver cannot load a board, because a load is async and can fail with an I/O error. Thus a run records each board read that it needs (`BoardRequest`). `CommitSession.run(readingRelatedBoardsWith:_:)` gives the requests to the engine, the engine loads the boards, and the call runs again before it commits. A test fixture with no engine uses `RelatedBoards.unavailable`: each unknown board ref is not found.
    - `Board.path: String` is a new schema field, so that `boards` shows the path of each copy. plan.md §4.1 now has it.
    - `node(id:)` with a URI of a board that the scan cannot find gives `null` with no error (the same as an id that names no node). `board(id:)` gives `NOT_FOUND` with the search roots. The existing test `NodeQueryTests.nodeOfDifferentBoardIsNull` keeps this contract.
    - The scan reads each entry of the parent directory of the repo. The user temp directory on this machine is very large, so a test repo directly in it made one test take 300 s. `TemporaryDirectory` (Tests/.../Events/EventLogTests.swift) now makes its directory in the shared folder `FoundationModelsKanbanTests` of the temp directory. In production, a repo whose parent directory has very many entries makes the first cross-board read slow.
    - A `LoadedBoard` type already exists in Events/Loader.swift, so the read snapshot of a board is `BoardSnapshot`.

    Evidence:
    - RED: `swift test --skip-build --filter 'BoardLocatorTests|CrossRepoReadTests|KanbanErrorTests'` gave 50 tests, 31 issues.
    - GREEN: the same filter gives 50 tests, all pass. `--filter BoardLocatorTests` gives 13 pass; `--filter CrossRepoReadTests` gives 14 pass.
    - Full suite: `swift test --skip-build` gives 902 tests in 58 suites, all pass.
    - `swift build --build-tests`: only the known `missing creator` warning. No line is longer than 120 characters. periphery: no unused code.
  timestamp: 2026-10-08T02:36:32.696623+00:00
- actor: wballard
  id: 01m4cpcs41grmc7shmkb4vv6zg
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (27dcfee). 4 findings (4 confirmed, 8 refuted). Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:76, :359, :435, :512.
    - next: Correct the 4 open items in the "Review Findings (2026-10-07 21:39)" section. Then review again.
  timestamp: 2026-10-08T02:45:03.233725+00:00
- actor: wballard
  id: 01m4cpd3ytthg6g06n9ksh8cz1
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — CrossRepo/BoardLocator.swift, CrossRepo/RelatedBoards.swift, KanbanGraph, Commit, Schema, QueryResolvers, Errors, Readiness, ColumnOrder, History, RefResolver, 5 test files, plan.md
    - test: green — swift test 3 runs, 902 passed each; build warnings only the 2 accepted kinds
    - commit: 27dcfee
    - review: findings — Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:76, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:359, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:435, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:512
  timestamp: 2026-10-08T02:45:14.330728+00:00
- actor: wballard
  id: 01m4cprqp5k1r2a20q6722ay01
  text: |-
    Correction of the 4 review findings (2026-10-07 21:39). Notes for the next agent:
    - swift/initialization: the cause is a stored Optional whose `nil` means "not done yet". KanbanGraph.swift had three of these: `index`, `currentKey`, and `session`. All three are gone. `scanState` is a `ScanState` enum (`.notScanned`, `.scanned(BoardIndex)`). `loadState` is a `LoadState` enum (`.notLoaded`, `.loaded(CommitSession)`). The first-scan rule is in one place: `resolution(of:currentKey:)`. `rescan()` gives the earlier index to `BoardLocator.scan(reusing:)`, whose documented contract takes `nil` for the first scan. `relatedBoards(updating:...)` now gives `locator.places(around: root)` as the search roots. This is the same value, because `scan` sets `BoardIndex.places` from that same function.
    - swift/preconditions: the key now goes into `loadBoard` as a parameter, so no nil branch exists. `CommitSession.key` changed from `private` to internal (Commit.swift), and `respond` reads `session.key` and gives it to the loader closure.
    - reuse/reuse: the new `private static func existingBoardDirectory(ofBoardAt:) -> URL?` does the lookup. `startWatch(ofBoardAt:)` and `movedWatch(_:ofBoardAt:)` both call it.
    - duplication/duplication: the new helper `apply(_:to:watchedBy:ofBoardAt:storingMovedWatchWith:)` does the move-then-apply sequence one time. It does not return the moved watch. A caller-supplied closure stores the watch BEFORE the apply. Reason: the old code stored the moved watch before `apply` and kept it when `apply` threw. A helper that returns the watch after `apply` loses the new watcher when `apply` throws, because the old watcher already stopped. That changes the behavior. Each caller stores the watch in its own place (`watchState` or `relatedBoards[path]`), as the finding asks.
  timestamp: 2026-10-08T02:51:34.981300+00:00
- actor: wballard
  id: 01m4cprt255z98sb29fxd46xh0
  text: |-
    ### implement — changed
    - evidence: 2 files: Sources/FoundationModelsKanban/Tool/KanbanGraph.swift and Sources/FoundationModelsKanban/Tool/Commit.swift. `swift build --build-tests`: the only warning is the accepted mlx-swift "missing creator" warning. `swift test` run 1: 902 tests in 58 suites passed. `swift test --skip-build` run 2: 902 passed. `swift test --skip-build` run 3: 902 passed. `periphery scan --retain-public --quiet -- --build-tests --build-system native`: no item in Sources. It reports 7 items, all in test files that this change did not touch. These items were there before. No line is longer than 120 characters. All 4 of 4 findings are checked.
    - next: /review
  timestamp: 2026-10-08T02:51:37.413043+00:00
depends_on:
- 01M4B3VKJ8W42AXVFVMH6WN5VQ
- 01M4B3YYXT069TKADQ93CBAA93
- 01M4B406Z7RVSBJKKJ8KJW0CY2
- 01M4B41VDXZ3NKEG4554PVXWQN
position_column: doing
position_ordinal: '80'
title: 'Cross-repo: BoardLocator and board refs'
---
## What
Find related boards on the disk and read them. The basis is plan.md §6.6 and §12 items 13 and 26.
- Add the `locator: BoardLocator = .default` parameter (the extra search roots) to `KanbanGraph.init`.
- `Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift`: scan the parent directory of the current repo (one level down) and the configured search roots for git repos. For each: key from the current `origin`; enabled if `.kanban/board.jsonl` exists. Index: key → list of directories. Scan one more time on an unknown key.
- Many copies of one key: the current key resolves to the current directory; a different key resolves to the first copy in scan order (parent directory first, then each search root in config order, then directory names in sort order). A path in `board` selects a copy.
- Board refs for `Query.board(id:)`: a key, a unique repo directory name, or a path. `Query.boards(enabled:)` lists each copy with its path; a board that is not enabled shows the directory name.
- Read across boards: `node(id:)` with a URI of a related board, and a cross-board `dependsOn` target, load that board. A loaded related board stays live and gets its own watcher. A target in a board that is not found counts as not done.

## Acceptance Criteria
- [x] Two temporary repos side by side: a task in one depends on a task in the other, and `ready` changes after the other task is completed (by `completeTask` in the same process, and by a write from a second process).
- [x] Two copies of one repo: the current key gives the current directory; a related key gives the first copy on each call; a path selects the other copy; `boards` lists both.
- [x] A board that cannot be found gives `NOT_FOUND` with the search roots in the message.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift` and `CrossRepoReadTests.swift`, with temporary git repos and worktrees.
- [x] Run `swift test --filter BoardLocatorTests` and `--filter CrossRepoReadTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-07 21:39)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 16 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:76` `swift/initialization` — `index` is an Optional that `rescan()` assigns later. Its `nil` means 'not scanned yet', not genuine absence. Callers must test `index` in `scannedIndex()`, `loadBoard` (`wasScanned`) and `relatedBoards`, and each test repeats the same first-scan rule. Build the initial index in a named method that the first call runs, and store a non-optional value after that. Or store a state enum such as `.unscanned` and `.scanned(BoardIndex)` so that the rule is named in one place.
- [x] `Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:359` `swift/preconditions` — The branch for `currentKey == nil` returns `.notFound` with no assertion and no log. This branch is not a normal requirement. `loadedSession()` sets `currentKey` before any related-board load runs, so a nil key is an unexpected state. Silent `.notFound` hides a defect in the engine from the author and from production logs. Add `assertionFailure(...)` and a `Log.kanban.error(...)` line that names the missing key before the `return .notFound`, as the Commit.swift:378-379 branch does. Or pass the key into `loadBoard` so that no nil branch exists.
- [x] `Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:435` `reuse/reuse` — startWatch(ofBoardAt:) repeats the board-directory lookup that movedWatch(_:ofBoardAt:) also does: it builds EventLog(repositoryAt:).directory and checks that it exists with FileManager. This is the first of the two copies of the same logic. Extract one private helper, for example `boardDirectory(ofBoardAt:) -> URL` or `hasBoardDirectory(ofBoardAt:) -> Bool`, and call it from both startWatch(ofBoardAt:) and movedWatch(_:ofBoardAt:).
- [x] `Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:512` `duplication/duplication` — The move-then-apply sequence is written twice. `applyCurrentBatch` and `applyBatch` each call `movedWatch`, then call `apply(_:to:afterMove:)` with the same `moved != nil` decision. The only difference is where the new watch is stored. The two copies can drift apart, for example if one later handles a failed move differently. Extract one helper that takes the watch and the session, runs `movedWatch`, and calls `apply` with the right `afterMove` value. It returns the moved watch, or nil. Each caller then stores the result in its own place: `watchState` for the current board, or `relatedBoards[path]` for a related board.
