---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m51e1shw0g2nnmc1f9ab2k8y
  text: |-
    Research results:
    - `KanbanGraph.loadRelatedBoard` keeps the first engine of a path. `SessionFeeds.add` keeps the first feed of a path.
    - The view sends the events itself: `SessionFeeds.publish` finds the feed by path and sends to the subscribers that the view owns. A subscriber lives in the `ChangeFeed` object of the engine. Thus, when the view replaces the feed of a path, the subscribers in the old feed get no more events. They must move to the new feed.
    - The old engine is not closed when the repo is replaced. Its `root` is still the same path, and `BoardEngine.publishChanges` keys its changes by `root.canonicalPath`. Thus a change of the old engine comes to `KanbanGraph.publish` with the same path as the new engine. The view must drop the changes of a path when they do not come from the engine that the view holds for that path. To find the engine, `BoardChanges` needs the identity of its engine.
    - A continuation whose stream ends before the move does not call a new `onTermination`. The new feed must remove a subscriber whose `yield` gives `.terminated`.
    - Plan: (1) `ChangeFeed.moveSubscribers(ownedBy:to:)`; (2) `SessionFeeds.replace(_:forBoardAt:)`; (3) `loadRelatedBoard` replaces an engine with a different identity; (4) `BoardChanges.identity`, and `KanbanGraph.publish` keeps only the changes of the loaded engine of each path; (5) divergence.md records the decision.
  timestamp: 2026-10-16T04:03:17.692010+00:00
- actor: claude-code
  id: 01m51f3d4fzcdt8y1jab4rdkyx
  text: |-
    Implementation done (TDD). Notes for the next agent:
    - RED 1: `ReplacedRepoTests.viewReadsNewRepo` gave the old key and the old task. RED 2: `subscriberGetsChangesOfNewRepo` first passed by accident, because the old engine (root = the same path) wrote the new task into the new repo with the old key. I added a check that the task URI has the new key; then it failed correctly.
    - RED 3: my first test for "no changes of the old board" injected the events of the OLD board. It passed without a fix, because the filter of a subscriber reads the nodes in the view of the new board, and the old tasks are not there. The real leak is the old engine that reads the files of the NEW repo at the same path and sends them again with the same path. The test now injects the new board events as a change of the old engine, and expects no duplicate event. That test failed with a duplicate event before the identity filter.
    - Design: `KanbanGraph.record(_:)` replaces the engine of a path when the identity differs. `SessionFeeds.replace(_:forBoardAt:)` moves the subscribers of the view with `ChangeFeed.moveSubscribers(ownedBy:to:)`. A `SubscriberRoute` (one lock for each subscriber) holds the feed and the id of the subscriber now; the termination handler is set one time and calls `route.end()`. Reason: a new `onTermination` that is set after the stream ended is never called, so a plain re-set has a race. `BoardChanges` has a new `identity` field, and `KanbanGraph.publish` keeps only the changes of the engine that the view holds for each path.
    - ChangeFeedTests were written after the integration tests drove the code. I checked that `endOfMovedStreamRemovesSubscriberFromNewFeed` catches a fault: with the route not updated in `move`, the test failed; the code was then put back.
    - New task ^1yg0p73: the old engine still runs on the old path (watcher and commit path), until the host closes.
    - Full run: `swift test` 1559 tests in 125 suites passed, 0 failures, only the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-16T04:21:39.087433+00:00
