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
- actor: claude-code
  id: 01m5agt3xzqvyce26zxbnge4j2
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (d080282). 7 findings, 7 confirmed, 2 refuted. Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift:260, Sources/FoundationModelsKanban/CrossRepo/ScanMarks.swift:127, Tests/FoundationModelsKanbanTests/CrossRepo/BoardIDTests.swift:71, Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift:148, Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift:366, Tests/FoundationModelsKanbanTests/CrossRepo/ScanChangeTests.swift:51, Tests/FoundationModelsKanbanTests/Design/PortabilityTests.swift:174.
    - acceptance: Each of the 5 acceptance items has a test in Tests/FoundationModelsKanbanTests/CrossRepo/BoardIDTests.swift. Item 1: newBoardHasOneIDEvent, oldBoardGetsIDOnNextWrite. Item 2: boardIDAndGitKeyResolveToOneBoard, taskURIWithBoardIDResolves, relatedBoardResolvesByBoardID. Item 3: mergedBoardLogKeepsEachID. Item 4: remoteChangeRecordsOldKey. Item 5: the tests use GitSandbox and CrossRepoFixture.SideBySide (temporary folders). The reviewer did not run the tests. The reviewer did not change the checkboxes. The implementer must set them.
    - next: implement the 7 findings, then review again.
  timestamp: 2026-10-19T16:44:41.791814+00:00
- actor: claude-code
  id: 01m5agtmgkcb29ccr6rf83hv7z
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 19 Sources files, 10 test files
    - test: green — swift test, 1626 passed
    - commit: d080282
    - review: findings — BoardLocator.swift:260, ScanMarks.swift:127, BoardIDTests.swift:71, BoardLocatorTests.swift:148, BoardLocatorTests.swift:366, ScanChangeTests.swift:51, PortabilityTests.swift:174
  timestamp: 2026-10-19T16:44:58.771578+00:00
- actor: claude-code
  id: 01m5ah3bzk8gyq49hgw8rm97a0
  text: |-
    Review findings (2026-10-19 11:40) fixed. Each cause is removed from the whole file:
    - BoardLocator.swift: the init BoardCopy(directory:key:) is gone. The new explicit step BoardCopy.read(fromRepoAt:key:) reads isEnabled and the names. The scan and BoardLocator.board(ofFolderAt:) call it. The memberwise init only stores values. The isEnabled disk read also left the init, because the finding says "Keep init(directory:key:) to storing the values".
    - New EventLog.boardLogURL(inRepositoryAt:) holds the board log location. RepoMark.init?(ofRepoAt:), BoardCopy.hasBoardLog(at:) and ScanCacheTests (a site that this change added) call it.
    - New BoardNames.init(key: BoardKey, board: BoardNode? = nil). BoardLocatorTests (3 sites, also the third copy at the outside-repo helper), ScanChangeTests, BoardNames.read (2 sites) and CommitSession.names use it.
    - BoardIDTests: undoKeepsBoardID calls Self.boardNode(inRepoAt:).
    - PortabilityTests.linesHolding builds its value with compactMap and Dictionary(uniqueKeysWithValues:). A new helper lines(of:) removes the repeated split of a log into lines (linesHolding and boardNamesLines).
    - Note: a local `let lines = lines(of:)` in a closure does not compile in Swift (use before declaration), so the local is named `held`.
    Acceptance: I read BoardIDTests.swift. Each of the 5 items has a test (newBoardHasOneIDEvent, oldBoardGetsIDOnNextWrite, boardIDAndGitKeyResolveToOneBoard, mergedBoardLogKeepsEachID, remoteChangeRecordsOldKey; GitSandbox and SideBySide temporary folders). All pass, so I set the 5 items to [x].
  timestamp: 2026-10-19T16:49:44.947717+00:00
