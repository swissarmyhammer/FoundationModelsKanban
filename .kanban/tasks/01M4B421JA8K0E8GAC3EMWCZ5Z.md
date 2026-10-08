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