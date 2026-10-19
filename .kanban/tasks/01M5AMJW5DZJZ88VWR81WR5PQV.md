---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5av61fnsf2a2prkcf15wmym
  text: |-
    Research.

    - `KanbanGraph.resolveBoard` loads the current board with `host.engine(ofBoardAt: root)` and no known key. In the `.notARepo` branch the root is `BareBoard.root(of:)` and the key is a board ID (`HostConfiguration.boardKeyReader` falls back to `BareBoardIDs`).
    - The engine watcher watches `root/.kanban/` (or `root` until `.kanban/` is there). A `git init` in `root` makes `root/.git`, which the engine watcher does not see when `.kanban/` is there.
    - The place watchers of the host start only with a scan, so a session that makes no scan has no place watcher.
    - `WatchedPlace(watching: parent)` maps `root/.git` and `root/.git/config` to `ScanChange.repo(root)`, and a compare batch (`compareEachFile()`) to `.place(parent)`. The known-folder watch of a path ref uses the same method.

    Plan: the host starts one watch on the parent folder of the root of each current board outside git (keyed by the engine identity). When a batch gives `.repo(root)` or `.place(parent)` and `root` has a `.git` entry, the host reads the key one time with `boardKeyReader` and calls `engine.changeKey(to:)`. Thus git runs only after a file change, never on a read. The watch stops when the key is no longer a board ID, when the engine retires, and at host close. A compare batch after the start finds a `git init` between the key read and the start of the watch. A new `BoardScanObserver.bareBoardKeyDidChange(_:)` call lets a test wait.
  timestamp: 2026-10-19T19:45:58.261813+00:00
- actor: claude-code
  id: 01m5avnfbvg6wmax0fwj5hs57d
  text: |-
    Implementation landed.

    - `KanbanGraph.resolveBoard` now calls `KanbanHost.engine(ofSessionBoardAt:)`. That method loads the engine as before. When the engine key is a board ID, it calls `watchGitInit(of:)`.
    - `watchGitInit(of:)` starts one file watcher on the parent folder of the board root, for each engine (table `bareBoardWatches`, by folder identity). After the start it calls `compareEachFile()`, so a `git init` between the key read of the load and the watcher start shows too.
    - `bareBoardDidChange(_:in:at:)`: when a batch holds `.repo(root)` or `.place(parent)` and `root` has a `.git` entry, the host reads the key one time with `boardKeyReader`. A git key goes to `engine.changeKey(to:)`, the watcher stops (`stop()`, not `end()`, because the method runs in the task of the watch), and `BoardScanObserver.bareBoardDidChange(_:)` gets the change. A board ID or a failed read keeps the watcher. Git runs only after a file change, never on a read.
    - `retire(_:)` and `close()` stop the watch. A new shared `makeParentWatch(ofRepoAt:sendingBatchesTo:)` is now also the body of `makeKnownFolderWatch`. A new `isLoaded(_:)` is used by `retire(_:)` and `watchGitInit(of:)`. A new `BoardEngine.key` gives the current key.
    - divergence.md M9: one sub-bullet for the current board outside git.
    - Change from the research plan: the observer method is `bareBoardDidChange(_:)`, not `bareBoardKeyDidChange(_:)`.

    Tests: Tests/FoundationModelsKanbanTests/Tool/SessionGitInitTests.swift (2 tests). RED: both failed with FolderEventTimeout (no event, key stayed the board ID). GREEN after the change.

    Not in scope: a `git init` in a parent folder above the bare board folder moves the board to a new place, so the engine does not change. A new remote on the current board of a git repo is also not in scope.
  timestamp: 2026-10-19T19:54:23.995368+00:00
- actor: claude-code
  id: 01m5avnj32098166te5gf3jqjh
  text: |-
    ### implement — changed
    - evidence: `swift test` 1686 tests in 140 suites passed; `swift build --build-tests` gives no warning except the accepted SwiftPM "missing creator". RED first: SessionGitInitTests (2 tests) failed with FolderEventTimeout. Files: Sources/FoundationModelsKanban/Tool/KanbanHost.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Sources/FoundationModelsKanban/Tool/BoardEngine.swift, Sources/FoundationModelsKanban/CrossRepo/ScanChange.swift, divergence.md, Tests/FoundationModelsKanbanTests/CrossRepo/ScanCacheTests.swift, Tests/FoundationModelsKanbanTests/Tool/SessionGitInitTests.swift (new).
    - next: /review
  timestamp: 2026-10-19T19:54:26.786136+00:00
position_column: doing
position_ordinal: '80'
title: Give the current board of a session the git key after git init in its bare folder
---
## What
Found in ^cggdpve. A loaded engine now takes a new key when the scan or an expired path-ref record reads a key from git (`KanbanHost.engine(identifiedBy:at:knownKey:)` calls `BoardEngine.changeKey(to:)`). The current board of a session does not get this: `KanbanGraph.prepareBoard` loads it with `host.engine(ofBoardAt:)` and no known key, and nothing reads git again for it. After `git init` in the bare folder of the working directory of a session, `{ board { key } }` on that session gives the old board ID until a scan or a path ref reaches the folder, or the process restarts.

divergence.md M9: when the git key of a board changes, the engine must use the new key.

## Acceptance Criteria
- [x] After `git init` in the bare folder of the working directory of a session, `{ board { key } }` on that session gives the git key with no restart.
- [x] The next write records the old board ID key as a board ID of the board.
- [x] Tests use temporary folders and temporary git repos only.