- actor: claude-code
  id: 01m51f3g69nr0t28dwdvab0swc
  text: |-
    ### implement — changed
    - evidence: 11 files — Sources/FoundationModelsKanban/Observe/ChangeFeed.swift, Sources/FoundationModelsKanban/Observe/SessionFeeds.swift, Sources/FoundationModelsKanban/Observe/ChangeRound.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Sources/FoundationModelsKanban/Tool/BoardEngine.swift, Tests/FoundationModelsKanbanTests/CrossRepo/ReplacedRepoTests.swift (new), Tests/FoundationModelsKanbanTests/Observe/ChangeFeedTests.swift (new), Tests/FoundationModelsKanbanTests/CrossRepo/PathRefCacheTests.swift, Tests/FoundationModelsKanbanTests/Observe/ChangeBuilderTests.swift, Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift, divergence.md (§16 Gap 5). `swift test`: 1559 tests, 125 suites, 0 failures.
    - next: /review
  timestamp: 2026-10-16T04:21:42.217532+00:00
- actor: claude-code
  id: 01m51ff5gc6jqebrpav2zdc2qp
  text: |-
    ### test — green
    - evidence: swift build: complete, only the allowed SwiftPM "missing creator" warning. swift test (full): 1559 tests in 125 suites passed, 0 failures, 0 skipped, 0 warnings. IntegrationTests (--scratch-path scratchpad/integration-build): 3 tests in 3 suites passed, only the allowed "missing creator" warning. Stability: ReplacedRepoTests, ChangeFeedTests and SubscriptionTests alone, 5 runs in a row, each 16 tests in 3 suites passed, no hang, no flaky result. No code was changed.
    - next: review
  timestamp: 2026-10-16T04:28:04.492277+00:00
- actor: claude-code
  id: 01m51ffzk6qga5ms5qrfg8k988
  text: |-
    ### commit — changed
    - evidence: local commit with subject "fix(cross-repo): replace the related engine when a new repo is at the same path (^0nkvw6d)"; sha is in the final report of the commit step. Files: ChangeFeed.swift, ChangeRound.swift, SessionFeeds.swift, KanbanGraph.swift, BoardEngine.swift, ReplacedRepoTests.swift, ChangeFeedTests.swift, PathRefCacheTests.swift, ChangeBuilderTests.swift, SubscriptionTests.swift, divergence.md, and the changed .kanban/tasks files (including new task ^1yg0p73).
    - next: review. No push was done.
  timestamp: 2026-10-16T04:28:31.206171+00:00
position_column: doing
position_ordinal: '80'
title: Replace the related engine of a session view when a new repo is at the same path
---
## What
Found during ^58v2scm. This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

`KanbanGraph.loadRelatedBoard(_:)` keeps the engine of a related board in `relatedBoards`, by the canonical path of its repo folder. It adds an engine only when the path has no engine (`if relatedBoards[path] == nil`). `SessionFeeds.add(_:forBoardAt:)` also keeps the first feed of a path.

When a repo is replaced at the same path (move the old folder away, make a new repo there), the host forgets the path ref result and reads git again (the `.place` and `.repo` forget paths of ^58v2scm). The host then gives a new copy with the new key, and `KanbanHost.relatedEngine` loads a new engine (a new `FolderIdentity`). But the view keeps the old engine of the path. `RelatedBoards.board(resolvedAs:)` reads the board by path, so `{ board(id: "<path>") { key } }` still gives the old key and the old tasks.

Seen in `PathRefCacheTests.replacedRepoIsReadAgain`: after the `.place` change, the host read git again (the git-call counter went up), and `host.board(ofFolderAt:)` gave the new key, but the GraphQL read through the session view gave the old key.

## Change
- [x] In `loadRelatedBoard`, when the engine of the path has a different `identity` from the loaded engine, replace the engine and its feed in the view.
- [x] Decide what the change feed of the view does with the old feed (end it, or keep its subscribers on the new feed). Decided: the subscribers of the view move to the new feed (divergence.md §16, Gap 5).

## Acceptance Criteria
- [x] After a repo is replaced at the same path, the next call with the path ref gives the board of the new repo (key and tasks).
- [x] The change feed of the view sends the changes of the new board, and no changes of the old board.

## Tests
- [x] A test replaces the repo of a path ref and checks the key of `{ board(id: "<path>") { key } }` through the session view.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.