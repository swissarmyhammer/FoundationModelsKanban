---
assignees:
- claude-code
position_column: todo
position_ordinal: b880
title: Expire the scan index only when the names of a board change
---
## What
After ^e65466d, RepoMark records the FileStamp of board.jsonl. Each write to a board log gives a `.board` ScanChange, and the scan index expires. The next call that needs the index scans again (no git, but a full scan of the places).

## Do
- On a `.board` change, read the names of that one copy again and keep the index current when only the names or the enabled state changed, in place of a full rescan.
- Keep the rule that a new board ID of a related board resolves after its board log changes (BoardIDTests.scanIndexGetsNewBoardID).

## Acceptance Criteria
- [ ] A write to a board log that does not change the board names starts no scan.
- [ ] A new board ID still resolves in the scan index of another session.