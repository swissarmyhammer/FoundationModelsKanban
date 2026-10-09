---
assignees:
- claude-code
depends_on:
- 01M4G9K2DV1V2ZVYNZBW3TAWFM
position_column: todo
position_ordinal: 8f80
title: 'Watcher batch: do not repeat derived updates in each Change'
---
## What
`Sources/FoundationModelsKanban/Observe/ChangeRound.swift:90-97` and `:114-125`: each transaction in one `LiveGraphChange` uses the same before and after views of the whole batch. Thus the derived updates of the full batch go into each `Change`. With T1 (patches task A) and T2 (patches task B) in one batch, the `Change` of T1 has an update of B, and the `Change` of T2 has an update of A. `changesOfOtherBoards` has the same problem. plan.md §6.7: values before and after come from the live graph before and after the batch.

- Give each patched node to the `Change` of the transaction that patched it.
- Give each derived update (a node that no transaction of the batch patched) to one `Change` only: the last transaction of the batch. Update plan.md §6.7 with this rule.

## Acceptance Criteria
- [ ] A batch with T1 and T2 gives two `Change` values. Each has only the node that it patched, and the derived updates are only in the `Change` of T2.
- [ ] No update is sent two times in one batch.

## Tests
- [ ] A test in `Tests/FoundationModelsKanbanTests/Observe/` that writes two transactions to the logs from outside and reads the subscription events.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.