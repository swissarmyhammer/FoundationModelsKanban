---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5mtwty8dkhvr2tpg6w3xq85
  text: |-
    Research done.
    - FoundationModelsExtras already has the hook: `GraphQLRunContext.responseExtensions()` (GraphQLRun.swift). `API.respond` puts its keys in `extensions` beside `warnings`. Its doc names "`txn` of an endpoint with transactions". The kanban `KanbanContext` uses the default (no key) today. So the form is `extensions.txn`, with no schema change (KANBAN-6 of the TestudoApp design says the same).
    - The txn is known during the run: `CommitSession.runReading` makes a new `EventStamp` (with its `txn`) for each run, and the commit writes the events of the run that made the response. A run that finds a changed log runs again with a new stamp and a new response, so the response of the run that commits has the txn that the commit writes.
    - A run writes when `work.hasChanges || relatedWork.contains(where: \.hasPatches)` (CommitSession.run). A refused field discards its patches, a dryRun keeps none, and a no-op patch is not kept, so these give no txn.
    - Plan: `BoardStore` gives the txn of the run when the run keeps a patch in a board; `KanbanContext.responseExtensions()` gives `["txn": <ULID text>]` from it. Record the decision in divergence.md as a new numbered section.
  timestamp: 2026-10-23T16:53:20.968579+00:00
- actor: claude-code
  id: 01m5mvj6s5d3jeamwtvph9gj2y
  text: |-
    Implementation landed (not yet full-suite green).
    - S/Tool/Commit.swift: `WorkingCopy.writes(along:)` is the one rule "the run writes" (kept patch or merged event, in this board or a related board). `CommitSession.run` uses it in place of the inline condition.
    - S/GraphQL/Schema.swift: `BoardStore.writtenTransaction` gives `work.stamp.txn` when the run writes, else nil. `KanbanContext.responseExtensions()` gives `["txn": <ULID text>]` from it (the hook of FoundationModelsExtras `GraphQLRunContext`). Key name: `KanbanContext.transactionKey`.
    - S/Tool/KanbanTool.swift: the tool description tells the agent about extensions.txn.
    - T/Undo/ResponseTransactionTests.swift: new suite. RED before the change (9 issues, no extensions object), GREEN after.
    - Discovery: about 100 existing assertions compare the full response text of a call that writes, so they now fail on the new `extensions` key. Fix: the test helper `KanbanGraphTests.withoutTransaction(_:)` removes only `extensions.txn` (text-based, from the last top-level `"extensions":{`, so `Change.txn` in data stays). `UnreadableRelatedBoardTests.hasNoWarning` now reads `extensions.warnings`, not the whole `extensions` object.
    - README: the addTask example now shows `extensions.txn` with a fixed example ULID; ReadmeExamplesTests puts that ULID in place of the real one before it compares.
    - divergence.md: new section 19.
  timestamp: 2026-10-23T17:05:01.221802+00:00
- actor: claude-code
  id: 01m5mvvqmhs5x8hm5tp2t91f2h
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` gives only the accepted "missing creator" warning; `swift test` passed 1776 tests in 148 suites. 24 files: S/GraphQL/Schema.swift, S/Tool/Commit.swift, S/Tool/KanbanTool.swift, README.md, divergence.md (§19), T/Undo/ResponseTransactionTests.swift (new), T/Tool/KanbanGraphTests.swift (helper `withoutTransaction(_:)` + its test), T/Tool/KanbanToolTests.swift, T/ReadmeExamplesTests.swift, T/CrossRepo/UnreadableRelatedBoardTests.swift, T/CrossRepo/DependencyTargetWarningTests.swift, and the assertions wrapped in `withoutTransaction` in T/Mutations/{AddUpdateTask,BoardMutation,ColumnActor,Comment,StaleWrite,TagMutation,TaskOperation}Tests.swift, T/GraphQL/{NameRewrite,RustField}Tests.swift, T/Tool/CommitTests.swift, T/GraphQLEngineTests.swift.
    - Acceptance: each writing mutation gives `extensions.txn` (addTask, updateTask, moveTask, deleteTask tested); `undoChange(input: {txn})` with it reverses the call (board read equal to before; `Change.undoes` is the txn); a refused call (STALE_WRITE, NOT_FOUND), a no-op, a dryRun, and a query give no txn; one document with three fields gives one txn for all its events.
    - Note: TDD order on the tool description: I wrote its test first, then removed the sentence again to watch RED, then put it back for GREEN.
    - next: /review
  timestamp: 2026-10-23T17:10:13.393784+00:00
position_column: doing
position_ordinal: '80'
title: Give the txn of the call in each mutation result
---
## What

KanbanViewKit sends `undoChange(txn:)` and `redoChange(txn:)` for one transaction of the user (its plan §3.4, §6.4). Today `undoChange` and `redoChange` give a `Change` with its `txn`, but an ordinary mutation (for example `addTask`, `updateTask`, `moveTask`) gives only the node. The client then must read `Board.history` to find the `txn`.

- Make the `txn` of the call available in the result of each mutation, with no second read.
- Choose one form, and record it in `divergence.md`. Options:
  - a response `extensions` key (`extensions.txn`), with no schema change; or
  - a `txn` field on each mutation result type.
- A call that writes nothing (a refusal, a `dryRun`, a no-op) gives no `txn`.
- A document with many mutation fields is one transaction: each field gives the same `txn`.

## Acceptance criteria

- [ ] The result of each mutation that writes gives the `txn`.
- [ ] `undoChange(input: {txn: <that txn>})` reverses that call.
- [ ] A refused call gives no `txn`.

## Tests

- Unit tests in `T/` for each criterion, with at least `addTask`, `updateTask`, `moveTask` and `deleteTask`.
- `swift test` passes with no new warnings. #kanbanviewkit