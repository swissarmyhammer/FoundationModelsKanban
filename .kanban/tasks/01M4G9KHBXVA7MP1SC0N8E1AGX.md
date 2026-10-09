---
assignees:
- claude-code
depends_on:
- 01M4G9J3T6GYAK2C87GK5XF03F
position_column: todo
position_ordinal: '9180'
title: 'Schema agrees with plan §4: nullability, optional addTag input, label alias'
---
## What
Three differences between the generated SDL and plan.md §4.

1. Nullability. The code makes these fields nullable on purpose, so that an error nulls only that field: `tasks(...)`, `searchTasks(...)`, `history(...)`, `Column/Actor/Tag.tasks`, `Change.updates` (`Sources/FoundationModelsKanban/GraphQL/QueryResolvers.swift:347, 372, 427` and the history resolvers). Update plan.md §4.1 to show them nullable, with one line that gives the reason. Do not change the code.
2. `addTag(input: AddTagInput!)`: each field of `AddTagInput` is optional, so §4.2 says `input` is optional. Make `input` optional (the same as `initBoard` in `GraphQL/MutationResolvers.swift:149-151`). Check each other mutation for the same rule.
3. The alias `label` → `tag` (`GraphQL/Schema.swift:1010-1011`) never matches, because no name is `tag`. Map `label` to `tags` (the field name), so that `tagTask(input:{label:["bug"]})` is rewritten to `tags`. Keep `labels` → `tags`.

## Acceptance Criteria
- [ ] plan.md §4.1 agrees with `KanbanGraph.schemaSDL` for the listed fields.
- [ ] `mutation { addTag { id } }` passes validation and gives `INVALID_TAG_NAME`.
- [ ] Each mutation whose input has no required field has an optional `input`.
- [ ] `label` is rewritten to `tags` and the rewrite is in `extensions.rewrites`.

## Tests
- [ ] An SDL test in `Tests/FoundationModelsKanbanTests/GraphQL/` that checks that each mutation whose input has no required field takes an optional `input`.
- [ ] Name rewrite tests for `label`.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.