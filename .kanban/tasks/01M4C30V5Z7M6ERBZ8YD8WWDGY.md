---
position_column: todo
position_ordinal: b280
title: 'plan.md: state the excludeDone default for tasks(deleted: true)'
---
## What
Task ^ryf7rn1 merged `Board.tasks(deleted:)` with the filter and the scoping arguments of plan.md §6.3. For `deleted: true`, the filter and the scoping arguments select from the tombstoned tasks, and `excludeDone` with no value is `false`. Thus `tasks(deleted: true)` shows each deleted task, also a deleted task in the done column.

plan.md §4.1 (the `Board.tasks` arguments, the line `excludeDone: Boolean, # no value: true, or false when a column is named (§6.3)`) and §6.3 ("Scoping arguments") do not state this rule yet.

- `plan.md`: add the rule to the `excludeDone` comment in §4.1 and to "Scoping arguments" in §6.3. Write in ASD-STE100 Simplified Technical English.
- Code: `Sources/FoundationModelsKanban/GraphQL/TaskSelection.swift` (`TaskSelection.init(for:)`) and `TasksArguments.excludeDone` in `Sources/FoundationModelsKanban/GraphQL/Schema.swift` already have this rule.

## Acceptance Criteria
- [ ] plan.md §4.1 and §6.3 state the `excludeDone` default for `deleted: true`.
- [ ] A person confirms the rule, or changes it (then change the code and the test "tasks(deleted: true) lists only the deleted tasks" to match).