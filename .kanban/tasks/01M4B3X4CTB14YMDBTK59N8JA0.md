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
- actor: wballard
  id: 01m4b6wx6mxng1zcatk8c1wpdj
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD; 1 finding (1 confirmed, 0 refuted) — Sources/FoundationModelsKanban/Body/DiffApply.swift:36 (swift/fluent-usage)
    - next: change the argument label `conflictLabel` to `withConflictLabel` at the declaration and at all call sites, then review again.
  timestamp: 2026-10-07T12:55:00.052455+00:00
- actor: wballard
  id: 01m4b6x60kq5z9c6mx8cmvbttp
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 2 files (DiffApply.swift, DiffApplyTests.swift)
    - test: green — swift test, 47 passed, 0 warnings
    - commit: 3d545b0
    - review: findings — Sources/FoundationModelsKanban/Body/DiffApply.swift:36
  timestamp: 2026-10-07T12:55:09.075162+00:00
- actor: wballard
  id: 01m4b70erkz7agp4vrcn7qtjkb
  text: |-
    Finding fix landed.
    - `applied(to:conflictLabel:)` is now `applied(to text: String, withConflictLabel conflictLabel: String)`. All 23 call sites in DiffApplyTests.swift use `withConflictLabel:`.
    - Same cause in the file: `ConflictBlock.lines(current:wanted:label:)` had noun labels with no preposition. It is now `lines(between current:, and wanted:, withLabel label:)`. Its only caller is `HunkApplier.insertConflict`. The doc `- Parameters` keys keep the internal names (current, wanted, label, conflictLabel), as the doc-comment rule requires.
    - Other labels in the file (`nearestMatch(of:near:)`, `insertConflict(for:near:)`, `replace(_:with:)`, `isPresent(in:)`, memberwise init labels) already have a preposition or are init labels. I did not change them.
    - TDD: RED was the test build that failed with "incorrect argument label (have 'to:withConflictLabel:', expected 'to:conflictLabel:')". Then GREEN.
    - The longer label made the line in `partialBlockIsNoConflict` 124 characters (swiftlint line_length 120). I split it into a `diff` constant and an apply line.
    - Tool note: the `files` tool `edit file` with `replace_all: true` replaced only one match per call. I wrote the full test file instead, and `git diff --word-diff` showed only label changes.
  timestamp: 2026-10-07T12:56:56.339656+00:00
- actor: wballard
  id: 01m4b70gn6g79w08hrbjyydh3h
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsKanban/Body/DiffApply.swift, Tests/FoundationModelsKanbanTests/Body/DiffApplyTests.swift. `swift build --build-tests`: 0 warnings, 0 errors. `swift test`: 47 tests in 4 suites passed. swiftlint on the 2 files: 0 findings. Finding DiffApply.swift:36 swift/fluent-usage is checked.
    - next: /review
  timestamp: 2026-10-07T12:56:58.278646+00:00
- actor: wballard
  id: 01m4b73zfj57cw0enycypaskv1
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (4283171) — 0 findings, 7 validator runs, 0 failed. The prior finding at DiffApply.swift (swift/fluent-usage) is checked.
    - next: none. The task is in done.
  timestamp: 2026-10-07T12:58:51.762028+00:00
- actor: wballard
  id: 01m4b747rej3sq0zcvn5jdm8bv
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 2 files (DiffApply.swift, DiffApplyTests.swift), 1/1 finding fixed
    - test: green — swift test, 47 passed, 0 warnings
    - commit: 4283171
    - review: clean — 0 findings
  timestamp: 2026-10-07T12:59:00.238258+00:00
depends_on:
- 01M4B3W5TJ921MJFG9AQ8B0QQR
position_column: done
position_ordinal: '8380'
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

## Review Findings (2026-10-07 07:50)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/Body/DiffApply.swift:36` `swift/fluent-usage` — The argument label `conflictLabel` is a noun instead of a preposition or descriptor, violating the fluent-usage rule. The call site reads `diff.applied(to: text, conflictLabel: label)`, which reads ungrammatically as 'applied to text, conflictLabel label' rather than forming a fluent phrase. Change the argument label from a noun to a preposition-based descriptor: `func applied(to text: String, withConflictLabel conflictLabel: String) -> AppliedBody`. This makes the call site read fluently as 'applied to text, with conflict label'. Update all call sites in the test file to use `withConflictLabel:` instead of `conflictLabel:`.
