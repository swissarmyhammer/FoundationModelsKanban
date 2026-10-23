---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5ms92yhzwqmr061vvw8xxhh
  text: |-
    Research done. Findings:
    - The card names `S/GraphQL/Errors.swift`; the file is `Sources/FoundationModelsKanban/GraphQL/Errors.swift`. A `KanbanError` gives only a code and a message, so the current version goes in the message.
    - Replay (`Events/Replay.swift`, `NodeFold`) folds the events of a node in event-id order. The id of the last event is the version. Plan: add `version: ULID?` to `NodeFields` (nil only for the in-memory empty board of `Graph.withBoard`), and a `version` field on the `Node` interface, so all six node types get it at no extra cost. An abort record removes the events of its transaction before the fold, so the version stays correct after a rollback.
    - The working copy of a commit folds each new event again (`WorkingCopy.apply`), and becomes the live graph, so the result of `updateTask` shows the new version.
    - `updateTask` runs its body in `KanbanContext.changeTask` under the commit retry loop. A throw in the body writes nothing: no event, so no undo entry (the undo log reads the events).
    - Forgiving input: compare `ifVersion` trimmed and in uppercase (the same as `UndoLog.target` for `txn`). Add input aliases for `ifVersion` in `FieldAliases.swift`.
    - The SDL golden file `Tests/Fixtures/kanban.graphql` is written again with `GRAPHQL_GOLDEN_RECORD=1`.
    - `KanbanErrorTests.codes` lists one error per code; the test "sixteen different codes" must change to seventeen.
  timestamp: 2026-10-23T16:25:05.233247+00:00
- actor: claude-code
  id: 01m5mt1wy4mf31fnm68800634r
  text: |-
    Implementation landed (not committed).
    - `NodeFields.version: ULID?` comes from the fold in `Events/Replay.swift` (`NodeFold` records the id of each event). `Node.version: ID` is on the `Node` interface, so all six node types have it. It is null only for the in-memory empty board.
    - `UpdateTaskInput.ifVersion: ID`. `Graph.checkVersion(of:against:namedBy:)` in `GraphQL/TaskMutations.swift` runs in the `updateTask` body, just after the task ref resolves. It trims the text and compares it in uppercase. A text that is not a ULID gives STALE_WRITE.
    - `KanbanError.staleWrite(task:givenVersion:currentVersion:)` has the code `STALE_WRITE`. The message gives the current version.
    - Input aliases: version, expectedVersion, baseVersion, ifMatch, etag. moveTask has no ifVersion.
    - Descriptions: Node.version, UpdateTaskInput.ifVersion, Mutation.updateTask, and the tool description. The golden SDL was written again with GRAPHQL_GOLDEN_RECORD=1. The decision is in divergence.md §18.
    Discovery: `ColumnActorTests.failure(...)` runs `PublicSchema().execute` with no name rewrite, so an alias test must go through `KanbanGraph.execute` (`respondWritingNothing`). The alias test passed at first, so I removed the alias entry for a short time to see it fail, and then put the entry back.
  timestamp: 2026-10-23T16:38:38.276737+00:00
