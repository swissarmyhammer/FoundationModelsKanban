---
assignees:
- claude-code
position_column: done
position_ordinal: ffc980
title: A write runs a change round only in the session views of its board
---
TestudoApp ^qa2eddw: `sample` showed that `KanbanHost.publish(_:)` sends each write to each session view, and each view calls the file system (`URL.canonicalPath`) for each engine. With many boards and views, each write costs O(views) file system calls.

Fix:
- `BoardEngine.canonicalRoot` holds the canonical path of the root. The engine calculates it one time, at its start.
- `KanbanGraph.publish(_:skipping:)` runs no round when the view loaded no board at a path of the write. The check reads only memory. The view tells that it logged its engines, the same as a round with no change, so no change log restarts.
- The round calculates the canonical path of the current board one time.

Test: `KanbanHostTests.writeRunsRoundOnlyInViewsOfItsBoard` (8 boards, 9 views, one write, rounds only in the 2 views of the written board). #performance #step1