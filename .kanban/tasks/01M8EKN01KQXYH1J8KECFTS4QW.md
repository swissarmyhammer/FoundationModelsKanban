---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m8ep8rkg91wgnmvjqbxy2rav
  text: |-
    Research done.
    - Reuse: `ChecklistItem` (parser, markers, indent, line break), `ChecklistItemMatch` (forgiving match), `BodyLines`, `KanbanContext.changeTask(named:on:_:)` and `TaskWrite` (internal since ^89e0cyq), `WorkingCopy.write` with `TaskChange(values: [:], body: .changed(body), edges: [:])`. The write path gives tags from `#tag` markers, undo and the change stream with no new code.
    - Decisions of ^89e0cyq that override the card: the result is nullable `Task`; `before` and `after` are `ID` (an int or a string); the board field is `makeTargetBoardField()` with `MutationBoard.holding(id, orNamed: board)` (the renameTag rule: a short ref resolves in the named or the current board, a full URI names its own board). The task mutations that name a task by `id` have no other board field.
    - The errors `checklistItemNotFound` and `ambiguousChecklistItem` say "as item" in their message. For `before` and `after` the field name must be in the message, so the plan is to add a `field` value with the default `item`. The empty-body message now tells to use `updateTask`; with the new mutation it can tell to use `addChecklistItem`.
    - New schema parts touch: the golden SDL `Tests/Fixtures/kanban.graphql`, `KanbanFieldAliases`, `AliasTableTests`, `KanbanErrorTests` code tables, `EndpointConventionTests.warningCodes`, `Schema.swift` builder chain.
  timestamp: 2026-11-27T14:24:07.792528+00:00
- actor: claude-code
  id: 01m8epv0w3ptj6yajc0w2vcf49
  text: |-
    Implementation landed. All 5 subtasks are checked.
    - New: `Derived/ChecklistItemAddition.swift` (`ChecklistItemDraft`: the forgiving read of the text; `ChecklistItemAddition`: the place and the new body) and `GraphQL/AddChecklistItemMutation.swift` (the input, the resolver, the schema, the `DUPLICATE_ITEM_TEXT` warning).
    - New errors: `INVALID_ITEM_TEXT` (`emptyChecklistItemText`, `multilineChecklistItemText`), `CONFLICTING_ITEM_STATE` (`conflictingChecklistItemState`), and `conflictingChecklistPlacement` with the code `CONFLICTING_PLACEMENT`.
    - Changed: `checklistItemNotFound` and `ambiguousChecklistItem` have a new `field` value (default `item`), so that the message names `before` or `after`. The NOT_FOUND message of a body with no checklist now tells the agent to use `addChecklistItem`, not `updateTask` (also for `updateChecklistItem`). `ChecklistItemMatch.item` has a `field` parameter, and the new `items(withTextLike:among:)`.
    - Discovery: the indexes of the same-text items must be the indexes in the new body, because an item before them moves them by one. The warning uses these indexes.
    - Test helpers `bodySetup`, `taskWithBody`, `bodyAfter`, and `failure` of `ChecklistItemMutationTests` are now internal and shared by the new mutation tests.
    - Divergences from the card: nullable `Task`, `before`/`after` are `ID`, and the board field is the renameTag form. divergence.md §31 records them. The card text is updated.

    ### implement — changed
    - evidence: `swift test`: 2072 tests in 177 suites passed, 0 failures, no warnings except the accepted mlx Metal ones. 16 files: 4 new (ChecklistItemAddition.swift, AddChecklistItemMutation.swift, ChecklistItemAdditionTests.swift, AddChecklistItemMutationTests.swift), 12 changed (Errors.swift, ChecklistItemMatch.swift, ChecklistItemMutation.swift, FieldAliases.swift, Schema.swift, SchemaDescription+Mutations.swift, Tests/Fixtures/kanban.graphql, KanbanErrorTests.swift, AliasTableTests.swift, EndpointConventionTests.swift, ChecklistItemMutationTests.swift, Documentation/kanban/SKILL.md, divergence.md).
    - next: /review
  timestamp: 2026-11-27T14:34:06.083831+00:00
