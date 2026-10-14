---
assignees:
- claude-code
depends_on:
- 01M4X6X6PS5P524DW45RBSSWN2
position_column: todo
position_ordinal: 9c80
title: Move the task in its column for a priority input, with a warning
---
## What
divergence.md P2 and K15 (DECIDED; they replace Q15), and §11 "Q15 (replaced by P2 and K15)". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Priority comes from the task order in the column. There is no priority field. An agent can send `priority`, `prio`, or `urgent` in a task input (for example on `addTask` or `updateTask`).

Decided behavior: accept `priority`, `prio`, and `urgent` on task inputs. Use this fixed value table (case does not matter):
- `urgent`, `critical`, `high`, `P0`, `P1`, and `urgent: true` → move the task to the top of its column.
- `low`, `P3`, `P4` → move the task to the end of its column.
- `medium`, `normal`, `P2` → no move.
- A bare number (for example `1` or `5`), or any other value → no move.
- Each case gives a warning in `extensions.warnings` that says that the position in the column is the priority (use `moveTask` with `before`/`after`, or filter with `#HIGH`/`#MEDIUM`/`#LOW`).
- On `addTask`, the move applies to the new task in its column. The move is in the same transaction as the add or update.

## Acceptance Criteria
- [ ] `addTask(input: {title: "x", priority: "high"})` puts the task at the top of its column, with a warning.
- [ ] `updateTask(input: {id: ..., prio: "low"})` moves the task to the end, with a warning.
- [ ] `priority: "medium"`, `"normal"`, `"P2"`, a bare number, and an unknown value make no move, with a warning.
- [ ] `urgent: true` moves the task to the top.

## Tests
- [ ] A test for each row of the table: `urgent`, `critical`, `high`, `P0`, `P1`, `urgent: true`, `low`, `P3`, `P4`, `medium`, `normal`, `P2`, a bare number (`1` and a large number), and an unknown value.
- [ ] A test that each case gives a warning.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.