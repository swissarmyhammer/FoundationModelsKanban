---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5aw28805rdas8hj3fwgz2r0
  text: |-
    Research done.
    - The expiry rule is in BoardIndex.isExpired(by:) and BoardIndex.forgetting(expiredBy:) (CrossRepo/ScanChange.swift). ScanRecord.apply and ScanRecord.finishScan (CrossRepo/ScanCache.swift) call forgetting(expiredBy:). Each `.board(inRepo:)` change whose RepoMark is not the same as the scan mark expires the index now, so the next call scans again.
    - The names and the enabled state of a copy come from BoardCopy.read(fromRepoAt:key:) (CrossRepo/BoardLocator.swift). It reads only the board log, with no git. A `collected` patch adds old names to the board log, and collectBoards removes the `.kanban/` of each source. Both give a `.board` change.
    - Plan: on a `.board` change of a repo that has a copy in the index and that is still a repo (RepoMark not nil), read the copy again with its known key and keep the index current. When no copy is at the repo (a new bare board, or a repo whose key read failed), or the folder is no repo now, keep the old rule: expire the index.
    - ScanRecord.apply must store the new index also when the change does not expire it.
    - FolderBoard.isExpired(by:ofRepoAt:) (path ref records) already ignores `.board`. No change there.
  timestamp: 2026-10-19T20:01:22.688910+00:00
- actor: claude-code
  id: 01m5awc7yqdgp27ngvrysdg0qw
  text: |-
    Implementation landed.
    - BoardIndex.forgetting(expiredBy:) (CrossRepo/ScanChange.swift): a `.board` change of a repo that has a copy in the index, and that is still a repo, now reads that copy again with its known key (new private helper readingBoardLog(of:), which calls BoardCopy.read(fromRepoAt:key:)). The index stays current. The new names (board IDs, old names of a `collected` patch) and the enabled state are in the index at once. A `.board` change with no copy at the repo (a new bare board, a repo whose key read failed) or of a folder that is no repo now keeps the old rule: it expires the index.
    - ScanRecord.apply (CrossRepo/ScanCache.swift) now stores the new index also when the change does not expire it. finishScan uses the same rule, so a board log write during a scan gives the result the new names.
    - Docs updated: ScanChange.board, BoardIndex.isExpired(by:), BoardIndex.forgetting(_:), KanbanHost.currentScanIndex(around:).
    - Changed one existing test: ScanMarksTests.placeChangeAfterBoardLogKeepsKeys asserted the old rule (a new board log makes the index stale). It now asserts the decided rule: the index stays current and the copy is enabled.
    - Discovery: each commit to the current board also gives `.board` for the current repo (it is in the parent place). That change now reads the board log of that one repo, in place of a full rescan on the next call.
    - New tests: ScanChangeTests boardLogWriteWithSameNamesKeepsIndex, boardLogWriteWithNewNameUpdatesIndex, boardLogWriteDuringScanUpdatesResult, removedBoardLogDisablesCopy; ScanCacheTests newBoardIDResolvesWithNoScan (host level, asserts no new scan). All five failed first (RED), then passed.
    - Full suite: swift test, 1691 tests in 140 suites passed. Only the accepted SwiftPM "missing creator" warning. BoardIDTests.scanIndexGetsNewBoardID passes.
  timestamp: 2026-10-19T20:06:50.071761+00:00
- actor: claude-code
  id: 01m5awcad0qhe57ytpbe73xd0z
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsKanban/CrossRepo/ScanChange.swift, Sources/FoundationModelsKanban/CrossRepo/ScanCache.swift, Sources/FoundationModelsKanban/Tool/KanbanHost.swift, Tests/FoundationModelsKanbanTests/CrossRepo/ScanChangeTests.swift, Tests/FoundationModelsKanbanTests/CrossRepo/ScanCacheTests.swift, Tests/FoundationModelsKanbanTests/CrossRepo/ScanMarksTests.swift; swift test: 1691 tests in 140 suites passed, 0 failures
    - next: review
  timestamp: 2026-10-19T20:06:52.576635+00:00
position_column: doing
position_ordinal: '80'
title: Expire the scan index only when the names of a board change
---
## What
After ^e65466d, RepoMark records the FileStamp of board.jsonl. Each write to a board log gives a `.board` ScanChange, and the scan index expires. The next call that needs the index scans again (no git, but a full scan of the places).

## Do
- On a `.board` change, read the names of that one copy again and keep the index current when only the names or the enabled state changed, in place of a full rescan.
- Keep the rule that a new board ID of a related board resolves after its board log changes (BoardIDTests.scanIndexGetsNewBoardID).

## Acceptance Criteria
- [x] A write to a board log that does not change the board names starts no scan.
- [x] A new board ID still resolves in the scan index of another session.