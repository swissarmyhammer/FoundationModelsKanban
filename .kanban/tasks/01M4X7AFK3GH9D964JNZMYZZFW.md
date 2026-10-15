---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m504v61k2eq7kecb5sc3baxx
  text: |-
    Picked up. Research:
    - Readiness is built per BoardView (BoardView.init -> Readiness.init). BoardStore.view makes a new BoardView on each access, from the working graph of the run and the related boards of the run. blockers(ofTaskAt:) runs isBlocking -> hasDependencyPath (a walk) on each call. ready, #READY/#BLOCKED (VirtualTags), nextTask, Summary, blockedBy all go through Readiness.blockers / isReady.
    - The live graph is in CommitSession.live (LiveGraph, a value type). It changes in LiveGraph.adopt (commit, also undo), LiveGraph.apply (watcher, held transactions can change nodes whose files did not change, full reload replaces self).
    - BoardSource (directory, search, events) goes with each BoardSnapshot of a session, so it reaches each read view of the board (current and related). It is the place to carry a shared cache object from the live graph to the views.
    - Graph is a COW value type; == on graphs that share storage is cheap. A slot diff of two graphs gives the changed nodes for any kind of change (commit, watcher, held txn, full reload, undo, related board change).
    - Plan: a ReadinessCache (final class, Mutex) owned by LiveGraph and kept across full reloads, carried in BoardSource. Readiness takes the cached blockers when the inputs (graph of the board, key, and the graph of each related board that the computation read) are the same. On a change it diffs the graphs, finds the changed task URIs, walks the reverse dependency index (raw edges of all tasks of the read boards) to find each dependent task also across boards, and computes again only those tasks. A column change or a key change gives a full compute. A walk counter on the cache lets the tests count the walks.
  timestamp: 2026-10-15T16:03:09.491452+00:00
- actor: claude-code
  id: 01m505yjbz4k53anya9fv500zm
  text: |-
    Implementation landed (GREEN for the first two tests):
    - New Derived/ReadinessCache.swift: ReadinessCache (final class, Mutex) keeps one ReadinessState. A read with the same graph, key, and related-board graphs takes it (Graph == is O(1) when storage is shared). Else ReadinessState.updated diffs the graphs (Graph.changedRefs(since:)), walks a reverse DependencyIndex (raw edges of the tasks of the board and of each read related board, by NodeURI position) to find each dependent task also across boards, and computes again only those tasks. Column change in the board, a key that now names a different board, a renumbered graph (full reload), or a new remote key in a changed task give a full compute.
    - Readiness.swift: the walk moved into BlockerWalk (counts walks). Readiness takes cached deps and blockers when it has a cache.
    - LiveGraph owns the cache (kept across a full reload). BoardSource carries it to every BoardView of the board (current and related). Views with no source (graph rules, history, fixtures) keep the old uncached behavior.
    - RelatedBoards: board(forKey:) (reused by task(for:)); dependencyRequests now uses Graph.remoteDependencyKeys.
    RED was seen first: with only a walk counter, the second nextTask walked again (1 -> 2) and the in-memory board walked 4 instead of 2.
  timestamp: 2026-10-15T16:22:28.991308+00:00
- actor: claude-code
  id: 01m50696g9k7aj7b664hxnmemq
  text: 'Tests added and checked: property test (reuses Design.ReplayPropertyTests.runSequences + RandomCall, then 12 steps per sequence of random public calls or raw log lines applied with CommitSession.apply(watchedPaths:): dependsOn edges that can close cycles, delete/undelete, column moves; after each step the cached blockers of each task equal an uncached full walk), an in-board cycle closed by a watcher apply, and a new CrossRepo/CrossRepoReadinessCacheTests suite (git repos side by side): a second engine completes the related task and the app engine''s kept readiness turns ready after the lib watcher batch; a raw lib edge closes a cross-board cycle and the kept ready task turns blocked. Mutation check: with DependencyIndex.closure returning only the seeds, all 6 new tests fail (property test 120 issues), so each test can catch a broken dependent walk. Code restored after the check.'
  timestamp: 2026-10-15T16:28:17.289980+00:00
- actor: claude-code
  id: 01m506d0h6tp7natnhzdd7rt1q
  text: |-
    ### implement — changed
    - evidence: swift test: 1506 tests in 119 suites passed, only the accepted mlx "missing creator" warning. Files: Sources/FoundationModelsKanban/Derived/ReadinessCache.swift (new), Derived/Readiness.swift, Model/Graph.swift, Observe/LiveGraph.swift, CrossRepo/RelatedBoards.swift, GraphQL/QueryResolvers.swift, Tool/Commit.swift; Tests/FoundationModelsKanbanTests/Derived/ReadinessCacheTests.swift (new), Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoReadinessCacheTests.swift (new). All acceptance-criteria and test boxes checked.
    - note: divergence.md §16 Gap 3 still describes the gap as open; divergence.md was not changed in this task.
    - next: /review
  timestamp: 2026-10-15T16:30:22.246532+00:00
depends_on:
- 01M4X6ZBTA66TCPVYM41QR0ACD
- 01M4X72R210B06MTDXZ4SXDCKE
position_column: doing
position_ordinal: '80'
title: Cache readiness so that ready and nextTask do not walk the graph again on each call
---
## What
divergence.md §2 ("Performance"), §16 (Gap 3 of the "fully cached" rule), and K9 (the user kept this work). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

- Now `isReady` walks the dependency graph again for each task and for each done dependency (`S/Derived/Readiness.swift:147`). Nothing keeps the result. `ready`, the READY and BLOCKED virtual tags, the filters, and `nextTask` repeat this work on each call. On a large board this is slow.
- Keep the readiness of each task in memory, with the live graph of its board. Compute it one time when the board loads.
- Change it only when something that it depends on changes:
  - a write (the commit makes the working copy the live graph);
  - an apply of changed files from the file watcher;
  - a change of a related board that a cross-board dependency reads.
- After a change, compute again only the tasks that the change can affect: the changed tasks, and each task that depends on them, also across boards. A full compute is acceptable when the change is large (for example, a full reload).
- The result must always be the same as a full walk. This includes the rules for tombstones (ignored), unknown targets (they block), unresolved cross-board targets (they block), and cycles (each task in a cycle is blocked, also across boards, X8).

## Acceptance Criteria
- [x] A read (`ready`, `#READY`, `#BLOCKED`, `nextTask`) does not walk the dependency graph when nothing changed since the last compute.
- [x] After each kind of change (a write, a watcher apply, a change of a related board), the cached readiness is the same as a full walk.
- [x] A cycle in one board and a cycle across boards still block each task in the cycle.

## Tests
- [x] A property test: after a random sequence of writes, deletes, undeletes, dependency changes, and watcher applies, the cached readiness of each task equals a full walk.
- [x] A test with a cross-board dependency: a change on the related board changes the readiness of the dependent task.
- [x] A test that counts the graph walks: a second `nextTask` with no change between the calls does no walk.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.