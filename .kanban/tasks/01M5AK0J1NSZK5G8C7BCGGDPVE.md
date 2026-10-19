---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5amk6f5ch2pama1gbkjh2w5
  text: |-
    Research and implementation.

    Cause: `KanbanHost.engine(identifiedBy:at:knownKey:)` gave back a loaded engine and did not use `knownKey`. After `git init`, the path-ref record expires, `board(ofFolderAt:)` reads the git key, and `KanbanGraph.loadRelatedBoard` calls `relatedEngine(ofBoardAt:knownKey:)` with the git key. But the engine kept its `CommitSession.key` (the board ID). A second gap: a bare board with no write before the `git init` has its board ID only in `BareBoardIDs` (memory). After a key change, the next write minted a new board ID, and the old board ID key was lost.

    Change:
    - `CommitSession.key` can change now: `changeKey(to:)` keeps the old key in `formerKeys`. `takeKey(of:)` copies the key and the former keys.
    - `BoardEngine.changeKey(to:)` changes the key with no wait for the gate (a caller can hold the gate of the engine while it loads a related board, so a gate wait can deadlock). `replaceSession(with:)` and the watcher apply keep the current key (`storeKeepingKey`), so a call that started before the change does not put the old key back.
    - The host calls `engine.changeKey(to: knownKey)` for each engine it gives back when the caller knows a key.
    - `WorkingCopy.formerKeys` comes from the session. `recordBoardNames` records each former git key as an old name, and each former board ID key as a board ID. `newBoardIDs` mints a new ID only when the board has no ID and no board ID key.
    - divergence.md M9: one sub-bullet that states this.
    - The `git init` test in PathRefCacheTests checks the git key again (key change check restored). It now uses a `BareFolderRepo` fixture, shared with the new write test.

    Proof that the tests can fail: with `formerKeys` taken out of `recordBoardNames`, the two write tests in BoardKeyChangeTests and the write test in PathRefCacheTests fail.

    Not in scope, new task ^1wr5pqv: the current board of a session (loaded with no known key) does not read git again after `git init` in its own working directory.
  timestamp: 2026-10-19T17:50:49.317221+00:00
- actor: claude-code
  id: 01m5amk9mjvcte6pn924k2dwyw
  text: |-
    ### implement — changed
    - evidence: `swift test` 1636 tests in 135 suites passed; no warning except the accepted mlx "missing creator". RED first: PathRefCacheTests/gitInitReadsGitKey (key was the board ID) and gitInitWriteRecordsBareKey (no gitKey). Files: Sources/FoundationModelsKanban/Tool/Commit.swift, Tool/BoardEngine.swift, Tool/KanbanHost.swift, GraphQL/MutationResolvers.swift, divergence.md, Tests/FoundationModelsKanbanTests/CrossRepo/PathRefCacheTests.swift, Tests/FoundationModelsKanbanTests/Tool/CommitTests.swift, Tests/FoundationModelsKanbanTests/Tool/BoardKeyChangeTests.swift (new).
    - next: /review
  timestamp: 2026-10-19T17:50:52.562794+00:00
position_column: doing
position_ordinal: '80'
title: Give a loaded engine the git key after git init in its bare folder
---
## What
divergence.md M9: when the git key of a board changes (for example `git init` in a bare folder), the engine must use the new key and record the old key as an old name.

Found in ^d5y7aay: after `git init` in a bare board folder, the path-ref record expires and the host reads git again, but the engine that the host loaded before the `git init` keeps its board ID key. `board(id: <path>) { key }` gives the old board ID until the process restarts.

## Acceptance Criteria
- [x] After `git init` in the folder of a loaded bare board, `board { key }` gives the git key with no restart.
- [x] The next write records the old board ID key as a name of the board.
- [x] Tests use temporary folders and temporary git repos only.