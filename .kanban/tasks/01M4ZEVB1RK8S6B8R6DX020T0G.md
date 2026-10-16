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
- actor: claude-code
  id: 01m5177nj9n9gr6m0kvxngt9m2
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (9494ce4). The engine found 4 confirmed findings and refuted 2. Findings: Sources/FoundationModelsKanban/CrossRepo/RelatedBoards.swift:528 (duplication/duplication), Sources/FoundationModelsKanban/CrossRepo/RelatedBoards.swift:528 (reuse/reuse), Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoTransferTests.swift:184 (reuse/reuse), Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoTransferTests.swift:227 (reuse/reuse).
    - next: Use one shared Graph helper for remoteAssigneeKeys and remoteDependencyKeys. Use one test helper for the actor and assigned task setup. Use one helper for the list of ids under a key. Then run the tests and review again. The task stays in review.
  timestamp: 2026-10-16T02:04:10.185487+00:00
- actor: claude-code
  id: 01m51788nytxjqtyyksh6cfkvy
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — QueryResolvers, RelatedBoards, FilterEvaluator, Node, ReadinessCache, KanbanGraph, Commit, CrossRepoTransferTests, divergence.md Q21 (option A)
    - test: green — swift test, 1552 passed; IntegrationTests 3 passed
    - commit: 9494ce4
    - review: findings — Sources/FoundationModelsKanban/CrossRepo/RelatedBoards.swift:528 (x2), Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoTransferTests.swift:184, :227
  timestamp: 2026-10-16T02:04:29.758239+00:00
- actor: claude-code
  id: 01m517pgrzz50f5p1q527eex7g
  text: |-
    Review findings fixed (4 of 4).
    - RelatedBoards.swift:528 (duplication and reuse): new `Graph.remoteBoardKeys(of edges: (TaskNode) -> [EdgeTarget]) -> Set<String>` in the Graph extension of RelatedBoards.swift. `remoteAssigneeKeys` calls it with `\.assignees`. `remoteDependencyKeys(inBoard:)` (ReadinessCache.swift) calls it with `{ task in dependencies(of: task, inBoard: key) }`. The slot walk, the flatten, and the `remoteBoardKey` filter now exist one time. No other copy of this pipeline is in RelatedBoards.swift.
    - CrossRepoTransferTests.swift:184: new helper `makeAssignedOldTask(named:on:)` adds the actor (id `alice`, name as a parameter) and the assigned old task, and gives the old task URI. `makeAssignedTransfer` and `transferStoresAssigneeAsOldBoardURI` both call it.
    - CrossRepoTransferTests.swift:227: `dependencyIDs(of:)` and `assigneeIDs(of:)` are replaced by one `ids(of:under:)`. All callers pass `PropertyName.dependsOn` or `PropertyName.assignees`.
    - Same cause in the whole file: `names(in:)`, `ids(of:under:)`, and three new `tasks.compactMap { task in task["id"] }` lines now all use one helper `texts(of:in:)`.
    - Choice on old tests: `transferStoresAssigneeAsOldBoardURI`, `dependencyIDs(of:)`, and `names(in:)` existed before this task (checked with `git show HEAD~1`). The review rule lets me leave old tests as they are, but I changed them to call the shared helpers, because each change is small and removes the copy completely. The old test now adds the actor with `id: alice, name: alice` in place of `name: alice`; the actor slug is the same (`alice`), so the test checks the same behavior.
    - Note: the `replace_all` flag of the files tool replaced only one copy per call in this session. I edited each copy and checked with grep that no old call stays.
  timestamp: 2026-10-16T02:12:16.799698+00:00
- actor: claude-code
  id: 01m517pjn1hdv1qnnjakc66nxe
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/CrossRepo/RelatedBoards.swift, Sources/FoundationModelsKanban/Derived/ReadinessCache.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoTransferTests.swift. `swift test --filter CrossRepoTransferTests`: 24 tests in 1 suite passed. `swift test`: 1552 tests in 123 suites passed, 0 failed. Only the accepted SwiftPM "missing creator" warning. Review findings: 4 of 4 checked.
    - next: /review
  timestamp: 2026-10-16T02:12:18.721886+00:00
