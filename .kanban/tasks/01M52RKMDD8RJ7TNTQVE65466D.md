---
assignees:
- claude-code
depends_on:
- 01M4XJG62C0DB0780SENXRQCGN
position_column: todo
position_ordinal: b380
title: Give each board a board ID in its log, and resolve a board by each of its names
---
## What
divergence.md M9 "each board has a board ID in its log". A board needs a fixed ID that does not come from git, so that a bare folder can have a key and `git init` later does not break links.

## Do
- `initBoard` writes one event on the board node with a new ULID, also in a git repo. An old board with no ID gets one on its next write. A load never writes.
- A board has these names: the bare ULID (`kanban://<ULID>/<type>/<id>`), the git key while it is in a repo, and each old name in its log. Each name resolves to the board.
- More than one ID event after a merge: each ID stays a name; the lowest ULID is the primary ID.
- Stored refs (`dependsOn`, assignee URI, tombstone line of a moved task) use the git key when there is one, else the ULID. The input accepts each name.
- When the git key changed (new remote, `git init` above the folder), record the old git key as an old name on the next write.
- The host keeps an index of all names for each scanned board. The scan reads the board node log one time. The watcher keeps the index current.

## Acceptance Criteria
- [ ] A new board has one ID event. An old board gets it on the next write, not on load.
- [ ] A URI with the bare ULID and a URI with the git key resolve to the same board.
- [ ] A merged log with two ID events: both resolve; the lowest is primary.
- [ ] A remote change records the old git key, and a URI with the old key still resolves.
- [ ] Tests use temporary git repos and temporary folders only.