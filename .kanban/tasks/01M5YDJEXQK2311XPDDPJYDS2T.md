---
assignees:
- claude-code
position_column: done
position_ordinal: ffc580
title: KanbanHost.publish restarts the change log of a board that did not change
---
Defect report from KanbanViewKit (tracking card ^5qbe4te), found at d07d5b0.

## Cause
- `KanbanHost.publish(_:)` reads `views` one time at its start, and then awaits `view.publish(changed, skipping:)` for each view. Other publishes interleave at these awaits.
- After the awaits, it restarts the log of each loaded engine that no view in the old snapshot logged. This includes an engine that did not change, and an engine whose view registered after the snapshot.
- A cursor from before the restart then gives `RESYNC_REQUIRED`, and each open subscriber of that board ends.

## Fix
- Send the round also to each view that registers while the round runs, until no view is left.
- Restart the log of an engine that no view logged only when the engine changed in the round, or when its graph names another board (a cross-board dependency or assignee). A board that names no other board and did not change has no change to log.

## Not changed
- A subscription after `KanbanGraph.close()` registers the view again. `KanbanGraph.close()` documents this behavior ("takes the view out of the host until its next subscription"), so it stays.

## Acceptance
- [x] Regression test: many boards in one host, interleaved writes. No board that did not change gets a log restart, and a cursor stays valid (`ChangeLogRestartTests`). The old code fails 5 of 5 runs; the fix passes 5 of 5 runs.
- [x] Full test suite is green, with no new warnings: 1898 tests in 165 suites passed. #bug