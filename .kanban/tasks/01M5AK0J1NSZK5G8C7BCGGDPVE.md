---
assignees:
- claude-code
position_column: todo
position_ordinal: b980
title: Give a loaded engine the git key after git init in its bare folder
---
## What
divergence.md M9: when the git key of a board changes (for example `git init` in a bare folder), the engine must use the new key and record the old key as an old name.

Found in ^d5y7aay: after `git init` in a bare board folder, the path-ref record expires and the host reads git again, but the engine that the host loaded before the `git init` keeps its board ID key. `board(id: <path>) { key }` gives the old board ID until the process restarts.

## Acceptance Criteria
- [ ] After `git init` in the folder of a loaded bare board, `board { key }` gives the git key with no restart.
- [ ] The next write records the old board ID key as a name of the board.
- [ ] Tests use temporary folders and temporary git repos only.