- actor: claude-code
  id: 01m51a2z5tz6vn2vcmh0q4w7hf
  text: |-
    ### test - green
    - evidence: swift build - Build complete, only the allowed SwiftPM "missing creator" warning. swift test - 1552 tests in 123 suites passed, 0 failures, 0 skipped, 0 issues, no warnings except the allowed "missing creator" one.
    - note: the first swift test run (iteration 2 code) made no progress for 30 minutes with 0 percent CPU, and its output was lost. I stopped only the two processes of that run (swift-test and its test helper in this repo). One full run again, with output saved to a file, passed in 62 seconds. No code changed between the runs. No time limit was raised.
    - next: review
  timestamp: 2026-10-16T02:54:01.914698+00:00
- actor: claude-code
  id: 01m51a44ak5176y6fh833x8tkn
  text: |-
    ### commit — changed
    - evidence: local commit "fix(cross-repo): address review findings for remote assignees (^x020t0g)". Files: RelatedBoards.swift, ReadinessCache.swift, CrossRepoTransferTests.swift, and the .kanban/tasks files (this task and a new task about a test hang). The sha is in the step record returned to the caller.
    - next: review. No push was done.
  timestamp: 2026-10-16T02:54:39.955647+00:00
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

## Review Findings (2026-10-15 20:54)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 8 file(s) reviewed, 9 not reviewed.

> 8 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 8 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `divergence.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/CrossRepo/RelatedBoards.swift:528` `duplication/duplication` — The new `Graph.remoteAssigneeKeys` repeats the body of `Graph.remoteDependencyKeys` (ReadinessCache.swift). Both collect the task slots, flatten one task edge list, and keep the `remoteBoardKey` values. Only the edge source differs (`assignees` versus `dependencies(of:inBoard:)`). The two copies can drift, so a later fix to one can miss the other. Extract one shared helper on `Graph`, for example `remoteBoardKeys(of edges: (TaskNode) -> [EdgeTarget]) -> Set<String>`, or a helper that takes the per-task edge list as a closure. Call it from both `remoteAssigneeKeys` and `remoteDependencyKeys`, and delete the duplicated pipeline. Keep the edge-source difference as the only argument.
- [x] `Sources/FoundationModelsKanban/CrossRepo/RelatedBoards.swift:528` `reuse/reuse` — The new `remoteAssigneeKeys` repeats the body of `remoteDependencyKeys`. Both walk every task slot, flatten one task edge list, and keep the `remoteBoardKey` values. Two copies of this logic can diverge, and a fix to one would be missed in the other. The new property should share one helper with `remoteDependencyKeys`, parameterized by the edge list. Extract a shared `Graph` helper that takes the per-task edge list, for example `remoteBoardKeys(of edges: (TaskNode) -> [EdgeTarget]) -> Set<String>`. Make `remoteDependencyKeys` and `remoteAssigneeKeys` both call it with their own closure.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoTransferTests.swift:184` `reuse/reuse` — `makeAssignedTransfer` repeats the setup that the existing test `transferStoresAssigneeAsOldBoardURI` already does inline: it adds an actor with `CommentTests.run`, builds the `assignees:` list from `AddUpdateTaskTests.list(of:)`, and adds the old task with `CrossRepoFixture.addTask`. The same setup now lives in two places, so a change to one will not reach the other. Move the actor-and-assigned-task setup into one helper, for example `makeAssignedOldTask(on:operation:)`, that returns the old task URI. Then have `makeAssignedTransfer` and `transferStoresAssigneeAsOldBoardURI` both call it. Keep the actor `name` as a parameter if the two tests need different names.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoTransferTests.swift:227` `reuse/reuse` — `assigneeIDs(of:)` repeats the body of the existing `dependencyIDs(of:)` helper. Both read a list of objects from one key of a task object, then take the `id` of each. Only the key differs (`assignees` instead of `dependsOn`). The new helper is a near-match that was not extended, so the same logic now lives in two places and will drift apart. Generalize `dependencyIDs(of:)` to take the key, for example `static func ids(of task: [String: Any], under key: String) throws -> [String]`, and have both call sites pass `"dependsOn"` or `"assignees"`. Alternatively, keep `dependencyIDs(of:)` and add an `assigneeIDs` that delegates to the shared helper. Either way, the list-of-ids logic should exist once.
