---
assignees:
- claude-code
position_column: todo
position_ordinal: a180
title: Make updateTag with a new slug do a renameTag
---
## What
divergence.md C4 (DECIDED: option a) and E1 (DECIDED), and §11 "C4". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem: `updateTag {id, name}` with a new name runs, but it changes only the display name. The slug stays. An agent that uses the Rust form thinks that it renamed the tag, but it did not.

Decided behavior:
- When `updateTag` gets a `name` whose slug is different from the current slug, it does the same as `renameTag` (a redirect from the old slug, and the `#old` markers change).
- When the slug is the same, `updateTag` changes only the display name (as now).
- E1 edge cases (do the same as `renameTag` in all cases):
  - The new slug already exists: merge the old tag into that tag (S/GraphQL/TagMutations.swift:250-253,267-268).
  - The new slug is reserved (`board`) or is a virtual tag name (for example `Done` gives `done`): give the same error as `renameTag` (`INVALID_TAG_NAME` or the virtual-tag error).
  - The same call also sets `color` or `body`: apply them to the tag at the end of the rename (the target tag).
  - Accepted result: a display name must give the same slug as the tag. For example, the tag `bug` cannot get the display name "Defect" without a rename.
- Change S/GraphQL/TagMutations.swift:113-128 (the resolver and its doc comment).

## Acceptance Criteria
- [ ] `updateTag(input: {id: "bug", name: "defect"})` renames the tag to `defect`, makes a redirect from `bug`, and changes `#bug` markers to `#defect`.
- [ ] `updateTag(input: {id: "bug", name: "Bug"})` changes only the display name.
- [ ] A new slug that exists merges into that tag.
- [ ] A reserved slug or a virtual tag name gives the same error as `renameTag`.
- [ ] `color` in the same call goes to the target tag.

## Tests
- [ ] A new slug makes a redirect and changes the markers.
- [ ] The same slug changes only the display name.
- [ ] The merge case, the reserved slug, the virtual tag name, and `color` in the same call.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.