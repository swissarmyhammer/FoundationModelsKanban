---
assignees:
- claude-code
depends_on:
- 01M8EKMNE2J1878SKPN89E0CYQ
position_column: todo
position_ordinal: '8280'
title: Add the deleteChecklistItem mutation
---
## Goal

Add the GraphQL mutation `deleteChecklistItem`. It removes one checklist item from the body of a task, and the caller does not send the full body.

## Contract

```graphql
deleteChecklistItem(input: DeleteChecklistItemInput!): Task!

input DeleteChecklistItemInput {
  id: ID!            # the task, all ID forms that updateTask accepts
  item: String!      # the item: a 0-based index or the item text
  board: ...         # the same board field as the other task mutations
}
```

- `item` uses the forgiving item matcher of `updateChecklistItem`. Use the same errors for no match and for an ambiguous match.
- Remove only the line of the item and its line break. Keep all other lines byte for byte. If the line is the last line, remove the line break before it, as `DependencyMarkers.removing` does.
- An item that is not there is an error with no change, and the error lists the current items. Do not give a silent success, because the caller can have a wrong item.
- Write through the same body-diff path as `updateTask`, so that undo gives the line back.
- Add the schema descriptions in STE. Add the mutation to SKILL.md and to divergence.md. Do not change `plan.md`.

## Subtasks

- [ ] Add `DeleteChecklistItemInput` and the resolver.
- [ ] Add the line remove logic.
- [ ] Add schema descriptions, and update the SDL signature tests.
- [ ] Tests: the first, a middle and the last item, the only line of the body, an indented item, a match by index and by text, no match, an ambiguous match, undo gives the line back.
- [ ] Update SKILL.md and divergence.md.
#checklist #graphql-endpoint