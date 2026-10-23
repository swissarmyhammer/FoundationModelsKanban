---
assignees:
- claude-code
position_column: todo
position_ordinal: 8a80
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