- actor: claude-code
  id: 01m8epvb1d7jmdjzpntbf6vzde
  text: 'Correction to the step record above: the count is 17 files (4 new, 13 changed), not 16. The list of names in the record is correct.'
  timestamp: 2026-11-27T14:34:16.493657+00:00
- actor: claude-code
  id: 01m8epzd7a7yqgnbwvnemxs6rj
  text: |-
    ### test - green
    - evidence: swift test - 2072 tests in 177 suites passed, 0 failed, 0 skipped. The only warning in the log is the allowed SwiftPM "missing creator for mutated node" warning for mlx-swift_Cmlx.bundle.
    - swiftlint: the project has no .swiftlint.yml and CI has no lint step. A plain `swiftlint lint` in the repo root also reads the SwiftLint configs of the packages in .build, so it prints only a version warning (0.48.0 against 0.65.1) and exits 2. I ran `swiftlint lint --no-cache Sources Tests IntegrationTests` with the default rules. It gives 598 findings (300 trailing_comma, 69 file_length, 62 line_length). 548 of them are in files that this task did not change. Schema.swift already had 1406 lines at HEAD. No written project rule exists for lint, so I made no change. I did not reformat.
    - next: review
  timestamp: 2026-11-27T14:36:29.802830+00:00
depends_on:
- 01M8EKMNE2J1878SKPN89E0CYQ
position_column: doing
position_ordinal: '80'
title: Add the addChecklistItem mutation
---
## Goal

Add the GraphQL mutation `addChecklistItem`. It adds one checklist item to the body of a task, and the caller does not send the full body.

## Contract

```graphql
addChecklistItem(input: AddChecklistItemInput!): Task

input AddChecklistItemInput {
  id: ID!            # the task, all ID forms that updateTask accepts
  text: String!      # the text of the new item, without a marker
  checked: Boolean   # no value: false
  before: ID         # optional: put the new item before this item (2 or "2", or the text)
  after: ID          # optional: put the new item after this item (2 or "2", or the text)
  board: String      # the board of a short task ref, the same as updateChecklistItem and renameTag
}
```

- Decision (2026-11-27, from ^89e0cyq): the result is nullable `Task`, the same as each mutation field of the schema. `before` and `after` are `ID`, so that an int and a string both work. The task mutations that name a task by `id` have no board field; the input uses the `board` field of `updateChecklistItem` and `renameTag`: a short ref resolves in the named board or in the current board, and a full URI names its own board.
- `before` and `after` use the forgiving item matcher of `updateChecklistItem` (index or text). Give `before` or `after`, not both. If both are set and they name the same place, accept the call. If they name different places, give an error.
- No position: put the item after the last checklist item, with the same indent as that item. A body with no checklist: put the item at the end of the body, after one blank line if the body is not empty.
- A `text` that starts with a marker (`- [ ] `, `- [x] `, `[ ] `, `- `) is close enough. Remove the marker, and use `checked` from the marker when `checked` has no value. A conflict between the marker and `checked` gives an error.
- An empty `text`, or a `text` with a line break, gives an error, because it is not one item.
- The same text as a current item is allowed. Add a warning, because a later text match will be ambiguous.
- Write through the same body-diff path as `updateTask`. A new `#tag` marker in the text gets a tag, as in `updateTask`.
- Add the schema descriptions in STE. Add the mutation to SKILL.md and to divergence.md. Do not change `plan.md`.
- Add the aliases in the same style as `updateChecklistItem`.

## Subtasks

- [x] Add `AddChecklistItemInput` and the resolver.
- [x] Add the insert logic: the end of the checklist, before, after, and a body with no checklist.
- [x] Add schema descriptions, and update the SDL signature tests.
- [x] Tests: the end of the checklist, an empty body, a body with no checklist, before and after by index and by text, a marker in the text, a conflict, a line break in the text, a duplicate text warning, a new tag marker, undo.
- [x] Update SKILL.md and divergence.md.
#checklist #graphql-endpoint