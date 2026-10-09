---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4h21abbge0qzff2qnnk65x9
  text: |-
    Research:
    - ChangeRound.changes(of:atPath:) makes one ChangeBuilder for each LiveGraphChange (one apply or one commit) and calls builder.change(of:) for each txn. ChangeBuilder.change adds the updates of the patched nodes of the txn, and then each other node whose fields changed between the before and after views. Thus each txn of a batch gets the updates of the nodes that the other txns patched, and all derived updates.
    - changesOfOtherBoards uses one builder for the whole round, with the views before and after the operation, so each txn of each changed board gets all derived updates.
    - ChangeFilter drops a Change with no update, so a Change with no update is not sent.
    - History.swift and UndoMutations.swift call change(of:markingUndone:) with one txn. That behavior stays.
    - Plan: ChangeBuilder gets changes(ofBatch:) and changesOfOtherBoards(ofBatch:) that take the transactions of one batch. Each patched node goes to one Change; derived updates go to the last transaction (in txn order) only. ChangeRound uses them; changeOfOtherBoard(of:inBoard:markingUndone:) is then dead code and goes away.
    - Open case: a node that two transactions of one batch patch. Choice: the update goes to the last transaction that patched it, so that no update is sent two times (the values are the values after the batch).
    - Test approach: an engine test in SubscriptionTests (two log lines from outside; the expected events are the same if FSEvents groups the two writes or not), and a ChangeBuilder test with a batch of two transactions that is deterministic.
  timestamp: 2026-10-09T19:25:28.299769+00:00
- actor: claude-code
  id: 01m4h2ksk3n5nvnj4jhawxsms7
  text: |-
    Discoveries during implementation:
    - Outside writes in a test must use a ULID source that sorts after the engine ids (GitGraphFixture.secondEngineIDs). With the fixture ids (step 0), the done move sorted before the addTask event of the task, and replay folded the task back to todo.
    - Under full-suite load, FSEvents gave the two outside writes in two batches in reverse order (the done move first). Each Change had the correct updates; only the order of the two events changed. The engine test now compares the sorted events with exact equality. The order of Changes across two watcher batches is not in the scope of this task.
    - The ChangeBuilder test applies the batch with session.apply(watchedPaths: [log.directory]), so the two transactions are always one batch. This test is deterministic.
    - changeOfOtherBoard(of:inBoard:markingUndone:) is removed (no caller after the change). ChangeBuilder now has changes(ofBatch:) and changesOfOtherBoards(ofBatch:), and BatchTransaction.grouping(_:inBoard:markingUndoneBy:).
  timestamp: 2026-10-09T19:35:33.731466+00:00
- actor: claude-code
  id: 01m4h2n1we8yh95wzn73pkzx61
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/Observe/ChangeBuilder.swift, Sources/FoundationModelsKanban/Observe/ChangeRound.swift, Tests/FoundationModelsKanbanTests/Observe/ChangeBuilderTests.swift, Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift, plan.md. `swift test`: 1097 tests in 80 suites passed; the only build warning is the accepted SwiftPM "missing creator for mutated node".
    - rule choice: a node that two or more transactions of one batch patch has its update only in the Change of the last of them (closest to plan.md §6.7: the values are the values after the batch, and no update is sent two times). Written in plan.md §6.7.
    - next: /review
  timestamp: 2026-10-09T19:36:14.990664+00:00
- actor: claude-code
  id: 01m4h2x5qx8c53y8tmr2em1p24
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 5 files
    - test: green — swift test x3, 1097 tests in 80 suites passed each run
    - commit: e955ffa
    - review: findings — Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift:269
  timestamp: 2026-10-09T19:40:41.085643+00:00
- actor: claude-code
  id: 01m4h3069rga1kjv95jckcpzbp
  text: |-
    ### implement — changed
    - evidence: 2 files — Tests/FoundationModelsKanbanTests/Events/ReplayTests.swift (movePatch now is `movePatch(of task: LocalRef? = nil, to column: LocalRef)`, with taskRef() when no task is given), Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift (donePatch keeps the done-column lookup and calls `ReplayTests.movePatch(of: task, to: .column(slug: done))`). The existing callers `movePatch(to:)` in ReplayTests did not change. `swift test`: 1097 tests in 80 suites passed; the only build warning is the accepted SwiftPM "missing creator for mutated node".
    - finding `SubscriptionTests.swift:269` `reuse/reuse` is checked.
    - next: /review
  timestamp: 2026-10-09T19:42:19.960422+00:00
- actor: claude-code
  id: 01m4h34bv8nrfq8vp1hrk278tc
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 2 files
    - test: green — swift test, 1097 tests in 80 suites passed
    - commit: b1fcb14
    - review: clean — 0 findings
  timestamp: 2026-10-09T19:44:36.712392+00:00
depends_on:
- 01M4G9K2DV1V2ZVYNZBW3TAWFM
position_column: done
position_ordinal: d480
title: 'Watcher batch: do not repeat derived updates in each Change'
---
## What
`Sources/FoundationModelsKanban/Observe/ChangeRound.swift:90-97` and `:114-125`: each transaction in one `LiveGraphChange` uses the same before and after views of the whole batch. Thus the derived updates of the full batch go into each `Change`. With T1 (patches task A) and T2 (patches task B) in one batch, the `Change` of T1 has an update of B, and the `Change` of T2 has an update of A. `changesOfOtherBoards` has the same problem. plan.md §6.7: values before and after come from the live graph before and after the batch.

- Give each patched node to the `Change` of the transaction that patched it.
- Give each derived update (a node that no transaction of the batch patched) to one `Change` only: the last transaction of the batch. Update plan.md §6.7 with this rule.

## Acceptance Criteria
- [x] A batch with T1 and T2 gives two `Change` values. Each has only the node that it patched, and the derived updates are only in the `Change` of T2.
- [x] No update is sent two times in one batch.

## Tests
- [x] A test in `Tests/FoundationModelsKanbanTests/Observe/` that writes two transactions to the logs from outside and reads the subscription events.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-09 14:38)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift:269` `reuse/reuse` — The new donePatch(of:) builds a column-move PatchInput that ReplayTests.movePatch already builds. It is a near-match that was not extended. movePatch(to:) only hard-codes the fixture task (taskRef()), so the right move was to add an `of` task parameter to movePatch and have donePatch call it with the done column, instead of writing a parallel copy of the same PatchInput(node:set: [column: .ref(.local(...))]) construction. Generalize ReplayTests.movePatch to take the node: `static func movePatch(of task: LocalRef? = nil, to column: LocalRef)`, defaulting to taskRef(). Then donePatch becomes a one-line call: `movePatch(of: task, to: .column(slug: done))`. Keep the done-column lookup in donePatch.
