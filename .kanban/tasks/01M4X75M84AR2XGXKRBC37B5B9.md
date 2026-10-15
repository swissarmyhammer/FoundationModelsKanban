---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4z4k2ceq3t68ej48tqk284c
  text: |-
    Research done.
    - No code reads `priority` now. The name rewrite gives a "no match" error for `priority` on AddTaskInput and UpdateTaskInput. The Q15 error was never built.
    - Plan: add one input field `priority` to AddTaskInput and UpdateTaskInput, with the aliases `prio` and `urgent` (FieldAliases byType). The field type is a new scalar `Priority`. Its parseLiteral and parseValue change each value (string, unquoted enum word, Bool, number) to its text. Reason: Graphiti decodes each input through MapDecoder, and MapDecoder can read a number as a Bool. Text avoids that risk.
    - A fixed table (case does not matter) gives the move: top, end, or no move. `true` is in the top row, so `urgent: true` moves to the top.
    - addTask: the move gives the ordinal of the new task (before the first task of the column, or the end). updateTask: the move gives the ordinal in the new column (when `column` is given) or in the column where the task shows now. The move is in the same patch as the add or the update.
    - Each priority value gives one warning (code PRIORITY_IS_POSITION) in extensions.warnings through TaskWrite.warnings.
    - Tests: new suite Tests/FoundationModelsKanbanTests/Mutations/PriorityInputTests.swift on temporary fixture repos (ColumnActorTests.makeFixtureGraph), with the .watcherBudget trait.
  timestamp: 2026-10-15T06:39:29.166050+00:00
- actor: claude-code
  id: 01m4z4xkfmabmxxz8pstq2ee0j
  text: |-
    Implementation landed (TDD: the new suite failed first with "Field \"priority\" is not defined by type \"AddTaskInput\"", then passed).
    - New S/GraphQL/PriorityInput.swift: scalar `Priority` (PriorityValue keeps the text of a string, an unquoted word, a Bool, or a number), PriorityMove with the fixed table (lowercase lookup, so the case does not matter), the warning (code PRIORITY_IS_POSITION), Graph.ordinal(for:inColumn:excluding:) and Graph.displayColumn(of:).
    - TaskMutations.swift: `priority` input field on AddTaskInput and UpdateTaskInput. addTask: a top/end move gives the ordinal of the new task in the same patch (it wins over an explicit `ordinal`). updateTask: place(of:movingTo:by:...) puts the task at the top or end of the new column, or of the column where it shows now (ordinal only). The warning goes into TaskWrite.warnings after the dependency warnings.
    - FieldAliases.swift: `prio` and `urgent` are aliases of `priority` on both inputs. Scalars.swift registers the scalar. SchemaDescription.taskPriority describes the field.
    - Discovery: `urgent: true` works through the alias, because `true` is a row of the top move.
    - Tests: Tests/FoundationModelsKanbanTests/Mutations/PriorityInputTests.swift (16 table rows x updateTask and addTask, one-patch checks, column+priority, variable values Bool and number). Full `swift test`: 1371 tests in 109 suites passed; only the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-15T06:45:14.356163+00:00
- actor: claude-code
  id: 01m4z4xnx361hza7r2s38mwd9g
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsKanban/GraphQL/PriorityInput.swift (new), Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift, Sources/FoundationModelsKanban/GraphQL/Scalars.swift, Sources/FoundationModelsKanban/GraphQL/FieldAliases.swift, Sources/FoundationModelsKanban/GraphQL/SchemaDescription.swift, Tests/FoundationModelsKanbanTests/Mutations/PriorityInputTests.swift (new); `swift test` 1371 tests passed, 0 failures
    - next: /review
  timestamp: 2026-10-15T06:45:16.835549+00:00
depends_on:
- 01M4X6X6PS5P524DW45RBSSWN2
position_column: doing
position_ordinal: '80'
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
- [x] `addTask(input: {title: "x", priority: "high"})` puts the task at the top of its column, with a warning.
- [x] `updateTask(input: {id: ..., prio: "low"})` moves the task to the end, with a warning.
- [x] `priority: "medium"`, `"normal"`, `"P2"`, a bare number, and an unknown value make no move, with a warning.
- [x] `urgent: true` moves the task to the top.

## Tests
- [x] A test for each row of the table: `urgent`, `critical`, `high`, `P0`, `P1`, `urgent: true`, `low`, `P3`, `P4`, `medium`, `normal`, `P2`, a bare number (`1` and a large number), and an unknown value.
- [x] A test that each case gives a warning.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.