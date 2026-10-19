---
assignees:
- claude-code
position_column: todo
position_ordinal: b980
title: Give the current board of a session the git key after git init in its bare folder
---
## What
Found in ^cggdpve. A loaded engine now takes a new key when the scan or an expired path-ref record reads a key from git (`KanbanHost.engine(identifiedBy:at:knownKey:)` calls `BoardEngine.changeKey(to:)`). The current board of a session does not get this: `KanbanGraph.prepareBoard` loads it with `host.engine(ofBoardAt:)` and no known key, and nothing reads git again for it. After `git init` in the bare folder of the working directory of a session, `{ board { key } }` on that session gives the old board ID until a scan or a path ref reaches the folder, or the process restarts.

divergence.md M9: when the git key of a board changes, the engine must use the new key.

## Acceptance Criteria
- [ ] After `git init` in the bare folder of the working directory of a session, `{ board { key } }` on that session gives the git key with no restart.
- [ ] The next write records the old board ID key as a board ID of the board.
- [ ] Tests use temporary folders and temporary git repos only.