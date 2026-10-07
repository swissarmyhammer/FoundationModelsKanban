---
comments:
- actor: wballard
  id: 01m4b5rta0fdz2yw9cxwj5r4ft
  text: |-
    Research:
    - No Body/ directory exists yet. Tests use Swift Testing with `@testable import FoundationModelsKanban`, so the diff types can stay `internal`.
    - Plan: one value type `UnifiedDiff` (hunks) with `init(from:to:)` (CollectionDifference over lines), `init(parsing:) throws`, `text`, and `reversed()`. A line of text keeps its final-newline state, so that a change of only the final newline shows as `-x` / `\ No newline at end of file` / `+x`, as git does.
    - Split text on the Unicode scalar "\n", not on Character: Swift reads "\r\n" as one Character, so a Character split does not find a CRLF line end.
    - Hunk header uses the git rule: a range with count 0 gives the line before it as start (`@@ -0,0 +1,3 @@` for a diff from empty text). Counts are always written (plan.md example `@@ -3,1 +3,2 @@`).
    - The later task ^59n8ja0 (DiffApply) uses the parsed hunks and the text line split.
    - Validators: periphery dead code (tests count as callers), swiftlint no_magic_numbers (name the context size 3), no top-level func, no force unwrap.
  timestamp: 2026-10-07T12:35:17.440856+00:00
- actor: wballard
  id: 01m4b60sp0jhgkwkdjvr29wp5z
  text: |-
    Implementation landed (TDD: RED was a build failure for the missing `UnifiedDiff` type; then GREEN).
    - `UnifiedDiff` (internal value type): `init(from:to:)`, `init(parsing:) throws`, `text`, `reversed()`. Nested `TextLine` (`lines(in:)`, `text(joining:)`), `Line` (kind raw value is the marker), `Hunk` (`oldStart`, `newStart`, `lines`, `oldLines`, `newLines`, counts, `header`). `UnifiedDiffError`: `malformedHeader`, `malformedLine`, `truncatedHunk`, `countMismatch`.
    - Two changes merge into one hunk when at most 6 unchanged lines are between them (the context lines touch), as git does.
    - `reversed()` puts the `-` lines before the `+` lines in each run of changes, so `reversed().reversed()` equals the original diff.
    - The parser accepts a header range with no count (`-2` means count 1) and text after the second `@@`, as git writes.
    - For ^59n8ja0 (DiffApply): use `Hunk.oldLines` / `Hunk.newLines` to match and replace, and `TextLine.lines(in:)` / `TextLine.text(joining:)` to split and join the body. An insert-only hunk (`oldCount == 0`) has `oldStart` = the line before the insert position.
  timestamp: 2026-10-07T12:39:38.944858+00:00
- actor: wballard
  id: 01m4b60v7zn7sd7cej19r9vgg0
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsKanban/Body/UnifiedDiff.swift, Tests/FoundationModelsKanbanTests/Body/UnifiedDiffTests.swift. `swift test --filter UnifiedDiffTests`: 21 tests passed (the property test checks 500 random text pairs). `swift test`: 34 tests in 3 suites passed, 0 warnings.
    - next: /review
  timestamp: 2026-10-07T12:39:40.543273+00:00
- actor: wballard
  id: 01m4b66kmmt57dv56bc82byjf2
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD; 3 findings (3 confirmed, 0 refuted) — Sources/FoundationModelsKanban/Body/UnifiedDiff.swift:19, Sources/FoundationModelsKanban/Body/UnifiedDiff.swift:355, Sources/FoundationModelsKanban/Body/UnifiedDiff.swift:356
    - next: Correct each finding in the Review Findings section. Remove each cause from the full file. Then do the review again.
  timestamp: 2026-10-07T12:42:49.364266+00:00
- actor: wballard
  id: 01m4b66wkgf3gq84vfrjy9wam8
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 2 files (UnifiedDiff.swift, UnifiedDiffTests.swift)
    - test: green — swift test, 34 passed, 0 warnings
    - commit: ca19d2e
    - review: findings — Sources/FoundationModelsKanban/Body/UnifiedDiff.swift:19, :355, :356
  timestamp: 2026-10-07T12:42:58.544203+00:00
