---
assignees:
- claude-code
depends_on:
- 01M8EKMNE2J1878SKPN89E0CYQ
position_column: todo
position_ordinal: '8180'
title: Add the addChecklistItem mutation
---
## Goal

Add the GraphQL mutation `addChecklistItem`. It adds one checklist item to the body of a task, and the caller does not send the full body.

## Contract

```graphql
addChecklistItem(input: AddChecklistItemInput!): Task!

input AddChecklistItemInput {
  id: ID!            # the task, all ID forms that updateTask accepts
  text: String!      # the text of the new item, without a marker
  checked: Boolean   # no value: false
  before: String     # optional: put the new item before this item
  after: String      # optional: put the new item after this item
  board: ...         # the same board field as the other task mutations
}
```

- `before` and `after` use the forgiving item matcher of `updateChecklistItem` (index or text). Give `before` or `after`, not both. If both are set and they name the same place, accept the call. If they name different places, give an error.
- No position: put the item after the last checklist item, with the same indent as that item. A body with no checklist: put the item at the end of the body, after one blank line if the body is not empty.
- A `text` that starts with a marker (`- [ ] `, `- [x] `, `[ ] `, `- `) is close enough. Remove the marker, and use `checked` from the marker when `checked` has no value. A conflict between the marker and `checked` gives an error.
- An empty `text`, or a `text` with a line break, gives an error, because it is not one item.
- The same text as a current item is allowed. Add a warning, because a later text match will be ambiguous.
- Write through the same body-diff path as `updateTask`. A new `#tag` marker in the text gets a tag, as in `updateTask`.
- Add the schema descriptions in STE. Add the mutation to SKILL.md and to divergence.md. Do not change `plan.md`.

## Subtasks

- [ ] Add `AddChecklistItemInput` and the resolver.
- [ ] Add the insert logic: the end of the checklist, before, after, and a body with no checklist.
- [ ] Add schema descriptions, and update the SDL signature tests.
- [ ] Tests: the end of the checklist, an empty body, a body with no checklist, before and after by index and by text, a marker in the text, a conflict, a line break in the text, a duplicate text warning, a new tag marker, undo.
- [ ] Update SKILL.md and divergence.md.
#checklist #graphql-endpoint