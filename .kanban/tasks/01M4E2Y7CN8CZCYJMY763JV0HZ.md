---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4e72n96h9yncxyg5t7bt156
  text: |-
    Research:
    - `MoveTaskInput` holds `ordinal`, `before`, `after` as three optionals. The resolver uses `ordinal` first, then `TaskPlacement(before:after:)` takes `before` before `after`. No error for two fields.
    - No catalog code fits: `INVALID_VARIABLES` is for variables that are not a JSON object, `INVALID_ORDINAL` is for a bad fractional index. Plan: add `CONFLICTING_PLACEMENT` to `KanbanError` and plan.md §4.4.
    - Graphiti decodes the input inside the field resolve (`Field.swift`: `coders.decoder.decode(Arguments.self, ...)`), so an error from `init(from:)` becomes the error of the field, and the field writes nothing.
    - `InputField(_:at:)` needs a key path of the field type on the input type, so the schema needs `String?`/`NodeID?` key paths after the change to one `Placement` enum.
    - `addTask` has only `ordinal` (one place field). No other input has more than one place field. The tool description does not show `before`/`after`.
    - The existing test `moveTaskOrdinalTakesPrecedence` checks the old rule (ordinal wins over before). It conflicts with the new rule. It becomes a test for an ordinal alone.
    - The validator dump file is 750k characters; it is too large to read in one pass. I use the rule list from the caller.
  timestamp: 2026-10-08T16:55:51.846057+00:00
- actor: claude-code
  id: 01m4e7emx1erfcqjptk342pbxt
  text: |-
    Implementation notes:
    - RED: the new parameterized test `moveTaskConflictingPlacement` (4 cases: before+after, ordinal+before, ordinal+after, all three) failed on assertions before the change: the log changed (`nodeFileSignatures() == before`) and no error came back (`#require(error)` got nil).
    - GREEN: new code `CONFLICTING_PLACEMENT` (`KanbanError.conflictingPlacement(fields:)`). No existing code fit: `INVALID_VARIABLES` is for variables that are not a JSON object, `INVALID_ORDINAL` is for a bad fractional index.
    - New `private enum Placement { end, ordinal(String), before(NodeID), after(NodeID) }` decodes the three place fields and throws when more than one is set. `MoveTaskInput` holds one `placement`, so the bad state cannot reach the resolver. `TaskPlacement` is removed. `Graph.ordinal(placing:inColumn:moving:resolvingWith:)` switches on `Placement`.
    - Graphiti decodes the input inside the field resolver, so the error is the error of the field, and the field writes nothing.
    - `InputField(_:at:)` needs a key path of the field type, so `MoveTaskInput` keeps computed `ordinal`, `before`, `after` properties that read from `placement`. The schema uses them for the field types.
    - The old test `moveTaskOrdinalTakesPrecedence` checked the old rule (ordinal wins). It conflicted with the card; it is now `moveTaskToOrdinal` (an ordinal alone), so the one-field coverage stays.
    - `addTask` has only `ordinal`: no other input has more than one place field. The tool description does not show `before`/`after`, so it did not change.
    - plan.md: §4.2 `moveTask` row, §4.4 code list and one rule line, §6 `moveTask` rule.
    - KanbanErrorTests: the code table has the new case; the test name says seventeen codes.
    - periphery (`periphery scan --retain-public --report-exclude 'Tests/**' --relative-results -- --build-system native --build-tests`): No unused code detected.
  timestamp: 2026-10-08T17:02:24.673477+00:00
- actor: claude-code
  id: 01m4e7eq80b2729t86s47xz6we
  text: |-
    ### implement — changed
    - evidence: Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift, Sources/FoundationModelsKanban/GraphQL/Errors.swift, Tests/FoundationModelsKanbanTests/Mutations/TaskOperationTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/KanbanErrorTests.swift, plan.md. Error code CONFLICTING_PLACEMENT. `swift build --build-tests`: only the accepted mlx "missing creator" warning. `swift test --skip-build` 3 runs: 985 tests in 68 suites passed each time (8.05 s, 8.17 s, 7.77 s). periphery: no unused code.
    - next: /review
  timestamp: 2026-10-08T17:02:27.072044+00:00
- actor: claude-code
  id: 01m4e7p65a8md9y6bp2b809tsb
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (1da94b0); 1 finding, 1 confirmed, 0 refuted — Tests/FoundationModelsKanbanTests/Mutations/TaskOperationTests.swift:215 (reuse/reuse)
    - next: Correct the finding in the Review Findings (2026-10-08 12:05) section. The task stays in review.
  timestamp: 2026-10-08T17:06:31.722542+00:00
