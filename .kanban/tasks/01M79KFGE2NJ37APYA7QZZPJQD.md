---
assignees:
- claude-code
position_column: done
position_ordinal: ffca80
title: A new watched folder does not make each other folder compare all its files
---
TestudoApp ^qa2eddw: each new `.kanban/` folder restarts the one FSEvents stream of the host, and after the restart each watched folder compares all its files (`BoardEngine.receive`, `EventLog.resolveConflicts`, `nodeFileSignatures`). The cost grows as the square of the number of boards.

Rejected: a start of the new stream at the last event id (`sinceWhen`). Card ^4p9q125 shows that on this machine fseventsd can keep no history ("scan_old: bailing out ... dls 0x0"), and then a stream with a past `since` gives no event at all. `FSEventsCopyUUIDForDevice` gives a UUID for that volume, so it cannot detect the problem.

Fix:
- `FolderStreams` collects the old folders of each stream change, and gives their compare batches one time after `defaultCompareDelay` (0.5 s). The changes in that time share one compare batch for each folder. The wait does not start again for a later change, so the compares always come.
- `BoardEngine.receive` checks iCloud conflicts on each file of the board only for the first batch that holds the board directory. A later such batch checks only the files that its apply read again.

Tests: `FolderStreamsTests.manyAddsGiveOneCompareForEachFolder` (20 adds, one compare batch for each old folder), `compareComesAfterWait`, the old stream-change tests with `compareNow()`, and `LogVersionMergeTests.boardDirectoryWithoutScanChecksNoFile`. #performance #step1