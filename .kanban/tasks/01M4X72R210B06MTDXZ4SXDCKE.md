---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4ycy6cj6mvdg4hvf7vvwva4
  text: |-
    Research done.
    - S/Derived/Readiness.swift: `isBlocking` calls `hasDependencyPath(from:to:)` only for a `.slot` target. The walk uses only the slots of this graph, so an `.unresolved(.remote)` edge ends the walk. A done remote target never runs a walk.
    - S/Derived/DependencyWalk.swift is the cross-board walk of the write path (cycle refuse). It makes a full `Readiness` for each board that it reads. That is too slow to call for each done dependency, and it would recurse in concept. Thus readiness gets its own walk over (board key, slot) positions, and computes the dependencies of a task of a related board on demand with `Graph.liveDependencies` (same tombstone rule).
    - `RelatedBoards.task(for:)` resolves a remote ref to (board snapshot, slot, state). A ref with the key of the current board resolves to `.current`; the walk maps that back to this graph, also when `related.current` is not set.
    - Tests: real git repos in `GitSandbox` (pattern of UnresolvedDependsOnTests), cycle edge with a raw log line (`KanbanGraphTests.append`). A third repo `tools` for the three-board test. Suite keeps `.watcherBudget`.
  timestamp: 2026-10-14T23:46:07.890344+00:00
- actor: claude-code
  id: 01m4yd8caa68n6555m3apn48jh
  text: |-
    Implementation landed (TDD). RED: 3 of 5 new tests failed because the feature was missing. The two chain tests are guards, and they passed. GREEN: 5 of 5 pass. Full `swift test`: 1275 tests in 98 suites pass. The only warning is the accepted SwiftPM "missing creator" warning.
    - `Readiness.isBlocking` now runs the cycle walk for each done dependency, also for a cross-board target. The walk steps over (board key, slot) positions. A task of a related board gets its dependencies on demand from `Graph.liveDependencies`, so the tombstone rule stays the same. A remote ref that resolves to a board with the key of this board is read in this graph. Only a live task continues the walk.
    - I did not use `DependencyWalk` again. It makes a full `Readiness` for each board that it reads, and it records commit paths. Neither one is correct for a read.
    - Note for ^zmyzzfw: the walk now also runs for each done cross-board dependency. That adds work to each read. The cache card must include it.

    ### implement — changed
    - evidence: 2 files. Sources/FoundationModelsKanban/Derived/Readiness.swift (cross-board walk), Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCycleReadinessTests.swift (new, 5 tests, `.watcherBudget`). `swift test`: 1275 passed, 0 failed.
    - next: /review
  timestamp: 2026-10-14T23:51:41.642179+00:00
position_column: doing
position_ordinal: '80'
title: Block each task in a dependency cycle across boards
---
## What
divergence.md X8 (§1.1, §2, §11 bugs). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem: a cycle across boards that comes from a merge does not block. `hasDependencyPath` follows only edges in the same board (S/Derived/Readiness.swift:144-151,175-181). Example: `a` depends on `B#b`, and `b` is done and depends on `A#a`. Then `a` is READY, and `nextTask` returns it. The rule (§5.3 step 5 of the design): each task in a cycle is blocked. A cycle in one board already blocks each task.

Change: the cycle part of readiness follows edges into loaded related boards too (with the same rules for tombstones and unknown targets). Each task in a cycle across boards is BLOCKED, and `nextTask` does not return it. Readiness stays memory only: it reads no file and runs no `git`.

## Acceptance Criteria
- [x] In the example, `a` is BLOCKED and not READY, and `nextTask` does not return it.
- [x] A cycle across three boards blocks each task in it.
- [x] A chain across boards with no cycle keeps its current readiness.

## Tests
- [x] The two-board example (make the cycle with raw log lines or a merge, because the write path refuses a cycle).
- [x] A cycle across three boards.
- [x] `nextTask` skips a task in a cycle across boards.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.