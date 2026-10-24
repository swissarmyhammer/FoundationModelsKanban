---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5nt9c27mw3t9sscjst4sexw
  text: |-
    Research done. Findings:
    - FoundationModelsExtras (already a dependency) gives `FrontmatterDocument.split(text:)` (a text split at the `---` fences, CRLF safe) and `YAMLValue.parse(_:)` (Yams under it, with `YAMLValueParsingError`). No new package dependency is necessary.
    - The write keeps the other keys: a line edit of the frontmatter text replaces or removes only the `trigger:` and `next:` lines. A YAML re-encode would lose the key order and the comments.
    - `ColumnObject.trackedFields` (ChangeBuilder.swift) gives the fields of a `changes` update. Add `trigger` and `next` there. The `NodeUpdate.fields` description lists the tracked fields, so it changes too.
    - Warnings from sync code go through `ResolverWarnings.current?.add(...)` (the same as the NEIGHBOR_NOT_FOUND warning).
    - Input aliases are in `KanbanFieldAliases.byType` by input type name.
  timestamp: 2026-10-24T02:01:57.575220+00:00
- actor: claude-code
  id: 01m5nv8edtncz99qgf6dkfeyc8
  text: |-
    Implementation landed (TDD: each new test failed first).
    - New `Body/ColumnTrigger.swift`: reads `trigger` and `next` from the frontmatter (Extras `FrontmatterDocument.split` + `YAMLValue.parse`), gives `Problem` (invalidYAML(line:), notAMapping, invalidValue(key:)) and the warning `INVALID_COLUMN_FRONTMATTER`. The write `ColumnTrigger.body(_:settingSkill:next:)` edits only the key lines.
    - New `Body/FrontmatterLines.swift`: line edit of one top-level key; keeps the other keys, their order and comments, and the text after the frontmatter.
    - `Column.trigger: String`, `Column.next: Boolean!`; both are tracked fields of `NodeUpdate.fields`. `trigger`/`next` in `AddColumnInput` and `UpdateColumnInput`, with aliases (skill, triggerSkill, onEnter, onEntry / autoAdvance, advance, moveNext, goNext).
    - The warning comes only on a call that gives body, trigger, or next (through `ResolverWarnings.current`). The write is never refused.
    - Discovery: Yams reports an unclosed flow sequence at the end of the input, not at the key line. The tests use `trigger: do: now` for a bad YAML on a known line.
    - Docs: divergence.md §22, schema descriptions, tool description with a tested example (`KanbanTool.columnTriggerExample`), SDL golden recorded.
  timestamp: 2026-10-24T02:18:55.802989+00:00
- actor: claude-code
  id: 01m5nv8evpt02ek5d42ybmzrf2
  text: |-
    ### implement — changed
    - evidence: `swift test` 1816 tests in 152 suites passed, only the accepted SwiftPM "missing creator" warning. Files: Sources/FoundationModelsKanban/Body/ColumnTrigger.swift (new), Sources/FoundationModelsKanban/Body/FrontmatterLines.swift (new), GraphQL/ColumnActorMutations.swift, GraphQL/FieldAliases.swift, GraphQL/MutationResolvers.swift, GraphQL/QueryResolvers.swift, GraphQL/Schema.swift, GraphQL/SchemaDescription+Changes.swift, GraphQL/SchemaDescription+Mutations.swift, GraphQL/SchemaDescription+Types.swift, Observe/ChangeBuilder.swift, Tool/KanbanTool.swift, Tests/Fixtures/kanban.graphql, Tests/.../Body/ColumnTriggerTests.swift (new), Tests/.../Mutations/ColumnTriggerMutationTests.swift (new), Tests/.../Mutations/TaskOperationTests.swift (jsonText now internal), Tests/.../Tool/KanbanToolTests.swift, divergence.md §22.
    - next: /review
  timestamp: 2026-10-24T02:18:56.246411+00:00
- actor: claude-code
  id: 01m5nvj64ff25y314b9c98p38y
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (8f23671): 2 findings (2 confirmed, 6 refuted) — Sources/FoundationModelsKanban/GraphQL/MutationResolvers.swift:569 (duplication/duplication), Sources/FoundationModelsKanban/GraphQL/MutationResolvers.swift:569 (reuse/reuse)
    - next: implement the two open findings in the Review Findings (2026-10-23 21:20) section. Then do a new review.
  timestamp: 2026-10-24T02:24:14.991657+00:00
- actor: claude-code
  id: 01m5nvk4hq37yavsytag3prsay
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 18 files, Column.trigger and Column.next, divergence.md §22
    - test: green — swift test, 1816 tests in 152 suites
    - commit: 8f23671
    - review: findings — Sources/FoundationModelsKanban/GraphQL/MutationResolvers.swift:569 (2)
  timestamp: 2026-10-24T02:24:46.135646+00:00
