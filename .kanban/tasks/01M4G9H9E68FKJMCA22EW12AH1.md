---
assignees:
- claude-code
position_column: todo
position_ordinal: '8380'
title: 'Body diff: two inserts into an empty body must not join lines'
---
## What
`Sources/FoundationModelsKanban/Body/DiffApply.swift:113-121` (`nearestMatch`) and `:159-161` (`oldOffset`). A hunk from an empty text has no context lines and no `-` lines, so it matches at each position and goes in at index 0. When the inserted last line has no final newline, `TextLine.text(joining:)` puts it directly before the next line.

Scenario (plan.md §5.5): branch A sets the empty body of a task to `alpha`, branch B sets it to `beta`, both with no final newline. After a `union` merge, replay gives `betaalpha` and no `CONFLICT` tag.

- Fix: a hunk whose old side is empty (`@@ -0,0 +1,n @@`) applies only when the current text is empty. In other cases it is a hunk that cannot apply, so replay writes the git-style conflict block and the virtual tag `CONFLICT` (§5.5, §12 item 19).
- Also check that an insert never joins a line without a newline to the next line: when the inserted text has no final newline and a line follows, add the newline or treat the hunk as a conflict.

## Acceptance Criteria
- [ ] The merge scenario above gives a body with a conflict block that holds `alpha` and `beta` on separate lines, and the task has `CONFLICT`.
- [ ] One empty-to-text diff on an empty body still applies with no conflict.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Body/DiffApplyTests.swift`: regression tests for the two cases above, with and without a final newline.
- [ ] A merge test (in the existing merge tests, for example `Tests/FoundationModelsKanbanTests/Events/`) with two log lines for the same task body.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.