- actor: claude-code
  id: 01m4e7pf1ebmmzvb0mmfpaspde
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — TaskOperationMutations.swift, Errors.swift, TaskOperationTests.swift, KanbanErrorTests.swift, plan.md; new code CONFLICTING_PLACEMENT
    - test: green — swift test 3 runs, 985 passed each (8.0 s, 8.0 s, 7.9 s); build warnings only the 2 accepted kinds
    - commit: 1da94b0
    - review: findings — Tests/FoundationModelsKanbanTests/Mutations/TaskOperationTests.swift:215
  timestamp: 2026-10-08T17:06:40.814207+00:00
- actor: claude-code
  id: 01m4e7thscx1jheetwq5f3xadc
  text: |-
    Finding fix (reuse/reuse, TaskOperationTests.swift conflictingPlacementMessage):
    - I removed the helper `conflictingPlacementMessage(naming:)`. It built the message again with `joined(separator: ", ")` and a copy of the correction text.
    - Each case of `conflictingPlacements` is now a pair: the place fields and the literal first sentence of the message (for example "The input gives more than one place field: ordinal, before. "). The correction sentence is one literal constant `conflictingPlacementCorrection`. The test compares `error.message` with the literal first sentence plus that literal. The text is pinned; no production code builds the expected value, and no `", "` join stays.
    - I did not use `KanbanError.conflictingPlacement(fields:).message`: that compares the production code with itself, so a change of the wording does not fail the test.
    - The other error tests in the file compare `KanbanError` values (`error == .notFound(...)` and others). No other helper builds a production message again.
    - The assertions are the same: the code check and the full message check for 4 cases.
  timestamp: 2026-10-08T17:08:54.700637+00:00
- actor: claude-code
  id: 01m4e7tkb1qxy5prcph8h5bzjh
  text: |-
    ### implement — changed
    - evidence: Tests/FoundationModelsKanbanTests/Mutations/TaskOperationTests.swift. `swift build --build-tests`: only the accepted mlx "missing creator" warning. `swift test --skip-build` 3 runs: 985 tests in 68 suites passed each time (7.90 s, 7.81 s, 7.99 s); the CONFLICTING_PLACEMENT test passed with 4 cases. Finding marked [x].
    - next: /review
  timestamp: 2026-10-08T17:08:56.289079+00:00
- actor: claude-code
  id: 01m4e821159763nvgrfzqq54n6
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (e498add). 0 findings, 0 confirmed, 0 refuted, 7 attempted, 0 failed. All items of the prior Review Findings (2026-10-08 12:05) section are checked.
    - next: none. The task is in done.
  timestamp: 2026-10-08T17:12:59.685901+00:00
- actor: claude-code
  id: 01m4e828z3j1yrw0z68fhpsmyq
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 1 test file (Mutations/TaskOperationTests.swift); 1/1 findings checked
    - test: green — swift test 3 runs, 985 passed each (8.4 s, 7.8 s, 7.9 s); build warnings only the 2 accepted kinds
    - commit: e498add
    - review: clean — 0 findings
  timestamp: 2026-10-08T17:13:07.811165+00:00
position_column: done
position_ordinal: bf80
title: 'moveTask: error when the input gives both before and after'
---
## What
A person said on 2026-10-08: "both before and after at the same time is nonsense". Today `moveTask` takes the first of `ordinal`, `before`, `after`, and ignores the others with no error (`Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift`, `MoveTaskInput` and `TaskPlacement.init(before:after:resolvingWith:)`).

- When a `moveTask` input gives more than one place field (`ordinal`, `before`, `after`), the mutation fails with an error. It writes nothing. The message names the fields that it got, and it tells the caller to give only one.
- Use an existing code of the error catalog (`Errors.swift`, plan.md §4.4) if one fits (for example the code for a bad input). If none fits, add one, and add it to plan.md §4.4.
- Apply the same rule to every other input that has place fields (for example `addTask`, if it takes `ordinal` together with another place field).
- Update plan.md §4.2 (`moveTask`) and the tool description if it shows `before`/`after`.

## Acceptance Criteria
- [x] `moveTask` with `before` and `after` gives the error and writes no event; the same for `ordinal` with `before` or `after`.
- [x] `moveTask` with one place field, or none, works as before.

## Tests
- [x] Add tests in the `moveTask` test suite for each pair of place fields, and check that the log has no new line.
- [x] Run the full `swift test`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-08 12:05)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/Mutations/TaskOperationTests.swift:215` `reuse/reuse` — conflictingPlacementMessage rebuilds the production message of KanbanError.conflictingPlacement by joining the fields and repeating the correction text. The test therefore carries a second copy of the message wording, which must change in two places whenever the wording changes. Compare the error's message with the expected string in the test. For example, assert that error.message equals the literal text, as KanbanErrorTests does for other messages. Or, if the helper stays, have it call KanbanError.conflictingPlacement(fields: fields).message, so the wording lives in one place. Use KanbanError.listSeparator instead of the literal ", ".
