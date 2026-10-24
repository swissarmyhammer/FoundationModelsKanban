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

- [ ] `updateColumn(input: {id, trigger: "do"})` writes `trigger: do` into the frontmatter of the body, and keeps the rest of the body.
- [ ] `Column.trigger` and `Column.next` read the frontmatter. With no frontmatter: `null` and `true`.
- [ ] A body with bad YAML gives `null` and `true` and a warning.
- [ ] A `changes` event gives the new body and the new typed fields. One `undoChange` reverses the write.
- [ ] `divergence.md` records the rule.

## Tests

- Unit tests in `T/` for each criterion.
- `swift test` passes with no new warnings.