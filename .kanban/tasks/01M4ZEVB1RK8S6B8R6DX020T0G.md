---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m515gy859gj9yk77chdpvte0
  text: |-
    Research (option A only, by the decision of the dispatcher; option B changes Q21 and only the user can decide it).
    - `TaskObject.assignees` (S/GraphQL/QueryResolvers.swift) reads only `.slot` edges. A transferred assignee is `.unresolved(.remote(uri))`.
    - `dependsOn` reads a remote task with `view.related.task(for:)` (S/CrossRepo/RelatedBoards.swift) and makes the object with the view of the found board. An actor needs the same read: `RelatedBoards.board(forKey:)` + `graph.slot(for: .actor(slug:))`.
    - The engine loads a related board only when a request names it. Today the requests come from `Graph.remoteDependencyKeys` through `RelatedBoards.dependencyRequests(of:inBoard:)` (callers: KanbanGraph.publish, KanbanGraph.relatedBoards, CommitSession.run, CommitSession.runReading). Thus the key of each remote assignee must also go into these requests, else the board of the actor is not loaded on the target board engine.
    - A board that cannot be read becomes `BoardResolution.unreadable` and gives the BOARD_UNREADABLE warning through `RelatedBoards.unreadableBoards`. A request for the assignee key gives this warning with no new code.
    - `@actor` (S/Filter/FilterEvaluator.swift `isAssigned`) matches only slot edges. A remote assignee edge must match by the slug of its URI, or by the slug of the name of the actor when the related board has it.
    - The change feed (ChangeBuilder `trackedFields`) uses `assignees` with `.ids(of:)`, so it gets the remote actor URI with no extra change.
  timestamp: 2026-10-16T01:34:16.837707+00:00
- actor: claude-code
  id: 01m516bn4pwvr02zw8115h64nq
  text: |-
    Implementation landed (option A only).
    - RED: 4 new tests in CrossRepoTransferTests (8 cases) failed for the expected cause: empty `assignees`, empty `@` result, no warning.
    - `TaskObject.assignees` now uses one generic `liveObject(at:)` (it replaces `liveTask(at:)`), so a remote actor URI reads the actor from its related board with the view of that board. `dependsOn` and `blockedBy` use the same helper.
    - `RelatedBoards.node(for:as:)` and `BoardSnapshot.node(for:as:)` are generic finds; `task(for:)` now calls them.
    - `RelatedBoards.dependencyRequests` / `loadedDependencyRequests` are renamed `crossBoardRequests` / `loadedCrossBoardRequests`, and they also ask for the key of each remote assignee (`Graph.remoteAssigneeKeys`). Without this, the target board engine does not load the old board. Callers updated: KanbanGraph.publish, KanbanGraph.relatedBoards, CommitSession.run, CommitSession.runReading.
    - `EdgeTarget.remoteBoardKey` removes a copy of the same `guard case .unresolved(.remote)` block in `remoteDependencyKeys` and `remoteAssigneeKeys`.
    - Filter: `@<slug>` matches a remote assignee by the slug or the name slug of the actor on its board; when no loaded board has the actor (board cannot be read), the slug in the URI decides. `@<actor URI of a different board>` matches the tasks with that assignee URI.
    - Forgiving: an unreadable old board gives the existing BOARD_UNREADABLE warning; the call continues; `assignees` leaves the actor out.
    - divergence.md: Q21 has the option A decision, and the Q21 change list in section 11 has one line.
    - Not in scope: a change of the actor on the old board does not make a change-feed event for the task on the target board (the feed reads the actor at each change of the task).
  timestamp: 2026-10-16T01:48:52.246700+00:00
- actor: claude-code
  id: 01m516bqkcjqdr70k48d874k6p
  text: |-
    ### implement — changed
    - evidence: 9 files — Sources/FoundationModelsKanban/GraphQL/QueryResolvers.swift, Sources/FoundationModelsKanban/CrossRepo/RelatedBoards.swift, Sources/FoundationModelsKanban/Filter/FilterEvaluator.swift, Sources/FoundationModelsKanban/Model/Node.swift, Sources/FoundationModelsKanban/Derived/ReadinessCache.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Sources/FoundationModelsKanban/Tool/Commit.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoTransferTests.swift, divergence.md. `swift test`: 1552 tests in 123 suites passed; only the accepted SwiftPM "missing creator" warning.
    - next: /review
  timestamp: 2026-10-16T01:48:54.764999+00:00
- actor: claude-code
  id: 01m516m98sgc696mkq2dgqj90r
  text: |-
    ### test — green
    - evidence: swift build — Build complete, 0 errors. swift test — 1552 tests in 123 suites passed, 0 failed, 0 skipped. IntegrationTests (--scratch-path integration-build) — 3 tests in 3 suites passed, 0 failed, 0 skipped.
    - warnings: only the allowed SwiftPM "missing creator for mutated node" warning for mlx-swift_Cmlx.bundle. No other warning.
    - code changes: none. One full run per target. No time limit failures.
    - next: review
  timestamp: 2026-10-16T01:53:35.001360+00:00
- actor: claude-code
  id: 01m516n2w0rv8k9nc34k1cq158
  text: |-
    ### commit — changed
    - evidence: one local commit with the cross-repo assignee read change. Files: QueryResolvers.swift, RelatedBoards.swift, FilterEvaluator.swift, Node.swift, ReadinessCache.swift, KanbanGraph.swift, Commit.swift, CrossRepoTransferTests.swift, divergence.md, and the .kanban/tasks files (new task ^t3fzn6q, stuck note on ^yf3bpss). The sha is in the final report of the commit step. No push.
    - next: review
  timestamp: 2026-10-16T01:54:01.216067+00:00
position_column: doing
position_ordinal: '80'
title: Show an assignee that is a full URI of a different board in Task.assignees
---
## What
A move or a copy of a task to a different board (^7jyymre, divergence.md Q21) stores each assignee of the old board as the full `kanban://<old key>/actor/<slug>` URI. This is the decided rule of the card.

`Task.assignees` (S/GraphQL/QueryResolvers.swift, `view.liveObjects(at: state.assignees.compactMap(\.resolvedSlot))`) reads only edges that resolve to a slot of the same board. Thus the moved task shows no assignee on the target board, and the `@actor` filter does not find it.

## Decide and do
- Option A: `Task.assignees` reads a remote actor URI from the related board (as `dependsOn` does), and the `@actor` filter matches the slug of a remote actor.
- Option B: the transfer makes each missing actor on the target board (as E6 does for tags) and stores a local ref. This changes the decided rule of Q21, so the user must decide.

Decision for this card: option A only (recorded in divergence.md Q21). Option B is not done.

## Acceptance Criteria
- [x] After `moveTask(board:)` of a task with an assignee, `Task.assignees` of the new task gives the actor.
- [x] `@<slug>` finds the moved task.

## Tests
- [x] A test in Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoTransferTests.swift with two temporary git repos.
- [x] `swift test` passes.