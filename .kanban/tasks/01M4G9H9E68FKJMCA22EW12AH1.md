---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4geayb00s8w1cgf2mgam5ts
  text: |-
    Research done.
    - `HunkApplier.nearestMatch` in `Body/DiffApply.swift` compares only the old lines. A hunk with no old lines matches at each index, so the nearest index (0) wins and the new lines go in before the current text.
    - A hunk whose last new line has no final newline can also join lines when other lines follow the matched range. Example: the diff `"a\n"` -> `"a"` applied to `"a\nb\n"` gives `"ab\n"`.
    - `applies(exactlyTo:)` (used by undo, plan.md §6.5) uses the same applier, so the fix also changes the undo conflict check.
    - The fixture task of `Design/MergeTests` has an empty body, so a branch test can set the body on each branch. `Events/ReplayTests` can fold two edit lines from the empty body.
    Plan: a hunk matches at a position only when (1) its old side is not empty, or the text is empty, and (2) its last new line has a newline, or the matched range ends at the end of the text. A hunk with an empty old side that cannot apply puts all current lines into the conflict block.
  timestamp: 2026-10-09T13:41:12.160592+00:00
- actor: claude-code
  id: 01m4geg3jamk1xxk1k0qyanmwx
  text: |-
    Implementation landed (TDD: 5 new tests failed first, for the correct reason, then passed).
    - `HunkApplier.matches(_:withOldLines:at:)` is new. A hunk matches at a position only when its old lines are equal there, AND (its old side is not empty, or the text is empty), AND (its last new line has a final newline, or the match ends at the end of the text).
    - `insertConflict` puts all current lines after the cursor into the current side of the block for a hunk with an empty old side. Thus `alpha` and `beta` are both in the block.
    - New `Hunk.endsWithoutNewline`.
    - Choice for the open behavior "add the newline or treat the hunk as a conflict": the hunk is a conflict. Reason: plan.md §5.5 applies a hunk only where it matches exactly, and a conflict block is the §5.5 result for a hunk that cannot apply. To add a newline would change the text that the agent wrote.
    - `applies(exactlyTo:)` (undo conflict check) uses the same rules, so a reversed diff to the empty text also is an undo conflict on a body that is not empty.
  timestamp: 2026-10-09T13:44:01.354173+00:00
- actor: claude-code
  id: 01m4geg5b0kdycsg3ww31yfn9x
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/Body/DiffApply.swift, Tests/FoundationModelsKanbanTests/Body/DiffApplyTests.swift, Tests/FoundationModelsKanbanTests/Events/ReplayTests.swift, Tests/FoundationModelsKanbanTests/Design/MergeTests.swift. `swift test`: 1054 tests in 74 suites passed, 0 failures; only the accepted SwiftPM "missing creator for mutated node" warning.
    - next: /review
  timestamp: 2026-10-09T13:44:03.168061+00:00
position_column: doing
position_ordinal: '80'
title: 'Body diff: two inserts into an empty body must not join lines'
---
## What
`Sources/FoundationModelsKanban/Body/DiffApply.swift:113-121` (`nearestMatch`) and `:159-161` (`oldOffset`). A hunk from an empty text has no context lines and no `-` lines, so it matches at each position and goes in at index 0. When the inserted last line has no final newline, `TextLine.text(joining:)` puts it directly before the next line.

Scenario (plan.md §5.5): branch A sets the empty body of a task to `alpha`, branch B sets it to `beta`, both with no final newline. After a `union` merge, replay gives `betaalpha` and no `CONFLICT` tag.

- Fix: a hunk whose old side is empty (`@@ -0,0 +1,n @@`) applies only when the current text is empty. In other cases it is a hunk that cannot apply, so replay writes the git-style conflict block and the virtual tag `CONFLICT` (§5.5, §12 item 19).
- Also check that an insert never joins a line without a newline to the next line: when the inserted text has no final newline and a line follows, add the newline or treat the hunk as a conflict.

## Acceptance Criteria
- [x] The merge scenario above gives a body with a conflict block that holds `alpha` and `beta` on separate lines, and the task has `CONFLICT`.
- [x] One empty-to-text diff on an empty body still applies with no conflict.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Body/DiffApplyTests.swift`: regression tests for the two cases above, with and without a final newline.
- [x] A merge test (in the existing merge tests, for example `Tests/FoundationModelsKanbanTests/Events/`) with two log lines for the same task body.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.