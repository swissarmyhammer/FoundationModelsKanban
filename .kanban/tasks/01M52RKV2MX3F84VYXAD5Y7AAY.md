---
assignees:
- claude-code
depends_on:
- 01M52RKMDD8RJ7TNTQVE65466D
position_column: todo
position_ordinal: b480
title: Put back boards in bare folders, with search up outside git
---
## What
divergence.md M9 "where the board is". A board can be in a folder that is not in a git repo. This replaces the M5 rule "a board exists only in a git repo". The old code in commits `afca516` (^fv1dcq3) and `107ffed` (^8dy1xz2) can be a start.

## Do
- In a git repo: the board stays at `<repo top>/.kanban/` (no change).
- Outside git: use the nearest folder, from the working directory up, that has a `.kanban/`. When none has one, use `<working dir>/.kanban/` (made on the first write). The key is the board ULID (^e65466d).
- Remove `NOT_A_REPO` for a folder outside git. A `board:` path to a bare folder names its board.
- `Query.boards` and the related-board scan also find sibling folders with a `.kanban/` and no `.git`.
- Two folders with the same board ULID (a copied folder): calls work, with a warning that names both paths.
- A `.kanban/` in a subfolder below a repo top: calls use the repo board, with a warning that names the subfolder board and tells the user to run `collectBoards`.

## Acceptance Criteria
- [ ] A session in a bare folder, and in a subfolder of it, uses the nearest `.kanban/` above.
- [ ] A session in a bare folder with no `.kanban/` above makes one in the working dir on the first write.
- [ ] `boards` lists a sibling bare-folder board.
- [ ] The copied-folder warning and the subfolder-in-repo warning are given.
- [ ] Tests use temporary folders and temporary git repos only.