- actor: wballard
  id: 01m4b68pj6k9pyem8bnb83zkyc
  text: |-
    Review findings corrected in Sources/FoundationModelsKanban/Body/UnifiedDiff.swift:
    - magic-numbers-swift: `largestMergedGap` is now `contextLineCount + contextLineCount` (the context after the first change and the context before the second change). Before, it was `contextLineCount * 2`. `swiftlint` with only `no_magic_numbers` now gives 0 findings for the full file.
    - idioms-swift (UseLetInEveryBoundCaseVariable): `offset(of:)` now uses `case .insert(let offset, _, _)` and `case .remove(let offset, _, _)`. No other `case let` pattern is in the file. `swift format lint` gives 0 UseLetInEveryBoundCaseVariable findings. Note: `swift format lint` with no project config also gives Indentation findings (default is 2 spaces); the project has no .swift-format file, and the review did not report them.
    - No behavior change; the tests that exist cover both code paths.
  timestamp: 2026-10-07T12:43:57.894604+00:00
- actor: wballard
  id: 01m4b68qpgdtrfka1y83v5pp0t
  text: |-
    ### implement — changed
    - evidence: 1 file — Sources/FoundationModelsKanban/Body/UnifiedDiff.swift. `swift build --build-tests`: 0 warnings. `swift test`: 34 tests in 3 suites passed. 3 of 3 findings checked.
    - next: /review
  timestamp: 2026-10-07T12:43:59.056153+00:00
- actor: wballard
  id: 01m4b6bmzrvsgqvp885k3894nw
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (1935328). 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. All 3 items in the prior Review Findings section are checked.
    - next: none. The task is in done.
  timestamp: 2026-10-07T12:45:34.584414+00:00
- actor: wballard
  id: 01m4b6bz4d48zxytyj9z2bqxfh
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 1 file (UnifiedDiff.swift), 3/3 findings fixed
    - test: green — swift test, 34 passed, 0 warnings
    - commit: 1935328
    - review: clean — 0 findings
  timestamp: 2026-10-07T12:45:44.973191+00:00
depends_on:
- 01M4B3V22A3PCQRESESTYBQ2FH
position_column: done
position_ordinal: '8280'
title: 'Body diff: make and reverse a unified diff'
---
## What
Make the diffs that the log stores for a body. The basis is plan.md §5.5.
- `Sources/FoundationModelsKanban/Body/UnifiedDiff.swift`: make a line-based unified diff from text A to text B with Swift `CollectionDifference`. No `---`/`+++` header lines. Each hunk has `@@ -a,b +c,d @@` and 3 lines of context. Use `\ No newline at end of file` as git does.
- Reverse a diff: the `-` and `+` lines change places, and the hunk header ranges change places.
- Parse a diff string into hunks (the apply step in a later task uses it).
- The same input always gives the same output.

## Acceptance Criteria
- [x] Apply(make(A, B)) to A gives B, for random A and B (use a simple exact apply in the test).
- [x] Apply(reverse(make(A, B))) to B gives A.
- [x] A diff from the empty text holds all lines of B as `+` lines.
- [x] Text with and without a final newline round-trips.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Body/UnifiedDiffTests.swift`: fixed cases plus a property test.
- [x] Run `swift test --filter UnifiedDiffTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-07 07:40)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/Body/UnifiedDiff.swift:19` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.
- [x] `Sources/FoundationModelsKanban/Body/UnifiedDiff.swift:355` `code-hygiene/idioms-swift` — UseLetInEveryBoundCaseVariable: move this 'let' keyword inside the 'case' pattern, before each of the bound variables.
- [x] `Sources/FoundationModelsKanban/Body/UnifiedDiff.swift:356` `code-hygiene/idioms-swift` — UseLetInEveryBoundCaseVariable: move this 'let' keyword inside the 'case' pattern, before each of the bound variables.
