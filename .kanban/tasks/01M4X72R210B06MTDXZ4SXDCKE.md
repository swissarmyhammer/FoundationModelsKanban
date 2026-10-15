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
- actor: claude-code
  id: 01m4ydqwpt32fgr3e57rf9vva6
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 2 files
    - test: green — swift test, 1275 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: a3b3447
    - review: findings — Sources/FoundationModelsKanban/Derived/Readiness.swift:272, Sources/FoundationModelsKanban/Derived/Readiness.swift:297, Sources/FoundationModelsKanban/Derived/Readiness.swift:300, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCycleReadinessTests.swift:30, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCycleReadinessTests.swift:42
  timestamp: 2026-10-15T00:00:09.946021+00:00
- actor: claude-code
  id: 01m4ye1macqyj6cc23p8t5ys94
  text: |-
    Review findings (2026-10-14 18:55) are fixed. All 5 items are checked.
    - WalkBoard reuse: `WalkBoard` is now internal and is the one type for a board key and graph pair. `DependencyWalk.board(holding:)` returns `WalkBoard?`, and `DependencyWalk.readiness(of:)` takes `WalkBoard`. The unnamed tuple is gone. A new `WalkBoard.init(of: BoardSnapshot)` makes the board from a loaded related board. `Readiness.step(toTaskOf:)` and `DependencyWalk` both use it.
    - `TaskPosition.boardKey` and `TaskPosition.slot` assign-only: the synthesized `Hashable` conformance reads these properties (the walk keeps a `Set<TaskPosition>` and compares with `==`). The dead-code-swift rule says: do not delete such a property, and write `// periphery:ignore` above it with the reason on its own line. I did that for each of the two properties. TaskPosition is the only Hashable type in the file.
    - ThreeRepos and makeThreeRepos: `CrossRepoFixture.ThreeRepos` (sandbox, app, lib, tools) with `make(toolsNamed:origin:)` replaces the two copies. CrossRepoParallelLoadTests and CrossRepoCycleReadinessTests both call it. Each file keeps only its `toolsName` and `toolsOrigin` constants. No other test file made a third repo.
    - Tool note: `replace_all: true` on the `files` edit op changed only one match each time. I made the remaining edits one at a time.

    ### implement — changed
    - evidence: 5 files. Sources/FoundationModelsKanban/Derived/Readiness.swift, Sources/FoundationModelsKanban/Derived/DependencyWalk.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoFixture.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoParallelLoadTests.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCycleReadinessTests.swift. `swift test`: 1275 tests in 98 suites passed, 0 failed. The only warning is the accepted SwiftPM "missing creator" warning.
    - next: /review
  timestamp: 2026-10-15T00:05:29.036210+00:00
- actor: claude-code
  id: 01m4yedysw8f1x4jghzt5czvkc
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 5 files (5 findings fixed)
    - test: green — swift test, 1275 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: 8617fa4
    - review: clean — none
  timestamp: 2026-10-15T00:12:12.988663+00:00
position_column: done
position_ordinal: ef80
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

## Review Findings (2026-10-14 18:55)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/Derived/Readiness.swift:272` `reuse/reuse` — The new `WalkBoard` struct holds a board key and graph pair. `DependencyWalk` already returns this pair as an unnamed tuple from its board lookup, so the codebase has two shapes for one thing. Use one type for a board key and graph pair. Either give `DependencyWalk` the `WalkBoard` type, or use the existing tuple in `Readiness` and drop `WalkBoard`. Keep only one of the two.
- [x] `Sources/FoundationModelsKanban/Derived/Readiness.swift:297` `code-hygiene/dead-code-swift` — var.instance `boardKey` is assignOnlyProperty.
- [x] `Sources/FoundationModelsKanban/Derived/Readiness.swift:300` `code-hygiene/dead-code-swift` — var.instance `slot` is assignOnlyProperty.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCycleReadinessTests.swift:30` `reuse/reuse` — The `ThreeRepos` struct repeats the three-repo shape already defined in another test file. Use the `ThreeRepos` type from `CrossRepoParallelLoadTests` instead of declaring a second one, or move the type into `CrossRepoFixture` so that both files share it.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCycleReadinessTests.swift:42` `reuse/reuse` — `makeThreeRepos()` builds the same three side-by-side repos as an existing helper, so the test file now carries a second copy of that setup. Call `CrossRepoParallelLoadTests.ThreeRepos.make` in place of this helper, or move that helper to `CrossRepoFixture` and call it from all three test files. Keep only the `toolsName` and `toolsOrigin` arguments in this file.
