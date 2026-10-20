---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5be2cewg18ebkxm55twrsta
  text: |-
    ### finish iteration 1 — stuck
    - implement: not run — the task needs a decision by a person before work can start (see "Decision needed": rewrite the merged lists, ignore `board` in the check, or merge the source board log lines; each changes a recorded decision)
    - next: a person chooses one option and records it in divergence.md, then `/finish ^16js6jx`
  timestamp: 2026-10-20T01:16:01.372039+00:00
- actor: claude-code
  id: 01m5bet0j1e9fm4zpjb22asadg
  text: |-
    ### decision — merge the source board log lines
    - The user chose option 3: `collectBoards` also merges the lines of the source board log that belong to a merged transaction.
    - Recorded in divergence.md M9 `collectBoards`, "Changed (2026-10-19)". The target keeps its own board ID, git key, and name; a merged board line does not change them.
    - next: `/finish ^16js6jx`
  timestamp: 2026-10-20T01:28:55.617962+00:00
- actor: claude-code
  id: 01m5bezmqs8t7j038qjj8wwvy3
  text: |-
    Research:
    - `CollectedSource.read` drops the board log (`refs.filter { ref != .board }`). `WorkingCopy.merge` adds node events to `merged`; the commit writes, marks, fsyncs, and rolls back `merged` the same as kept events. Thus a board line that goes through `merge` gets the same crash safety and the same dry-run path.
    - The board node folds by event id (Replay `NodeFold`): `name` and `gitKey` are `set` (the last event id wins), `boardIds` and `oldNames` are `add` lists (union; `remove` takes members out). Thus a merged source board line can give the target the source name, the source git key, and a second board ID (the lowest ID is the primary ID).
    - `WorkingCopy.merge` does not advance the stamp past the merged event ids. A collect whose engine mints ids that are lower than the source ids would write a patch that a merged source `set` overrides.
    - Plan: read the source board lines whose `txn` is a `txn` of a source node line; merge them inside the mutation-rules body; then write one board patch that sets back the name and git key of the target before the merge and removes each board ID that the target did not have. `merge` advances the stamp past the largest merged event id. A new target then gets a new board ID and its folder name from the mutation rules, as before.
  timestamp: 2026-10-20T01:32:00.121532+00:00
- actor: claude-code
  id: 01m5bfah2tp84cqk0cdgpwtmn8
  text: |-
    Implementation landed:
    - `CollectedSource.boardEvents`: the lines of the source board log whose `txn` is the `txn` of a source node line.
    - `WorkingCopy.addCollected` merges these lines with `merge`, then `keepBoardNames(of:at:)` writes one board patch: it sets back the name and git key that the target had before the merge (or clears them), and removes each board ID that the target did not have. `addCollected` runs in the dry-run path and in the write path, so `dryRun` makes the same merge. The merged board lines go into `WorkingCopy.merged`, so the commit marks, appends, fsyncs, and rolls them back the same as the other merged lines. The source board file is already in `signatures`, so the lock check covers it.
    - `WorkingCopy.merge` now advances the stamp past the largest merged event id (divergence.md S3). Without this, a target engine whose ids are lower than the source ids writes a restore patch that a merged source `set` overrides. The test `targetKeepsItsBoardNames` uses a target engine at time step 0 to show this.
    - For a new target, the in-memory board has the folder name and no ID, so the restore patch keeps the folder name and removes the source IDs; `recordBoardNames` then mints a new ID (`makesTargetBoard` still passes).
    - The merge report (`slugMerges`, `conflicts`) does not include the board node: the target values win, so a board conflict would not be true.
    - Tests: `freshLoadHoldsNoMergedLine` (RED: held `addTask` lines; GREEN after the merge of board lines), `targetKeepsItsBoardNames` (RED after the merge alone: source ID, git key, and name won; GREEN after the restore patch and the stamp advance).
    - Docs: divergence.md M9 "Changed (2026-10-19)" now says how the target values win; `CollectBoardsField` doc comments name the board lines.
  timestamp: 2026-10-20T01:37:56.826798+00:00
- actor: claude-code
  id: 01m5bfapdd79kqv7jmwbqmabtt
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/CrossRepo/BoardCollect.swift, Sources/FoundationModelsKanban/Tool/Commit.swift, Sources/FoundationModelsKanban/GraphQL/CollectBoardsField.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CollectBoardsTests.swift, divergence.md; `swift test`: 1703 tests in 140 suites passed, only the accepted SwiftPM "missing creator" warning
    - next: /review ^16js6jx
  timestamp: 2026-10-20T01:38:02.285866+00:00
position_column: doing
position_ordinal: '80'
title: Merged collectBoards lines are held after a fresh load when their source transaction also wrote the source board log
---
## What
Found during ^ye4xk09. `collectBoards` does not merge the board log of a source (`S/CrossRepo/BoardCollect.swift`, divergence.md M9). The first transaction of a source board (auto-init and `addTask`) writes `board` and the node logs. Its lines name `board` in their `files` list (divergence.md Q23), and they keep this list when they are merged into the target (Q23 "Changed (2026-10-19)").

The target board log has no line of that source transaction. So a fresh load of the target (`BoardLoader.load`) holds all merged lines of that transaction: the columns, the task, and the actor of the source. The live graph after the call shows them, because `LiveGraph.adopt` applies the written events with no check. After a restart, the tasks are not on the board.

The old count check had the same problem: the count named 7 files, and the target holds 6 of them.

## Reproduce
`CollectBoardsTests` fixture: collect the two sources, then `BoardLoader(reading: EventLog(repositoryAt: target)).load()`. `heldEvents` holds the merged `addTask` lines of each source. The test `collectTransactionListsOnlyItsFiles` checks only the collect transaction for this reason.

## Decision needed
A person must choose the fix, because each option changes a recorded decision:
- `collectBoards` rewrites the list of each merged line to drop the refs that it does not merge (`board`). This changes "merged lines keep their own list".
- The transaction check ignores `board` in the list of a line in a different file. This weakens the crash check of the board log.
- `collectBoards` merges the lines of the source board log that belong to a merged transaction. This changes M9.

Decided: option 3 (divergence.md M9 `collectBoards`, "Changed (2026-10-19)"). The target keeps its own board ID, git key, and name.

## Acceptance Criteria
- [x] After `collectBoards` and a fresh load of the target, no merged line is held.
- [x] The target keeps its own board ID, git key, and name after a merged board line.
- [x] Tests use temporary folders only.