- actor: claude-code
  id: 01m5nvsgtec1jrnytvjxgn42ns
  text: |-
    Fixed the two findings in MutationResolvers.swift. Cause: `isCleared` and `isUnchanged` each had a `guard case ... else { return false }; return true` copy. The getter `value` had a third copy of the same guard-case-return pattern (`guard case .changed(let value) = self else { return nil }`).
    - New private `FieldUpdate.Kind` (the case without the value) and a private `kind` that reads the case with one `switch self`. `isCleared` is now `kind == .cleared`, and `isUnchanged` is now `kind == .unchanged`.
    - `value` is now a `switch self` expression, the same form as `map` and `value(clearingTo:)`. The file has no more `guard case` lines.
    - New test Tests/FoundationModelsKanbanTests/GraphQL/FieldUpdateTests.swift holds the behavior of `isCleared`, `isUnchanged`, and `value` for each case. This is a refactor, so the test passed before and after the change.
    - Acceptance criteria: all 5 are checked. Each has a passing test in ColumnTriggerMutationTests.swift (no frontmatter read, body write, bad YAML warning, updateColumn trigger write, changes event, undoChange) and divergence.md §22 records the rule.
  timestamp: 2026-10-24T02:28:15.310461+00:00
- actor: claude-code
  id: 01m5nvsh8epfp56x77xs429w8t
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` and `swift test`: 1817 tests in 153 suites passed; only the accepted SwiftPM "missing creator" warning. Files: Sources/FoundationModelsKanban/GraphQL/MutationResolvers.swift, Tests/FoundationModelsKanbanTests/GraphQL/FieldUpdateTests.swift (new). Findings 2/2 checked; acceptance criteria 5/5 checked.
    - next: /review
  timestamp: 2026-10-24T02:28:15.758050+00:00
position_column: doing
position_ordinal: '80'
title: Read the trigger and next of a column from the frontmatter of its body (KANBAN-2)
---
## What

KanbanViewKit has the command "Set Column Trigger…" (its plan §3.2, §3.4). The definition is in TestudoApp: D29, D46, D47, D49, and KANBAN-2 and KANBAN-11 in `../TestudoApp/features/packages/foundationmodels-kanban.md`.

- A trigger is a skill that runs when a task enters the column.
- The configuration is YAML frontmatter at the top of the column `body`: `trigger: <skill>` and `next: <bool>`. `next` says if the task moves to the next column when the skill ends. The default of `next` is `true`.
- The frontmatter is in the column body, so it is in the event log, with history, undo and git merge. There is no new file and no new stored field.
- This task does NOT run triggers. The `TriggerRunner` (KANBAN-1) is in Step 3 (D56).

## Work

- Parse the frontmatter of the column body. Give the typed fields `Column.trigger: String` (null when not set) and `Column.next: Boolean!` (default `true`). A body with no frontmatter, or with bad YAML, gives `trigger: null` and `next: true`, and a warning for bad YAML. Do not refuse the write.
- Give an easy write: `trigger` and `next` in the input of `addColumn` and `updateColumn`. The engine writes them into the frontmatter of the body, and keeps the other frontmatter keys and the text after the frontmatter. `trigger: null` removes the key.
- A write of `body` directly also works: the typed fields come from the new body.
- Record in `divergence.md` that the column trigger follows KANBAN-2.
- Add schema descriptions and update the tool description.
- Not in this task: `wipLimit`, `taskCount` and `moveColumn` (the rest of KANBAN-11).

## Acceptance criteria

- [x] `updateColumn(input: {id, trigger: "do"})` writes `trigger: do` into the frontmatter of the body, and keeps the rest of the body.
- [x] `Column.trigger` and `Column.next` read the frontmatter. With no frontmatter: `null` and `true`.
- [x] A body with bad YAML gives `null` and `true` and a warning.
- [x] A `changes` event gives the new body and the new typed fields. One `undoChange` reverses the write.
- [x] `divergence.md` records the rule.

## Tests

- Unit tests in `T/` for each criterion.
- `swift test` passes with no new warnings.

## Review Findings (2026-10-23 21:20)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 16 file(s) reviewed, 4 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `Tests/Fixtures/kanban.graphql` — no validator matches this file
> - `divergence.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/GraphQL/MutationResolvers.swift:569` `duplication/duplication` — `FieldUpdate.isUnchanged` (lines 568-574) is a copy of the existing `isCleared` (lines 560-566) with only the enum case name changed. Two copies of one guard-case-return pattern can drift apart. Add one private helper on `FieldUpdate`, for example `isCase(_ test: (FieldUpdate) -> Bool)`, or write both properties as `switch self` expressions that share one shape. Keep the two public properties as one-line delegations. If the team judges this two-line guard too small to matter, drop this finding.
- [x] `Sources/FoundationModelsKanban/GraphQL/MutationResolvers.swift:569` `reuse/reuse` — `FieldUpdate.isUnchanged` is a copy of the existing `isCleared` pattern (line 561) with a different case. Each new case adds another copy of the same guard. Add one helper on FieldUpdate that tests for a given case, or derive the checks from a single switch, and express `isCleared` and `isUnchanged` through it.
