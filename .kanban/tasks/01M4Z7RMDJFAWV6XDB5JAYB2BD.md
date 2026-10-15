---
assignees:
- claude-code
position_column: todo
position_ordinal: b080
title: Accept the stored local form tag/<slug> in task tag lists
---
## What
Found during ^tjwb41h (divergence.md R18). `RefResolver` now accepts the stored local form `<type>/<id>`. But the tag list of `addTask`, `updateTask`, and `tagTask` does not use the resolver for a text that is not a URI: `TaskMutations.tag(named:includingTombstones:)` (S/GraphQL/TaskMutations.swift) sends each text that is not a `kanban://` URI to `TagName(normalizing:)`. Thus `tags: ["tag/bug"]` makes or names the tag `tag-bug`, not the tag `bug`.

Decide (very forgiving): treat a tag text that starts with `tag/` as the stored local form, so `tag/bug` names the tag `bug` (and makes it when the board has no such tag). A text such as `area/backend` stays a tag name. Record the decision in divergence.md.

## Acceptance Criteria
- [ ] `addTask(input: {tags: ["tag/bug"]})` gives the task the tag `bug`.
- [ ] `tagTask` and `updateTask` do the same.
- [ ] A tag name with `/` that does not start with `tag/` keeps its current behavior.

## Tests
- [ ] The cases above, each as a test, in temporary fixture folders (never the `.kanban/` of this repo).
- [ ] `swift test` passes.