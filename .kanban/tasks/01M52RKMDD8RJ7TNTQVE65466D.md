---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5aevne78n21zss2wpwy1yx7
  text: |-
    Research done. Findings:
    - Each public mutation runs through WorkingCopy.applyMutationRules (MutationResolvers.swift). The auto-init and the session actor are written there. This is the place for the board ID event: when the field keeps a patch (or the board is new) and the board node has no ID, write one board patch `add boardIds [kanban://<ULID>/board]` and `set gitKey <key>`.
    - Set-valued properties hold StoredRef members, and a member can be a remote board URI. Thus the IDs and the old names are members of `boardIds` and `oldNames`, and a union merge keeps all ID events. Replay (NodeFold.makeState) must read them into BoardNode.
    - Undo: NodeInverse reverses each property of an existing node. The board identity properties must be kept out of the inverse, else undo removes the ID.
    - Board refs resolve in BoardIndex.resolution (current key compare, then copy key compare), in RefResolver (localKey and the .board short form use one boardKey string), in KanbanHost.pathCopy and loadedCopies. Each compares one key today; each must compare all names.
    - NodeURI parsing lowercases the first key segment, so a bare ULID key becomes lowercase. The normalization must keep a ULID in its canonical form.
    - The scan builds BoardCopy(directory:key:) and reads the enabled state there. RepoMark records only hasBoardLog, so a write to board.jsonl gives no ScanChange. The mark must record the file stamp of board.jsonl, so that a change expires the index and the rescan reads the names again (keys are reused, no git).
    - The engine reads the git key one time at load. A remote change shows at the next load; the recorded gitKey in the log tells the old key.
  timestamp: 2026-10-19T16:10:35.335111+00:00
- actor: claude-code
  id: 01m5afmg738bb7a580brzdx3xn
  text: |-
    Progress (implementation in the working tree, not committed):
    - BoardNode has ids, gitKey, oldNames (Replay reads the members of boardIds and oldNames as board URIs kanban://<name>/board, and the value of gitKey).
    - New Identity/BoardNames.swift: BoardNames (key, ids, old names, kind(of:), contains, all, read(fromRepoAt:key:)), BoardNameKind, StoredRef.board(named:), ULID(boardKeyText:). BoardKey.normalizedText keeps a one-segment ULID key in uppercase.
    - WorkingCopy.applyMutationRules now takes inBoard key; recordBoardNames writes one board patch (add boardIds when none, add oldNames when the recorded gitKey differs, set gitKey). All 4 call sites updated.
    - NodeInverse skips BoardNode.nameProperties for the board node, so undo keeps the ID.
    - BoardCopy has names; scan reads them from the board log. BoardIndex.resolution(of:currentRoot:currentNames:) ranks key < board ID < old name. RepoMark records the board log FileStamp, so a write to board.jsonl gives a .board change and the index scans again (keys reused).
    - Tool/SessionNames.swift: CommitSession.names and copy(at:); KanbanGraph uses them for the current copy. KanbanHost.loadedCopies and pathCopy match all names.
    - RefResolver treats each name of its board as local. CrossRepo/StoredRefNames.swift: RelatedBoards.storedEdges rewrites a remote ref to the current key of the loaded board; WorkingCopy.write uses it.
    - GraphQL/BoardNameFields.swift: Board.boardId and Board.names.
    - Tests: Tests/FoundationModelsKanbanTests/CrossRepo/BoardIDTests.swift (12 tests). Next: update test call sites of resolution(currentKey:) and the 3-arg BoardCopy init, then run the suite.
    Note: the edit tool echoes the whole file; KanbanGraph/Schema edits went to tool-results files.
  timestamp: 2026-10-19T16:24:09.187920+00:00
- actor: claude-code
  id: 01m5age5k515yn47cw3z2xjw3t
  text: |-
    ### implement — changed
    - evidence: swift test: 1626 tests in 133 suites passed, 0 failures; only the allowed SwiftPM "missing creator" warning. BoardIDTests: 12 tests pass.
    - Decisions: the board log stores the names (boardIds and oldNames as kanban://<name>/board members, gitKey as a value) per M9; the old test "no log line holds the key of its own board" now allows only the board names patch in board.jsonl. New fields Board.boardId (primary = lowest ULID) and Board.names. "Stored refs use the git key, else the ULID": each board has a git key today, so the stored key is the git key; the ULID fallback belongs to ^5y7aay (bare folders). Updated tests that counted board events or the order of updates (extra board names patch).
    - Follow-up task added: expire the scan index only when board names change (each board.jsonl write now starts one rescan with no git).
    - next: /review
  timestamp: 2026-10-19T16:38:10.277668+00:00
depends_on:
- 01M4XJG62C0DB0780SENXRQCGN
position_column: doing
position_ordinal: '80'
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