- actor: claude-code
  id: 01m5mt203kv2gg345hvvhcnr70
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` clean (only the accepted SwiftPM "missing creator" warning); `swift test` 1770 tests in 147 suites passed. 17 files: Sources/FoundationModelsKanban/{Events/Replay.swift, Model/Node.swift, GraphQL/Errors.swift, GraphQL/FieldAliases.swift, GraphQL/QueryResolvers.swift, GraphQL/Schema.swift, GraphQL/SchemaDescription.swift, GraphQL/SchemaDescription+Mutations.swift, GraphQL/SchemaDescription+Types.swift, GraphQL/TaskMutations.swift, Tool/KanbanTool.swift}, Tests/FoundationModelsKanbanTests/Mutations/StaleWriteTests.swift (new), Tests/FoundationModelsKanbanTests/GraphQL/KanbanErrorTests.swift, Tests/Fixtures/kanban.graphql, divergence.md, and the kanban card files.
    - next: /review
  timestamp: 2026-10-23T16:38:41.523991+00:00
- actor: claude-code
  id: 01m5mtbzcytcsrtz277mc3wfrk
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (local backend), 1 finding (1 confirmed, 0 refuted) — Tests/FoundationModelsKanbanTests/Mutations/StaleWriteTests.swift:50 (completeness/invariant-propagation)
    - next: implement the open item in the "Review Findings (2026-10-23 11:40)" section; the task stays in review.
  timestamp: 2026-10-23T16:44:08.478381+00:00
- actor: claude-code
  id: 01m5mtc9qpvzepmd54drbx0km5
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 15 files
    - test: green — swift test, 1770 passed in 147 suites
    - commit: dd65859
    - review: findings — Tests/FoundationModelsKanbanTests/Mutations/StaleWriteTests.swift:50
  timestamp: 2026-10-23T16:44:19.062243+00:00
- actor: claude-code
  id: 01m5mtke2nrc6kzt6v47jcfjjm
  text: |-
    Finding fixed: `StaleWriteTests.eachNodeHasVersion` now covers all six node types.
    - The test adds a comment with a new author (`actor: "Bob Smith"`, which makes the actor) and a tag on the fixture board. Then it reads each node file in the repo (`BoardMutationTests.storedRefs`), and it checks that the node types are all of `PatchNodeType.allCases`. One query reads `version` of each node through `node(id:)` with aliases `node0`, `node1`, and so on. Each version must equal the id of the last event of the node.
    - The test reads all node files of the repo, not a fixed list. Thus a node that the setup writes, for example the session actor, is also checked.
    - RED check: for a short time I made `GraphNodeObject.version` give nil for comments. The test failed on the comment version. Then I removed that change; Sources has no diff.
    - No production code changed in this pass.
  timestamp: 2026-10-23T16:48:12.885750+00:00
- actor: claude-code
  id: 01m5mtkfy4yr3qdwd0k46x4vpt
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/Mutations/StaleWriteTests.swift (and the card files). `swift build --build-tests` clean (only the accepted SwiftPM "missing creator" warning); `swift test` 1770 tests in 147 suites passed. Finding "StaleWriteTests.swift:50 completeness/invariant-propagation" is now `- [x]`.
    - next: /review
  timestamp: 2026-10-23T16:48:14.788848+00:00
- actor: claude-code
  id: 01m5mtqyjkcwq3ap053jd4ghwn
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (c68d337) — 0 findings, 0 confirmed, 0 refuted; 7 validators attempted, 0 failed; 1 file reviewed (Tests/FoundationModelsKanbanTests/Mutations/StaleWriteTests.swift). All prior findings (2026-10-23 11:40) are checked.
    - next: none. The task moved to done.
  timestamp: 2026-10-23T16:50:40.851136+00:00
- actor: claude-code
  id: 01m5mtr99pz74kmbh4q0ccfrye
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 1 file (StaleWriteTests.swift)
    - test: green — swift test, 1770 passed in 147 suites
    - commit: c68d337
    - review: clean — 0 findings; prior finding checked
  timestamp: 2026-10-23T16:50:51.830683+00:00
position_column: done
position_ordinal: ffb480
title: Add ifVersion to updateTask and refuse a stale write with STALE_WRITE
---
## What

KanbanViewKit edits the title and the description of a task in place (its plan §3.4). Two editors can edit the same task. The second write must not overwrite the first write with no warning.

- Add a `version` field to `Task` (and to the other node types if it is cheap). The version changes on each write of the node. Use a value that the event log already holds, for example the event id of the last event of the node. Do not add a stored counter.
- Add an optional `ifVersion` to the input of `updateTask`. When it is set and it is not the current version of the task, refuse the call with the new error code `STALE_WRITE`, and write nothing. The error gives the current version.
- With no `ifVersion`, the call works as today.
- `moveTask` takes no `ifVersion`: a move is never refused (KanbanViewKit D100).
- Add the code to `S/GraphQL/Errors.swift` and describe it in the schema description and the tool description.
- Record the decision in `divergence.md`.

## Acceptance criteria

- [x] `Task.version` is in the schema, and it changes after each write of the task.
- [x] `updateTask(input: {id, title, ifVersion: <current>})` writes.
- [x] `updateTask(input: {id, title, ifVersion: <old>})` gives `STALE_WRITE` with the current version, and writes nothing (no event, no undo entry).
- [x] With no `ifVersion`, the behavior does not change.

## Tests

- Unit tests in `T/` for each criterion.
- `swift test` passes with no new warnings. #kanbanviewkit

## Review Findings (2026-10-23 11:40)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 13 file(s) reviewed, 4 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `Tests/Fixtures/kanban.graphql` — no validator matches this file
> - `divergence.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/Mutations/StaleWriteTests.swift:50` `completeness/invariant-propagation` — The test is named 'Each node type gives the id of its last event as its version', but the body checks only the board and the column. The version is stored in the shared NodeFields type for all six node types. The task, actor, tag, comment, and other node types are not checked, so a fault that affects only one of them would pass this test. Extend the query to read `version` on a task, an actor, a tag, and a comment, and assert each one equals the id of its last event. Or rename the test to say it covers only the board and the column.