- actor: claude-code
  id: 01m5ah3f1rddkgs5ep36mg1fyp
  text: |-
    ### implement — changed
    - evidence: swift test: 1626 tests in 133 suites passed, 0 failures; only the allowed SwiftPM "missing creator" warning. Files: Sources/.../CrossRepo/BoardLocator.swift, Sources/.../CrossRepo/ScanMarks.swift, Sources/.../Events/EventLog.swift, Sources/.../Identity/BoardNames.swift, Sources/.../Tool/SessionNames.swift, Tests/.../CrossRepo/BoardIDTests.swift, Tests/.../CrossRepo/BoardLocatorTests.swift, Tests/.../CrossRepo/PathRefRecordTests.swift, Tests/.../CrossRepo/ScanCacheTests.swift, Tests/.../CrossRepo/ScanChangeTests.swift, Tests/.../Design/PortabilityTests.swift. 7/7 findings and 5/5 acceptance items are [x]. Not committed.
    - next: /review
  timestamp: 2026-10-19T16:49:48.088777+00:00
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
- [x] A new board has one ID event. An old board gets it on the next write, not on load.
- [x] A URI with the bare ULID and a URI with the git key resolve to the same board.
- [x] A merged log with two ID events: both resolve; the lowest is primary.
- [x] A remote change records the old git key, and a URI with the old key still resolves.
- [x] Tests use temporary git repos and temporary folders only.

## Review Findings (2026-10-19 11:40)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 28 file(s) reviewed, 6 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

- [x] `Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift:260` `swift/initialization` — The new BoardCopy init reads the board log from disk through BoardNames.read(fromRepoAt:key:). An init that is not throws has no way to report a failure, and callers expect init to return at once. The read belongs in an explicit load step that the scan calls, not in init. Keep init(directory:key:) to storing the values. Pass the names in from the scan, or give the scan a separate step that reads BoardNames for each copy, and call that step explicitly before the copy is used.
- [x] `Sources/FoundationModelsKanban/CrossRepo/ScanMarks.swift:127` `reuse/reuse` — The new board log path is derived inline as `EventLog(repositoryAt: directory).fileURL(for: .board)`. The same derivation already exists in `BoardCopy.hasBoardLog(at:)`, so the board log location is now computed in two places. If the layout of the board log changes, both places must change. Move the board log URL derivation into one shared helper (for example a static on `EventLog` or on `BoardCopy`) and call it from both `RepoMark.init?(ofRepoAt:)` and `BoardCopy.hasBoardLog(at:)`.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/BoardIDTests.swift:71` `reuse/reuse` — The test reads the board node with the same inline expression that the new helper `boardNode(inRepoAt:)` already wraps. The helper is declared in this file at line 88. The test does not call it, so the read logic exists twice. Replace line 71 with `let board = try Self.boardNode(inRepoAt: repo)`.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift:148` `reuse/reuse` — The line builds `BoardNames(key:board: nil)` from a key text. The same construction appears in other new lines of this change, so the pattern is repeated without a shared helper. Add one helper, or an existing initializer, that builds the names of a board from its key. Use it at every site. If `BoardNames` already has such an initializer, call it.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift:366` `reuse/reuse` — The line repeats the `BoardNames(key:board: nil)` construction. It is the third copy in this file. Use the same shared helper or initializer as the fix for line 148.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/ScanChangeTests.swift:51` `reuse/reuse` — The copy helper builds `BoardNames(key: key.description, board: nil)` by hand. The same construction appears in other files of this change. Use the same shared helper or initializer as the fix for BoardLocatorTests.swift:148.
- [x] `Tests/FoundationModelsKanbanTests/Design/PortabilityTests.swift:174` `swift/immutability` — The function linesHolding builds its result with a mutable var accumulator that is changed inside a for loop. A reader must read the whole loop to learn the final value of found. The loop only keeps the refs whose lines are not empty, so it is a filter-and-build step. Build the result as a value, for example: return Dictionary(uniqueKeysWithValues: try logTexts(inRepoAt: root).compactMap { ref, log in let lines = ...; return lines.isEmpty ? nil : (ref, lines) }). Use let, not var.
