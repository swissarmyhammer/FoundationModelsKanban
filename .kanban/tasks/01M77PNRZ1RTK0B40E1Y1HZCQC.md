---
assignees:
- claude-code
position_column: done
position_ordinal: ffc880
title: Merge the iCloud conflict versions of a board log (D179)
---
The TestudoApp default board is in iCloud Drive (D178, D179). A person must never resolve an iCloud conflict of a board.

When a `.jsonl` log of a board has conflict versions (`NSFileVersion.unresolvedConflictVersionsOfItem(at:)`), Kanban merges them:
- Read the current version and each conflict version.
- Drop the torn tail of each version (the bytes after the last line feed).
- Keep each event one time by its id, and each abort record one time by its transaction.
- Write the lines in id order, with an NSFileCoordinator write, under the board lock.
- Set `isResolved = true` on each conflict version, then call `NSFileVersion.removeOtherVersionsOfItem(at:)`.

This is the same rule as the `merge=union` git attribute and `EventMerge.merged`. A file of the board that is not a log keeps its current version.

Detection: the engine checks the changed log files of each watcher batch before the apply. A batch that holds the board directory checks each log file.

Tests: the merge function on plain version files. The NSFileVersion glue stays thin. #icloud