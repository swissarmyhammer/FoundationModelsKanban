---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m8erb04sc69j9fw986yqmgvn
  text: |-
    Research done.
    - Reuse: `ChecklistItem.items(inLines:)`, `ChecklistItemMatch.item(for:among:ofTask:)` (NOT_FOUND / AMBIGUOUS_ITEM, field `item`), `BodyLines.lines(of:)` and `BodyLines.content(of:)`, `SchemaDescription.checklistItemReference`, `makeTaskReferenceField`, `makeTargetBoardField`, `MutationBoard.holding(_:orNamed:)`, `KanbanContext.changeTask`. Tests reuse `ChecklistItemMutationTests.bodyAfter(_:on:field:)`, `taskWithBody`, `failure(on:field:)`, `KanbanErrorCapture`.
    - `BodyLines.body(joining:with:)` with an empty edit is NOT correct for the remove: on a last line WITH a line break ("a\nb\n"), it also drops the line break of the line before ("a" in place of "a\n"). So the remove has its own small rule: drop the line; only when the removed line has no line break (the last line), drop the line break of the line before.
    - The NOT_FOUND message of a body with no checklist line says "Add an item with addChecklistItem ... and then send the call again". That is wrong for a delete. Plan: make that sentence correct for each checklist mutation.
    - The resolver closures of updateChecklistItem and addChecklistItem have the same shape (ref, body, TaskChange, write, TaskWrite). A third copy is duplication, so a shared body-write helper goes in, and the three mutations call it.
    - Decisions that differ from the card (the same as §30 and §31): `item` is `ID`, the field is nullable `Task`, `board` is the renameTag-style board field.
  timestamp: 2026-11-27T15:00:18.201192+00:00
- actor: claude-code
  id: 01m8erxq8b82f657tzjv87avzg
  text: |-
    Implementation landed.
    - New: `Derived/ChecklistItemDeletion.swift` (the line remove), `GraphQL/DeleteChecklistItemMutation.swift` (input, resolver, schema), divergence.md §32.
    - New shared write path `KanbanContext.changeTaskBody(named:of:inBoard:_:)` in `TaskMutations.swift`. `updateChecklistItem` and `addChecklistItem` now use it too, so the three checklist resolvers do not repeat the ref / TaskChange / write / TaskWrite block.
    - New shared test helper `ChecklistItemMutationTests.bodyAfterUndo(of:field:)`. The undo tests of update, add and delete use it.
    - The NOT_FOUND message of a body with no checklist line is now "... The body of the task has no checklist line, so no item can match. To add an item, use addChecklistItem with no before or after." The old text ("... and then send the call again") was not correct for a delete.
    - Discovery: the tags of a task come from its tag edges and its body markers (`Graph.tagSlots(of:)`). So a delete of a line with a `#tag` marker removes that tag from the task, unless an edge also gives it. divergence.md §32 records this.
    - Aliases: `deleteSubtask`, `deleteItem`, `removeChecklistItem`, `removeSubtask`, `removeItem`; input `item` aliases are shared with updateChecklistItem.
  timestamp: 2026-11-27T15:10:31.691306+00:00
- actor: claude-code
  id: 01m8erxted3fc39n2qxnk4nb6t
  text: |-
    ### implement — changed
    - evidence: `swift test` 2091 tests in 180 suites passed, 0 failures; the only warning is the SwiftPM "missing creator" warning. 22 files: new Sources/FoundationModelsKanban/Derived/ChecklistItemDeletion.swift, Sources/FoundationModelsKanban/GraphQL/DeleteChecklistItemMutation.swift, Tests/FoundationModelsKanbanTests/Derived/ChecklistItemDeletionTests.swift, Tests/FoundationModelsKanbanTests/Mutations/DeleteChecklistItemMutationTests.swift; changed AddChecklistItemMutation.swift, ChecklistItemMutation.swift, Errors.swift, FieldAliases.swift, Schema.swift, SchemaDescription+Mutations.swift, TaskMutations.swift, Tests/Fixtures/kanban.graphql, AliasTableTests.swift, KanbanErrorTests.swift, AddChecklistItemMutationTests.swift, ChecklistItemMutationTests.swift, Documentation/kanban/SKILL.md, divergence.md, and the kanban files of this task.
    - next: /review
  timestamp: 2026-11-27T15:10:34.957018+00:00
- actor: claude-code
  id: 01m8erzz9rrz6mm6zgmtje6vhy
  text: |-
    ### test — green
    - evidence: swift test — 2091 tests in 180 suites passed, 0 failed, 0 skipped. The only warning is the allowed SwiftPM "missing creator" warning.
    - next: review
  timestamp: 2026-11-27T15:11:45.464746+00:00
- actor: claude-code
  id: 01m8es5wzvwfrbva9ej3rzdzkj
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (5ff2a51). 0 findings, 0 confirmed, 2 refuted, 21 attempted, 0 failed. No validator matched Documentation/kanban/SKILL.md, Tests/Fixtures/kanban.graphql and divergence.md.
    - next: none. The task is in done.
  timestamp: 2026-11-27T15:14:59.707753+00:00
- actor: claude-code
  id: 01m8es6849pf66y6sbzrnvs80z
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 4 new files, 14 changed
    - test: green — swift test, 2091 passed in 180 suites
    - commit: 5ff2a51
    - review: clean — 0 findings; task in done
  timestamp: 2026-11-27T15:15:11.113573+00:00
depends_on:
- 01M8EKMNE2J1878SKPN89E0CYQ
position_column: done
position_ordinal: ffd580
title: Add the deleteChecklistItem mutation
---
## Goal

Add the GraphQL mutation `deleteChecklistItem`. It removes one checklist item from the body of a task, and the caller does not send the full body.

## Contract

```graphql
deleteChecklistItem(input: DeleteChecklistItemInput!): Task

input DeleteChecklistItemInput {
  id: ID!            # the task, all ID forms that updateTask accepts
  item: ID!          # the item: a 0-based index (2 or "2") or the item text
  board: String      # the board of a short task ref, as in updateChecklistItem and renameTag
}
```

The contract follows the decisions of divergence.md §30 and §31: `item` is `ID`, so that `item: 2` and `item: "2"` both work. The field is nullable, the same as each other mutation field of the schema. `board` is the board field of `updateChecklistItem`: a short task ref resolves in the board that `board` names, or in the current board. A full URI in `id` names its own board.

- `item` uses the forgiving item matcher of `updateChecklistItem`. Use the same errors for no match and for an ambiguous match.
- Remove only the line of the item and its line break. Keep all other lines byte for byte. If the line is the last line, remove the line break before it, as `DependencyMarkers.removing` does.
- An item that is not there is an error with no change, and the error lists the current items. Do not give a silent success, because the caller can have a wrong item.
- Write through the same body-diff path as `updateTask`, so that undo gives the line back.
- Add the schema descriptions in STE. Add the mutation to SKILL.md and to divergence.md. Do not change `plan.md`.

## Subtasks

- [x] Add `DeleteChecklistItemInput` and the resolver.
- [x] Add the line remove logic.
- [x] Add schema descriptions, and update the SDL signature tests.
- [x] Tests: the first, a middle and the last item, the only line of the body, an indented item, a match by index and by text, no match, an ambiguous match, undo gives the line back.
- [x] Update SKILL.md and divergence.md.
#checklist #graphql-endpoint