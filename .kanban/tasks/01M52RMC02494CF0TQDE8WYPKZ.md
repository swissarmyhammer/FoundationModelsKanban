---
assignees:
- claude-code
depends_on:
- 01M52RKV2MX3F84VYXAD5Y7AAY
- 01M52RM3SJT6S3R1PVF99E0H99
position_column: todo
position_ordinal: b780
title: Add collectBoards to combine .kanban folders into one target board
---
## What
divergence.md M9 "collectBoards". A user can combine any list of `.kanban` folders into one target `.kanban`, for example the subfolder boards below a repo top, or boards made by mistake with search up (^d5y7aay).

## Do
- `collectBoards(sources:, target:, dryRun:, reach:)`. A source is any folder or board ref.
- Add the event lines of each source node log to the target node log with the same name (the same as a git union merge). Tasks and comments keep their ULIDs. The same slug for a column, tag, or actor becomes one node. List each field conflict and the value that won by event order.
- Write one `collected` event on the target board for each source: each board ID, git key, and old name of the source, and the source path, time, and actor. These become old names of the target (^e65466d).
- When the target has no board, make it with a new ULID. In a git repo the target must be the repo top.
- Lock all boards. A Rust board stops the call with `INCOMPATIBLE_BOARD`. The write is crash safe.
- Remove each source `.kanban` folder after the write.
- Collect is final; `undo` does not reverse it. `dryRun: true` reports the slug merges, the conflicts, and the link repairs, and writes nothing.
- Run `checkLinks` and `repairLinks` (^rctvtvc, ^99e0h99) on the target. Repair other reachable boards only with `reach: true`. Always report the old-name links found in other boards.

## Acceptance Criteria
- [ ] Two boards with tasks, comments, and a shared `todo` column collect into one board with all tasks and one `todo` column.
- [ ] A URI with an old name of a source resolves to the target after collect.
- [ ] A `dependsOn` between the two sources becomes a local ref.
- [ ] Each source folder is removed. `dryRun: true` writes and removes nothing.
- [ ] A target with no board is made.
- [ ] A Rust source stops the call and writes nothing.
- [ ] Tests use temporary folders and temporary git repos only.