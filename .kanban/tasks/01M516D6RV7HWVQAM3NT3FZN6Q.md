---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m51j87yfsz8bh58j0zw0fq0b
  text: |-
    Research:
    - `ChangeRound.changesOfOtherBoards(in:)` calls `ChangeBuilder.changesOfOtherBoards(ofBatch:)`. That builder gives each node of this board whose tracked fields changed (derived updates). This is how `blockedBy` and `ready` updates from a related board reach the feed.
    - `TaskObject.trackedFields` holds `assignees` as a list of actor ids. `updateActor` keeps the slug, so a rename does not change the id list. Thus a rename of a remote assignee gives no derived update now.
    - A delete removes the actor from `Task.assignees` (only live actors show), so the id list changes. The derived compare can give that update when the old board is loaded.
    - Plan: in `changesOfOtherBoards`, give the patched-node closure a set of the tasks of this board whose assignee is an actor that the transaction of the other board patched. Then the task gets an update in the change of that transaction, also with no field change (the same as a patched node). The subscriber can read `node { assignees { name } }` for the new value.
    - Test pattern: `CrossRepoActorTests.otherBoardChangeGivesActorOfTransactionBoard` (a watcher engine subscribes, a second engine writes the other board) and `CrossRepoTransferTests.makeAssignedTransfer`.
  timestamp: 2026-10-16T05:16:43.343316+00:00
- actor: claude-code
  id: 01m51jqz97pfx310vvw1y1krmm
  text: |-
    Implementation landed.
    - RED: the new rename test got no event (nil). The new delete test already got its event before the change (the derived compare saw `assignees` lose the id). My first expected text failed only on JSON key order (keys are sorted). I corrected the helper of the test, not the code.
    - GREEN: `ChangeBuilder.changesOfOtherBoards(ofBatch:)` now gives the patched-node closure the live tasks of this board whose assignee resolves (through `related.node(for:as: ActorNode.self)`) to an actor that the transaction of the other board patched. Those tasks get an update in the change of that transaction, also with no field change. A delete or undelete also gives the `assignees` field change. Tombstoned tasks are left out, the same as derived updates.
    - The resolve goes through the related boards, so an assignee URI that holds an old key of the board still matches the transaction board.
    - divergence.md Q21: added the change feed rule and the test file to the change list.
    - Full `swift test`: 1562 tests in 126 suites passed. Only the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-16T05:25:18.759848+00:00
- actor: claude-code
  id: 01m51jr5912mjwkhk01vjad12g
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/Observe/ChangeBuilder.swift, Tests/FoundationModelsKanbanTests/CrossRepo/RemoteAssigneeFeedTests.swift (new, 2 tests), divergence.md (Q21). `swift test`: 1562 tests in 126 suites passed, 0 failures, only the accepted "missing creator" warning.
    - next: /review. The task stays in doing.
  timestamp: 2026-10-16T05:25:24.897583+00:00
- actor: claude-code
  id: 01m51k12dv5gc0ebq769gqy882
  text: |-
    ### test — green
    - evidence: swift build: complete, only the allowed SwiftPM "missing creator" warning. swift test: 1562 tests in 126 suites passed, 0 failures, 0 skipped, no new warnings (one run, 56 s). IntegrationTests with scratch path integration-build: 3 tests in 3 suites passed, 0 failures, 0 skipped, only the allowed "missing creator" warning.
    - logs: build.log, test1.log, integ1.log in the scratchpad.
    - next: review.
  timestamp: 2026-10-16T05:30:16.891641+00:00
- actor: claude-code
  id: 01m51k1v1zaw5qyf370ygmcwtf
  text: |-
    ### commit — changed
    - evidence: local commit "feat(observe): send an update when the remote assignee of a moved task changes (^t3fzn6q)". Files: ChangeBuilder.swift, RemoteAssigneeFeedTests.swift (new), divergence.md, .kanban/tasks files. The sha is in the final report of this step.
    - next: review
  timestamp: 2026-10-16T05:30:42.111020+00:00
depends_on:
- 01M4ZEVB1RK8S6B8R6DX020T0G
position_column: doing
position_ordinal: '80'
title: Send a change feed event for a moved task when its remote assignee actor changes
---
## What
Found during ^x020t0g (divergence.md Q21, option A). A task that `moveTask(board:)` or `copyTask` moved to a different board keeps each assignee as the full `kanban://<old key>/actor/<slug>` URI. `Task.assignees` now reads that actor from the old board.

When the actor changes on the old board (rename, delete, undelete), the change feed of the target board does not send an event for the moved task. A subscriber on the target board thus keeps an old assignee value.

## Change
- When a related board applies a change to an actor, find each task on this board that has that actor URI as an assignee, and send an update for it in the change feed (the same way as a dependency on a related board does for `blockedBy` and `ready`).

## Acceptance Criteria
- [x] A rename of a remote assignee actor gives an update event for the moved task on the target board.
- [x] A delete of a remote assignee actor gives an update event, and `Task.assignees` leaves the actor out.

## Tests
- [x] Tests with two temporary git repos. Each repo gets a unique first commit. Never use the `.kanban/` of this repo.
- [x] `swift test` passes.