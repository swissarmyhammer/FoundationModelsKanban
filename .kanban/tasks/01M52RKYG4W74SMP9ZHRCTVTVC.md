---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5an5pyb4kgntab0p95n4pna
  text: |-
    Research done (implement step).

    - Read time already resolves an old name: `BoardIndex.resolution(ofName:)` reads `BoardCopy.names` (board IDs, old names, and the recorded `gitKey` when it is not the current key). `RelatedBoards.board(forKey:)` thus gives the board that has the old name now, so readiness and reads of a `dependsOn` URI with an old key already work. `board(id: <old key>)` also gives the board now (BoardIDTests.remoteChangeRecordsOldKey). What is missing: the warning, `checkLinks`, and tests.
    - Plan for the warning: `RelatedBoards` keeps `resolutions` by the ref text. A new read lists each resolved ref whose board key is an old name of the board it resolved to (`BoardNames.kind(of:) == .oldName`). `KanbanGraph.runCall` adds one `OLD_BOARD_NAME` warning for each, next to the `BOARD_ID_SHARED` place warnings.
    - Plan for `checkLinks(boards:)`: a read-only `Query` field. No `boards` reads the current board. It lists one `LinkCheck` for each stored link: `dependsOn` edges, remote assignee URIs, body task URLs (`DependencyMarkers`) of live tasks, and the `Moved to <URI>` line of a tombstoned task. The status is an enum `OK`, `OLD_NAME`, `DANGLING`, `MISSING_NODE`. A key that the run did not resolve yet records a `BoardRequest.board`, and the call runs again (the same pattern as `board(id:)`).
    - Decision to note: a link to a board that cannot be read (`BOARD_UNREADABLE`) gets its class from the name only (`OK` or `OLD_NAME`), because the node cannot be checked. The `BOARD_UNREADABLE` warning of the response names that board.
    - The public schema already has GraphQL enums (`NodeType`, `UpdateKind`) through `SchemaBuilder.enumType`, so the new enums use the same helper.
  timestamp: 2026-10-19T18:00:56.011657+00:00
- actor: claude-code
  id: 01m5anwaw5pkgs6a62pcj4x76s
  text: |-
    Implementation landed (not committed).

    - `Query.checkLinks(boards: [String!])` reads only. No value or an empty list checks the current board. Aliases: board, ids, id, keys, key, repos, repo, paths, path; one string becomes a list of one item. Output type `LinkCheck { board node field target status currentName }`, enums `LinkField` (DEPENDS_ON, ASSIGNEE, BODY, TOMBSTONE) and `LinkStatus` (OK, OLD_NAME, DANGLING, MISSING_NODE).
    - Live task: dependsOn edges (local and remote), remote assignee URIs, body task URLs. Tombstone: only its `Moved to <URI>` line. A missing node wins over an old name.
    - Read time: each resolved board ref of a run whose key is an old name of the board it resolved to gives one `OLD_BOARD_NAME` warning (`RelatedBoards.oldBoardNames`, added in `KanbanGraph.runCall`). Thus each call on a board with an old-name link warns until the link changes. The next task (^99e0h99, repairLinks) removes the cause.
    - Shared helpers: `MovedTaskLine` (the writer in TaskTransferMutations and the reader use one prefix), `Graph.boardNames(currentKey:)`, `Graph.uri(of:inBoard:)`, `EdgeTarget.remoteURI`, `SchemaBuilder.enumType` is now internal.
    - Discovery: Swift reads "\r\n" as one Character, so `split(separator: "\n")` does not split a CRLF body. The moved line parse uses `split(whereSeparator: \.isNewline)`; a unit test covers it (it failed first).
    - Decision to confirm by a person: a link to a board that cannot be read gets its class from the name only (OK or OLD_NAME), because its node cannot be checked; BOARD_UNREADABLE names the board. divergence.md does not say this.
  timestamp: 2026-10-19T18:13:17.317289+00:00
- actor: claude-code
  id: 01m5anwgzjdypnv6xfcd2h86yg
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` 0 warnings; `swift test` 1647 tests in 136 suites passed. New: Sources/FoundationModelsKanban/CrossRepo/LinkCheck.swift, CrossRepo/OldBoardName.swift, GraphQL/CheckLinksField.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CheckLinksTests.swift (11 tests). Changed: CrossRepo/RelatedBoards.swift, GraphQL/Schema.swift, GraphQL/SchemaDescription.swift, GraphQL/FieldAliases.swift, GraphQL/TaskTransferMutations.swift, Tool/KanbanGraph.swift, Tool/KanbanTool.swift, Tool/SessionNames.swift, Identity/BoardNames.swift, Identity/RefResolver.swift, Derived/ReadinessCache.swift, Model/Node.swift, Observe/Change.swift, Tests/.../CrossRepo/BoardIDTests.swift.
    - next: /review
  timestamp: 2026-10-19T18:13:23.570481+00:00
depends_on:
- 01M52RKMDD8RJ7TNTQVE65466D
position_column: doing
position_ordinal: '80'
title: Add checkLinks, and resolve an old board name at read time with a warning
---
## What
divergence.md M9 "checkLinks and repairLinks". A user must find links that use an old board name, and links that no board can resolve.

## Do
- `checkLinks(boards:)` (read only) reads the stored refs of the named boards: `dependsOn`, assignee URIs, task URLs in bodies, tombstone lines. Each link gets a class: **ok**, **old name** (with the current name), **dangling**, or **missing node**.
- An old-name link works at read time (readiness and reads use the board that has the old name now). The response gives a warning for it.
- `board(id:)` with an old name gives the board that has it now, with its current names.

## Acceptance Criteria
- [x] Each of the four classes has a test.
- [x] A task that depends on a task through an old board name is ready when that task is done, and the response warns.
- [x] `board(id:)` with an old name gives the current board.
- [x] Tests use temporary folders and temporary git repos only.