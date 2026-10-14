---
assignees:
- claude-code
depends_on:
- 01M4X71FVFN9HYJ19VJ71VWV3B
- 01M4X72R210B06MTDXZ4SXDCKE
position_column: todo
position_ordinal: a780
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
- [ ] Each test in the lists above exists and passes.

## Tests
- [ ] The tests listed above.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.