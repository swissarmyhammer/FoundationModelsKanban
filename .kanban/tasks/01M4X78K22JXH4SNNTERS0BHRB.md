---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m501tgwz4fg7ze6svpnn664a
  text: 'Research done. Some listed tests exist already from other tasks: cross-board tombstoned dependency (UnresolvedDependsOnTests.tombstonedTargetIsNotUnresolved), missing task on a found board (UnresolvedDependsOnTests.missingTaskOfLoadedBoardIsUnresolved, DependencyTargetWarningTests), nextTask with a cross-board cycle (CrossRepoCycleReadinessTests.nextTaskSkipsTaskInCrossBoardCycle), and readiness of a three-board cycle. Missing: write-path DEPENDENCY_CYCLE across three boards, body-marker cycle through a related board, end-to-end marker readiness, updateTask dropping a cross-board URL from the body, ^<other-board task> on history and changes, R15 for tags/assignees/author, the IntegrationTests two-repo test, the nextTask list, and the three virtual-tag tests. Note for R15: an assignee or author URI of another board gives ACTOR_NOT_FOUND (the not-found code of the actor type); a tag URI gives NOT_FOUND, as for column. Note: a board with one column has that column as the terminal column, so each task there is done and nextTask is null.'
  timestamp: 2026-10-15T15:10:22.111336+00:00
- actor: claude-code
  id: 01m503cv29zzc1btshwermd8e4
  text: 'Implementation landed. Each new test passed on its first run, so no test showed a bug and no production code changed. Map of tests: nextTask list -> T/Filter/NextTaskTests.swift (tombstoned only dependency, cycle in one board, board not loaded, all blocked, CONFLICT, ULID tie-break, slug tie-break, tombstoned column, one column, #READY/#BLOCKED/^ filters); cross-board nextTask (done, not done, board not found), body-marker cycle, end-to-end marker readiness, dropped cross-board URL, three-board write cycle -> T/CrossRepo/CrossRepoDependencyTests.swift; ^<other-board task> on history and changes -> T/CrossRepo/CrossRepoRefFilterTests.swift; R15 (column, tags, assignees, author) -> T/Mutations/OtherBoardRefTests.swift; virtual tags -> T/Derived/VirtualTagsTests.swift and T/Derived/PriorityTagsTests.swift; two repos side by side -> IntegrationTests/.../CrossRepoDependencyTests.swift with TemporaryGitRepo.withRepos. Existing coverage kept for: cross-board tombstone (UnresolvedDependsOnTests.tombstonedTargetIsNotUnresolved), R3 missing task on a found board (UnresolvedDependsOnTests.missingTaskOfLoadedBoardIsUnresolved), cross-board cycle nextTask (CrossRepoCycleReadinessTests.nextTaskSkipsTaskInCrossBoardCycle). Environment note: `swift test --package-path IntegrationTests` fails in this sandbox, because SwiftPM wants to clone FoundationModelsMetadataRegistry again and the sandbox refuses writes to its `.kanban/` folder. With `--scratch-path` in the session scratchpad the integration suite builds and passes (2 tests). The IntegrationTests/.build checkout was put back as it was.'
  timestamp: 2026-10-15T15:37:50.921129+00:00
- actor: claude-code
  id: 01m503czq6cddw4tdt505tqxfw
  text: |-
    ### implement — changed
    - evidence: 8 files — T/Filter/NextTaskTests.swift, T/Derived/VirtualTagsTests.swift, T/Derived/PriorityTagsTests.swift, T/CrossRepo/CrossRepoDependencyTests.swift (new), T/CrossRepo/CrossRepoRefFilterTests.swift (new), T/Mutations/OtherBoardRefTests.swift (new), IntegrationTests/Tests/FoundationModelsKanbanIntegrationTests/CrossRepoDependencyTests.swift (new), IntegrationTests/.../Support/TemporaryGitRepo.swift. `swift test`: 1500 tests in 117 suites passed, only the accepted mlx "missing creator" warning. Integration suite (scratch path): 2 tests passed.
    - next: /review
  timestamp: 2026-10-15T15:37:55.686135+00:00
depends_on:
- 01M4X71FVFN9HYJ19VJ71VWV3B
- 01M4X72R210B06MTDXZ4SXDCKE
position_column: doing
position_ordinal: '80'
title: Add the missing tests for dependencies, nextTask, and virtual tags
---
## What
divergence.md K14 (DECIDED: keep all the missing tests of sections 1–3, as one test task) and §11. This is work on the Swift package tests (T/ = Tests/FoundationModelsKanbanTests/). Leave out "a related board that cannot be read", because the Q7 task covers it. Leave out each BLOCKING test, because Q1 removes BLOCKING. The tests for X4 (a board reached by a path), X5 (undo on a second copy), and X6 (undo conflict across boards) are in their own tasks; do not repeat them here.

If a test shows a bug, fix the code in this task when the fix is small, or add a new task for it.

Tests to add — dependencies between boards (§1.1):
- A dependency on a tombstoned task of a related board (the tombstone is ignored).
- A body marker that closes a cycle through a related board (`DEPENDENCY_CYCLE`).
- An end-to-end marker dependency on another board that changes `ready` when the other task moves to done.
- `updateTask(dependsOn:)` that drops a target on another board also removes its URL from the body.
- A `^<task on another board>` filter on `changes` and `history`.
- A cycle across three or more boards (write path gives `DEPENDENCY_CYCLE`).
- A missing task on a board that is found counts as not done (R3).
- `tags`, `assignees`, and `author` with a URI of a different board stay in one board (R15): the call gives the same error as for `column`.
- A test in `IntegrationTests/` that uses two repos side by side.

Tests to add — `nextTask` (§2):
- The only dependency is tombstoned (the task is returned).
- A cycle in one board, and a cycle across boards (neither task is returned).
- A dependency on another board that is done, not done, and on a board that is not found (check `nextTask`, not only `ready`).
- Two tasks with the same ordinal (ULID tie-break).
- Two columns with the same `order` (slug tie-break).
- A task in a tombstoned column (shows in the first column).
- All tasks are blocked (`null`).
- A board with one column.
- A task with CONFLICT.
- The filters `#READY`, `#BLOCKED`, and `^<blocked id>` with `nextTask`.

Tests to add — virtual tags (§3):
- A self-dependency on an open task gives the virtual tag BLOCKED (D2).
- A tombstone with CONFLICT.
- The priority tags (HIGH, MEDIUM, LOW) on a board with no live column.

## Acceptance Criteria
- [x] Each test in the lists above exists and passes.

## Tests
- [x] The tests listed above.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.