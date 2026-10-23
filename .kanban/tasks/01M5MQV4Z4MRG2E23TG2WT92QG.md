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
- actor: claude-code
  id: 01m5mw7abvsmbytm54986ddgaj
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` gave 4 findings (4 confirmed, 11 refuted), all `test-integrity/no-test-cheating`: Tests/FoundationModelsKanbanTests/GraphQL/RustFieldTests.swift:124, Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift:480, Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift:599, Tests/FoundationModelsKanbanTests/Mutations/TagMutationTests.swift:461.
    - acceptance criteria: all three are met by the code and by T/Undo/ResponseTransactionTests.swift (writeGivesTransaction for addTask, updateTask, moveTask, deleteTask; undoOfResponseTransactionReversesCall; noWriteGivesNoTransaction for staleUpdate, missingTask, noOpTag, dryRun, query). divergence.md §19 records the form `extensions.txn`. No criterion finding.
    - next: replace each `hasSuffix` assertion with a full `==` comparison of the response with the transaction removed, then /review again.
  timestamp: 2026-10-23T17:16:33.019591+00:00
- actor: claude-code
  id: 01m5mw7thwaa0f9tckphq9a9zy
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 24 files
    - test: green — swift test, 1776 passed in 148 suites
    - commit: 579c3a0
    - review: findings — RustFieldTests.swift:124, ColumnActorTests.swift:480, ColumnActorTests.swift:599, TagMutationTests.swift:461
  timestamp: 2026-10-23T17:16:49.596608+00:00
- actor: claude-code
  id: 01m5mwche195s8j5k6nm7k37th
  text: |-
    Picked up again for the 4 review findings (test-integrity/no-test-cheating).
    - Discovery: each hasSuffix assertion existed before 579c3a0. The commit only put `withoutTransaction` around it. But the cause is the same in each changed test file, so all of them change to a full `==` compare.
    - The response JSON has sorted keys at each level, also the mutation field keys in `data`. So a full expected text is easy to write from the fields of the document.
    - ColumnActorTests.swift: 5 sites changed (undeleteColumn, updateActor, updateActor null color, deleteActor, and the board actors query that used `contains`). New documented constant `addedAliceJSON`. `swift test --filter ColumnActorTests`: 28 tests passed.
    - The other files (RustFieldTests, AddUpdateTaskTests, CommentTests, StaleWriteTests, TagMutationTests, TaskOperationTests) are in progress.
  timestamp: 2026-10-23T17:19:24.097763+00:00
- actor: claude-code
  id: 01m5mwtj4p5fm7qfzkf7m3sz38
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` gives only the accepted "missing creator" warning. `swift test` passed 1776 tests in 148 suites, with no issue. 7 test files changed: T/GraphQL/RustFieldTests.swift (2 sites), T/Mutations/AddUpdateTaskTests.swift (10 sites, with the `timeInputIsRefused` error response now a full `==`; its error column is calculated from the document), T/Mutations/ColumnActorTests.swift (5), T/Mutations/CommentTests.swift (1), T/Mutations/StaleWriteTests.swift (1), T/Mutations/TagMutationTests.swift (8), T/Mutations/TaskOperationTests.swift (10, with the `contains` sites for assignTask, unassignTask and untagTask). Each `hasSuffix`/`contains` on a GraphQL response in these files is now a full `==` compare (with `withoutTransaction` when the call writes). New fragment constants have doc comments.
    - The 4 findings are checked. The 3 acceptance criteria are checked: T/Undo/ResponseTransactionTests.swift proves them, and it passes in the full run.
    - Not changed: `contains`/`hasPrefix` that 579c3a0 did not add in other files (NameRewriteTests message hasPrefix, GraphQLEngineTests:172, CommitTests:433). A task id that the engine makes is read from the response in AddUpdateTaskTests; the rest of each such response is compared in full.
    - next: /review
  timestamp: 2026-10-23T17:27:03.574171+00:00
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

- [x] The result of each mutation that writes gives the `txn`.
- [x] `undoChange(input: {txn: <that txn>})` reverses that call.
- [x] A refused call gives no `txn`.

## Tests

- Unit tests in `T/` for each criterion, with at least `addTask`, `updateTask`, `moveTask` and `deleteTask`.
- `swift test` passes with no new warnings. #kanbanviewkit

## Review Findings (2026-10-23 12:11)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 20 file(s) reviewed, 4 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file
> - `divergence.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/GraphQL/RustFieldTests.swift:124` `test-integrity/no-test-cheating` — The changed assertion for updateActor now uses hasSuffix on the response with the transaction removed, instead of an exact equality. The check no longer fixes the start of the response, so the data envelope and any keys before "first" are not checked. A response with extra or wrong leading fields would still pass. This loosens the assertion, which the rule treats as weakened coverage. Compare the full response for equality with the transaction removed, as the other changed lines do: `#expect(KanbanGraphTests.withoutTransaction(response) == #"{"data":{"first":...,"second":...}}"#)`. If the suffix form was chosen for a reason, such as an ordering issue, state that reason in a comment and assert the full prefix separately.
- [x] `Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift:480` `test-integrity/no-test-cheating` — The undeleteColumn test now checks only the end of the response with hasSuffix, not the whole response. A wrong leading field or a wrong response shape would still pass, so the assertion is weaker than an exact comparison. Compare the full response with `==`, as the other tests in this change do, and include the leading `{"data":...}` part.
- [x] `Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift:599` `test-integrity/no-test-cheating` — The updateActor test checks only the suffix of the response. The data prefix is not compared, so the assertion is weaker than an exact match. Use `==` against the full expected response `{"data":{"updateActor":...}}`.
- [x] `Tests/FoundationModelsKanbanTests/Mutations/TagMutationTests.swift:461` `test-integrity/no-test-cheating` — The updateTag rename test checks only the suffix of the response. The data prefix is not compared. Compare the full response with `==`.
