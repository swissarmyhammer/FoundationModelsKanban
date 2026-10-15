---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4z87dgy4p49thga0x6j564z
  text: |-
    Research done.
    - `FieldUpdate` (S/GraphQL/MutationResolvers.swift) reads `null` as `.cleared`; `PatchInput(changing:updating:...)` writes `.cleared` as an `unset`. The four required text fields pass `.cleared` straight through: `updateTask` title (TaskMutations.swift), `updateColumn` and `updateActor` name (ColumnActorMutations.swift), `updateTag` name (TagMutations.swift, through `map` of `TagName`).
    - Plan: add `FieldUpdate.ignoringNull` (`.cleared` gives `.unchanged`) and one warning with a new code `NULL_IGNORED` in `extensions.warnings`, so that the agent knows the call ignored the `null` (public-output-contract rule: do not silence a condition). The four resolvers use it. A patch with no change is not written, so `title: null` alone writes nothing.
    - Optional fields (`body`, `color`, `order`, lists) keep "`null` clears the field". The tests `updateTaskClearsBody(null)` and `updateActorNullColorUnsetsColor` already prove that.
    - Test helper to reuse: `DependencyTargetWarningTests.expectWarning(coded:naming:in:)`, `ColumnActorTests.respondWritingNothing(to:after:in:)`.
  timestamp: 2026-10-15T07:43:01.662406+00:00
- actor: claude-code
  id: 01m4z8fyndcfqc7699rkgah2ev
  text: |-
    Implementation landed (TDD: RED run showed name/title "" and no extensions; GREEN run 5/5 pass).
    - New file S/GraphQL/IgnoredNull.swift: `IgnoredNull.warningCode = "NULL_IGNORED"`, `IgnoredNull.warnings(of:forField:of:)`, `FieldUpdate.ignoringNull` (`.cleared` gives `.unchanged`), and `KanbanContext.warnIfNull(_:forField:of:)`.
    - `updateTask` title, `updateColumn` name, `updateActor` name, `updateTag` name write `ignoringNull`, and add one `NULL_IGNORED` warning in `extensions.warnings` after the field succeeds. A field that fails adds no warning. `title: null` alone writes no patch.
    - `FieldUpdate.isCleared` changed from fileprivate to internal, for reuse.
    - Doc comments of the four update inputs and of `FieldUpdate` tell the rule.
    - Tests: replaced `updateTaskNullTitle` and `updateColumnNullNameUnsetsName`; added `updateTaskNullTitleClearsNullBody` (title kept, null body still clears), `updateActorNullNameKeepsName`, `updateTagNullNameKeepsName`; shared helper `ColumnActorTests.expectIgnoredNull(of:keeping:inField:of:)`.
    - Not changed: board `name` null in `initBoard`/`updateBoard` still clears; the card does not list it.
    - Full `swift test`: 1385 tests in 109 suites pass; only the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-15T07:47:41.357512+00:00
- actor: claude-code
  id: 01m4z8g1brkbvjv3af39y2sdqs
  text: |-
    ### implement — changed
    - evidence: 8 files — Sources/FoundationModelsKanban/GraphQL/IgnoredNull.swift (new), Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift, Sources/FoundationModelsKanban/GraphQL/ColumnActorMutations.swift, Sources/FoundationModelsKanban/GraphQL/TagMutations.swift, Sources/FoundationModelsKanban/GraphQL/MutationResolvers.swift, Tests/FoundationModelsKanbanTests/Mutations/AddUpdateTaskTests.swift, Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift, Tests/FoundationModelsKanbanTests/Mutations/TagMutationTests.swift; `swift test` 1385 tests pass
    - next: /review
  timestamp: 2026-10-15T07:47:44.120196+00:00
position_column: doing
position_ordinal: '80'
title: Ignore null on a required text field in update mutations
---
## What
divergence.md Q17 (DECIDED: ignore it, as Rust does), O4, and §11 "Q17". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem (O4): `null` clears `title` and the column `name`, and they then read as `""`. The same path also clears the actor `name` (S/GraphQL/ColumnActorMutations.swift:114) and the tag `name` (S/GraphQL/TagMutations.swift:53,130-132).

Decided behavior: `null` on a required text field means "no change". The call works, and the field keeps its value. The required text fields are: task `title`, column `name`, actor `name`, tag `name`. Other optional fields keep the rule "`null` clears the field".

Change the update mutations in S/GraphQL/TaskMutations.swift, S/GraphQL/ColumnActorMutations.swift (column and actor `name`), and S/GraphQL/TagMutations.swift (tag `name`).

## Acceptance Criteria
- [x] `updateTask(input: {id: ..., title: null})` works and the title does not change.
- [x] The same for column `name`, actor `name`, and tag `name`.
- [x] `null` on an optional field (for example `body`) still clears it.

## Tests
- [x] Change the tests T/Mutations/AddUpdateTaskTests.swift:651-660 and T/Mutations/ColumnActorTests.swift:382-390 to the new rule.
- [x] Add tests for actor `name` and tag `name`.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.