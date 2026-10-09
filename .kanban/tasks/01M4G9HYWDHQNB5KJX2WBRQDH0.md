---
assignees:
- claude-code
depends_on:
- 01M4G9JDQ98082KJQTMWE86DV8
position_column: todo
position_ordinal: '8780'
title: addTag, addColumn and addActor accept a full kanban:// URI as id
---
## What
`Sources/FoundationModelsKanban/GraphQL/TagMutations.swift:94-95` and `Sources/FoundationModelsKanban/GraphQL/ColumnActorMutations.swift:140` and `:223` make the slug from `input.id.text` with `TagName(normalizing:)` or `Slug(columnOrActorName:)`. They do not check for the `kanban://` scheme first. Thus `addTag(input:{id:"kanban://github.com/o/r/tag/bug"})` makes a tag `kanban-github-com-o-r-tag-bug`, and `addActor(ensure:true)` with an actor URI makes a second actor. plan.md §3.2: "a full URI with the key of the target board becomes a local ref". `moveTask` and `addComment` already do this check.

- Use the same resolve step as `moveTask` and `addComment`: when the id is a `kanban://` URI, parse it, check the node type (tag, column, actor), check the board, and use its slug.
- A URI of a wrong node type gives the same error as in `moveTask`.

## Acceptance Criteria
- [ ] `addTag` with the URI of an existing tag returns that tag and makes no new tag.
- [ ] `addActor(ensure:true)` with the URI of an existing actor returns that actor.
- [ ] `addColumn` with a column URI uses the slug of the URI.
- [ ] A task URI in `addTag` gives an error.

## Tests
- [ ] Tests in `Tests/FoundationModelsKanbanTests/Mutations/` for each acceptance criterion.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.