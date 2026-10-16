---
assignees:
- claude-code
position_column: todo
position_ordinal: b680
title: Use the shared warning helpers in the older removed-parameter tests
---
## What
This is work on the Swift package. Code: Tests/FoundationModelsKanbanTests/GraphQL/RemovedParameterTests.swift.

^164tehz added two helpers to RemovedParameterTests: `expectResult(at:in:)` (no error, and an object at the result key) and `expectRemovedWarning(_:in:)` (the one warning of a removed parameter, with its code). It also added the constant `dueWarning`. The review finding of ^164tehz at RemovedParameterTests.swift (duplication/duplication) told the change not to edit the tests that existed before it, and to report this work as a separate task.

These older tests still write the same assertions inline:
- `removedVariableKeyGivesWarning`: the `addTask` lookup, the `title` check, the warnings lookup, and the `due` warning check. The finding asks to fold this test into `variableCases`, or into a case list of its own (its document has no rewrite; the removed key is in the value of the variable).
- `removedParameterGivesWarning`: the `errors` check, the `data[resultKey]` check, and the warning message and code checks.
- `cases`: the `due` warning text (`"`due`" + noDateText`) and the `page` warning text are also written in `variableCases`.

## Acceptance Criteria
- [ ] `removedVariableKeyGivesWarning` uses the shared helpers, or is a case of a case list.
- [ ] `removedParameterGivesWarning` uses `expectResult(at:in:)` and `expectRemovedWarning(_:in:)`.
- [ ] Each warning text is written one time in the file.

## Tests
- [ ] `swift test` passes.