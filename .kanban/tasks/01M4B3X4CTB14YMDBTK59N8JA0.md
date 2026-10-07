---
comments:
- actor: wballard
  id: 01m4b6f0k8q1z55hjhex15qmff
  text: |-
    Research done.
    - UnifiedDiff.swift gives Hunk (oldStart, oldLines, newLines, oldCount) and TextLine (content, hasNewline). The oldStart rule is git's: for an empty old range it is the line before the range.
    - UnifiedDiffTests.swift has ExactApply (test-only, exact line numbers), RandomText, and SplitMix64. The new tests can use RandomText and SplitMix64 for the determinism property.
    - No event id type exists yet (the event model task is still in todo). Thus the apply takes the conflict label (the event id) as a String.
    - Design: `UnifiedDiff.applied(to:conflictLabel:) -> AppliedBody` (text, hasConflict). The search is in the lines of the input text. Each hunk searches from the end of the previous hunk. It starts at its line number plus the offset of the previous match (as GNU patch does). The nearest exact match wins; at equal distance the earlier line wins. A hunk with no match replaces the current lines at its position with a conflict block. hasConflict scans the result for a full block, so a later edit that removes the block clears it.
  timestamp: 2026-10-07T12:47:24.776230+00:00
- actor: wballard
  id: 01m4b6k9jbb8077jsxjwktcsrn
  text: |-
    Implementation landed (TDD: the RED build failed because `applied(to:conflictLabel:)` and `AppliedBody` did not exist; then GREEN).
    - New `Sources/FoundationModelsKanban/Body/DiffApply.swift`: `AppliedBody` (text, hasConflict), `UnifiedDiff.applied(to:conflictLabel:)`, the private `HunkApplier`, `UnifiedDiff.Hunk.oldOffset`, and `UnifiedDiff.ConflictBlock` (marker constants, `lines(current:wanted:label:)`, `isPresent(in:)`).
    - New `Tests/FoundationModelsKanbanTests/Body/DiffApplyTests.swift`: 13 tests. They cover exact apply, shifted apply (lines added and lines removed before the hunk), nearest match, merge in either order, the conflict block text, a block at the end of a text with no final newline, later hunks after a conflict, resolution clears hasConflict, a partial block is no conflict, and a determinism property over 500 random texts.
    - Decisions for the next agent: each line of a conflict block ends with a newline, also at the end of a text with no final newline. Thus a hunk that wanted no final newline loses that state in the block. The conflict label is a String, because no event id type exists yet. The replay task (^xb2p4ck's dependent) can pass the event id text. hasConflict scans the result, so the replay can use the value of the last apply for the CONFLICT tag.
    - The test helper `ExactApply` in UnifiedDiffTests.swift has the same old-offset rule as the new `Hunk.oldOffset`. I did not change that existing test code.
  timestamp: 2026-10-07T12:49:45.035165+00:00
- actor: wballard
  id: 01m4b6keggmy5ta3trjk8zxtg7
  text: |-
    ### implement — changed
    - correction: the previous comment names the replay task incorrectly. The replay task is ^zwd88dr ("Replay: fold the events of one node"). It can pass the event id text as `conflictLabel`.
    - evidence: 2 new files — Sources/FoundationModelsKanban/Body/DiffApply.swift, Tests/FoundationModelsKanbanTests/Body/DiffApplyTests.swift. `swift test --filter DiffApplyTests`: 13 tests passed. `swift test`: 47 tests in 4 suites passed. `swift build --build-tests`: 0 warnings. swiftlint (no_magic_numbers, missing_docs, function_body_length) on the 2 files: 0 findings.
    - next: /review
  timestamp: 2026-10-07T12:49:50.096031+00:00
depends_on:
- 01M4B3W5TJ921MJFG9AQ8B0QQR
position_column: doing
position_ordinal: '80'
title: 'Body diff: apply with nearest match and conflict block'
---
## What
Apply a stored diff to a body during replay. The basis is plan.md §5.5.
- `Sources/FoundationModelsKanban/Body/DiffApply.swift`: apply each hunk in order. A hunk applies at its line number if its context and `-` lines match there. If not, find the nearest position where they match exactly (no fuzz).
- A hunk that cannot apply: insert a git-style conflict block at the hunk position: `<<<<<<< current` / the current lines / `=======` / the lines that the hunk wanted / `>>>>>>> <event id>`.
- Report whether the result has a conflict block (the `CONFLICT` virtual tag uses it later).
- The result depends only on the input, so all clones give the same text.

## Acceptance Criteria
- [x] Two diffs made from the same base that change different lines both apply, in either order.
- [x] Two diffs that change the same line give exactly one conflict block with the event id.
- [x] The same inputs always give the same output.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Body/DiffApplyTests.swift`: exact apply, shifted apply, conflict, determinism.
- [x] Run `swift test --filter DiffApplyTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.