---
depends_on:
- 01M4B42S72SRF2PEZR5603JKBR
position_column: todo
position_ordinal: a880
title: 'Multitool proof: code mode end to end'
---
## What
Prove that the tool works in code mode. The basis is plan.md §9 and §10 step 18.
- Add `FoundationModelsMultitool` as a test dependency (by URL, the same as the other siblings).
- `Tests/FoundationModelsKanbanTests/Multitool/CodeModeTests.swift`: register `KanbanTool(graph:)` in a `MultiTool.Builder`, and run a `runCode` script that adds a task, reads `nextTask`, and moves the task to `doing`. The script passes `variables` once as an object and once as a JSON string (the plan.md §9 example script).
- A second test with a real `LanguageModelSession` checks that the on-device model makes the string form of `variables` for a document with variables. Mark it so that it runs only when the on-device model is available (a Swift Testing trait), and reports as skipped with a reason otherwise.

## Acceptance Criteria
- [ ] The script gets `result.data.board.nextTask` as a structured value.
- [ ] Both `variables` forms work through Multitool, which passes the object through because the schema has `anyOf` and no `type`.
- [ ] After the script, the task is in `doing` in the log.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Multitool/CodeModeTests.swift`.
- [ ] Run `swift test --filter CodeModeTests`; expect all pass (the model test is skipped only when the model is not available).

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.