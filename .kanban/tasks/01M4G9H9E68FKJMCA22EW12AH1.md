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
- actor: claude-code
  id: 01m4geqj8xb7p2wc6x2fr94md5
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD — engine: 0 findings (0 confirmed, 0 refuted), 4 source and test files reviewed, 4 .kanban files ignored by .reviewignore. Driver check of the commit message: 1 finding — 9bfb481 commit message has statements that are not true for the diff (old behavior made no conflict block; the task stays in column doing in this commit; the main fix "a hunk with no old lines applies only to the empty text" is not named). The 5 acceptance and test items agree with the diff: DiffApplyTests has the empty-body cases with and without a final newline, MergeTests has the two-branch merge test, ReplayTests has the two-log-line test. The implement record gives swift test 1054 tests in 74 suites passed.
    - next: reword the commit message of 9bfb481, then /review
  timestamp: 2026-10-09T13:48:05.789190+00:00
- actor: claude-code
  id: 01m4geqk4cch6vtnwk0948n5sq
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 4 files
    - test: green — swift test, 1054 tests in 74 suites passed
    - commit: 9bfb481
    - review: findings — 9bfb481 (commit message)
  timestamp: 2026-10-09T13:48:06.668912+00:00
- actor: claude-code
  id: 01m4gesnsxe2zrsqhatdnhe3fd
  text: |-
    Commit message of 9bfb481 reworded with `git commit --amend --only -m`. New HEAD 53362dd. Tree 8719d83 before and after, so the files did not change. The new message: (1) says that the old nearestMatch applied a hunk with no old lines at index 0 of any body, so two inserts into an empty body joined ("betaalpha", no conflict block); (2) names the main fix `HunkApplier.matches(_:withOldLines:at:)` (a hunk with no old lines applies only to the empty text; a hunk whose last new line has no final newline applies only at the end of the text; else replay writes a conflict block), plus `Hunk.endsWithoutNewline` and the `insertConflict` change; (3) names the 5 tests; (4) says only "Record the task files of ^ew12ah1 and ^tdybdkj", with no claim about columns. No code change and no other commit.

    ### implement — changed
    - evidence: HEAD 9bfb481 -> 53362dd (message only); `git show --stat HEAD` gives the same 8 files, 188 insertions, 19 deletions; tree 8719d83 unchanged.
    - next: /review
  timestamp: 2026-10-09T13:49:14.941059+00:00
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

## Review Findings (2026-10-09 08:45)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `9bfb481` `commit/message` (driver check of the commit message, not an engine validator) — The commit message of 9bfb481 has statements that are not true for its diff. (1) The body says "When a second insert met a body that was no longer empty, the conflict block held no current lines". Before this change, `nearestMatch` matched a hunk with no old lines at each index, so the hunk applied at index 0 and no conflict block was made. (2) The body says "Task ^ew12ah1 moves to review with its comments". In this commit, `.kanban/tasks/01M4G9H9E68FKJMCA22EW12AH1.jsonl` keeps the task in column `doing`. (3) The bullet list does not name the main fix: a hunk with no old lines now applies only to the empty text (`matches(_:withOldLines:at:)`). Reword the commit message so that each statement agrees with the diff, and name the main fix.