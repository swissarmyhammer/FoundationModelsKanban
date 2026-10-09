---
assignees:
- claude-code
position_column: todo
position_ordinal: '8980'
title: Refuse tag names that are the same as a virtual tag
---
## What
A real tag whose slug is the same as a virtual tag (`deleted`, `blocked`, `ready`, `done`, `conflict`, `high`, `medium`, `low`, and the others in `Sources/FoundationModelsKanban/Derived/VirtualTags.swift`) gives wrong results. `#kanban://k/tag/<slug>` also matches the virtual tag (`Filter/FilterEvaluator.swift:172-175`, `:431-432`), and `Tag.tasks` uses that atom (`GraphQL/QueryResolvers.swift:408-409`). Thus `addTag("Deleted")` then `Tag(deleted).tasks` gives every tombstone.

- `addTag`, `renameTag`, `updateTag` (name change), and the tags that `addTask`/`updateTask`/`tagTask` and `#markers` make: refuse a name whose slug is the same as a virtual tag name (ignore case). Give `INVALID_TAG_NAME` with a message that names the virtual tag.
- A `#marker` in a body that names a virtual tag does not make a real tag (it stays a filter word only).
- Replay never refuses a log. An old log that holds a real tag `done`, `high` or `low` still loads. That tag node stays and is listed in `tags`. The filter atom `#done` matches the virtual tag only, not the real tag.
- Update plan.md §6 (virtual tags) and §6.1 with this rule.

## Acceptance Criteria
- [ ] `addTag(name:"Deleted")` and `addTag(name:"blocked")` give `INVALID_TAG_NAME`.
- [ ] `addTask(tags:["done"])` gives `INVALID_TAG_NAME` and writes no patch.
- [ ] A body with `#BLOCKED` makes no tag.
- [ ] A board whose log holds a real tag `done` loads with no error. `tags` lists the tag `done`. `tasks(filter:"#done")` gives only the tasks in the done column, not the tasks that have the real tag `done`.

## Tests
- [ ] Tests in `Tests/FoundationModelsKanbanTests/Tags/` and `Tests/FoundationModelsKanbanTests/Mutations/`.
- [ ] A test that writes a log with a real tag `done` (and a task with that tag that is not in the done column) to a temporary board, opens the board, and checks the last acceptance criterion.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.