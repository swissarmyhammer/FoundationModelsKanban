---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m51hbjn5njrrdnj8f9q8kn5c
  text: 'Research: the change is only in Tests/FoundationModelsKanbanTests/GraphQL/RemovedParameterTests.swift. The helpers `expectResult(at:in:)` and `expectRemovedWarning(_:in:)` and the constant `dueWarning` are private static members of the suite. No other file calls them. The `due` text is in `cases` and in `dueWarning`. The `page` text is in `cases` and in the `page` case of `variableCases`. The `exclude_done`/`excludeDone` and `include_counts`/`INCLUDE_COUNTS` texts have the same tail; the plan is to name each tail as a constant, the same as `noDateText`. `removedVariableKeyGivesWarning` will use the helpers (not a case list), because a `RemovedVariableCase` also needs a rewritten text, and the test of the rewrite does not apply to this document. This is a change to tests only, so the existing tests are the check: they must stay green.'
  timestamp: 2026-10-16T05:01:04.037975+00:00
- actor: claude-code
  id: 01m51hk5mggjzc1j2c727p4zns
  text: |-
    ### implement — changed
    - evidence: 1 file, Tests/FoundationModelsKanbanTests/GraphQL/RemovedParameterTests.swift. `removedParameterGivesWarning` and `removedVariableKeyGivesWarning` now call `expectResult(at:in:)` and `expectRemovedWarning(_:in:)`. `removedVariableKeyGivesWarning` keeps its `title` check, and now also checks that there is no error and that the warning has its code. New constants: `excludeDoneText`, `includeCountsText`, `pageWarning`. `dueWarning` moved up to the other constants. `cases` uses `removedDue`, `dueWarning`, `pageWarning` and the two new tail constants; the `page` case of `variableCases` uses `pageWarning`. Each warning text is written one time. `swift test --filter RemovedParameterTests`: 11 tests in 1 suite passed. Full `swift test`: 1560 tests in 125 suites passed. The only build warning was the accepted SwiftPM "missing creator" warning.
    - next: /review
  timestamp: 2026-10-16T05:05:12.848818+00:00
- actor: claude-code
  id: 01m51hraafbwpz02m5t2x1v5dk
  text: |-
    ### test - green
    - evidence: swift build - Build complete, only the allowed SwiftPM "missing creator" warning. swift test (one full run) - Test run with 1560 tests in 125 suites passed after 44.762 seconds. 0 failures, 0 skipped, 0 compiler warnings. Log: scratchpad/test1.log.
    - note: the test log holds 2 runtime log lines that start with "warning". Tests that feed malformed log lines on purpose cause them ("Replay skips a log line that does not decode"). They are not build warnings.
    - next: review
  timestamp: 2026-10-16T05:08:01.487023+00:00
- actor: claude-code
  id: 01m51hs176x47769jhr4yy3qhp
  text: |-
    ### commit — changed
    - evidence: local commit of RemovedParameterTests.swift and the changed .kanban/tasks files. The sha is in the report of the commit step. No push.
    - next: review
  timestamp: 2026-10-16T05:08:24.934452+00:00
- actor: claude-code
  id: 01m51j2xyj9kb2h02gmfem9nsn
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (e0b96e1). 0 findings (0 confirmed, 0 refuted, 7 attempted, 0 failed). 1 file reviewed: Tests/FoundationModelsKanbanTests/GraphQL/RemovedParameterTests.swift. The .reviewignore rule excluded 4 .kanban files.
    - next: none. The task has no earlier findings. The task moved to done.
  timestamp: 2026-10-16T05:13:49.266508+00:00
- actor: claude-code
  id: 01m51j3fe7zf0fw8a0rzpykrjy
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — RemovedParameterTests.swift (shared helpers, warning text constants)
    - test: green — swift test, 1560 passed
    - commit: e0b96e1
    - review: clean — 0 findings
  timestamp: 2026-10-16T05:14:07.175606+00:00
position_column: done
position_ordinal: ff9280
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
- [x] `removedVariableKeyGivesWarning` uses the shared helpers, or is a case of a case list.
- [x] `removedParameterGivesWarning` uses `expectResult(at:in:)` and `expectRemovedWarning(_:in:)`.
- [x] Each warning text is written one time in the file.

## Tests
- [x] `swift test` passes.