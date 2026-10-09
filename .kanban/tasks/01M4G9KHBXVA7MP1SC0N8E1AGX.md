---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gr8bejefgc73vx63gzg96n
  text: |-
    Research:
    - The generated SDL (`kanban --schema`) has these nullable fields: `Board.tasks: TaskConnection`, `Board.searchTasks: [TaskHit!]`, `Board.history: [Change!]`, `Column/Actor/Tag.tasks: [Task!]`, `Change.updates: [NodeUpdate!]`. plan.md §4.1 shows them with `!`.
    - Of all input types, only `BoardInput`, `UndoInput` and `AddTagInput` have no required field. `initBoard`, `updateBoard`, `undo`, `redo` already take an optional `input`. Only `addTag(input: AddTagInput!)` breaks the rule.
    - `BoardMutationArguments` (MutationResolvers.swift) and `UndoArguments` (UndoMutations.swift) are two private copies of the same shape: a struct with `let input: X?`. `InputArguments<Input>` (ColumnActorMutations.swift) is the generic form for a required input.
    - The alias step of NameMatcher compares the written name with the aliases of each candidate name. `GraphQLFieldAliases.byName["tag"] = ["label"]` never matches, because no schema position has the name `tag`. `label` must be an alias of `tags`.
    - plan.md §4.5 step 5 also says `label` → `tag`.
  timestamp: 2026-10-09T16:34:33.042516+00:00
- actor: claude-code
  id: 01m4grmnyezv1wqzpcmbaev6p8
  text: |-
    Implementation:
    - New generic `OptionalInputArguments<Input>` (ColumnActorMutations.swift, next to `InputArguments`). `addTag` uses it, so the SDL now shows `addTag(input: AddTagInput): Tag`. With no `input`, `addTag` gives `INVALID_TAG_NAME` (name ""), the same as an empty `input`.
    - The two private copies `BoardMutationArguments` and `UndoArguments` are removed. `initBoard`, `updateBoard`, `undo` and `redo` use the generic type. The SDL of these four did not change.
    - Check of all mutations: only `BoardInput`, `UndoInput` and `AddTagInput` have no required field. All other inputs have a required field and keep `input!`.
    - `GraphQLFieldAliases.byName`: removed `"tag": ["label"]`; `"tags"` is now `["labels", "label"]`.
    - plan.md: §4.1 shows the listed fields as nullable, with one comment line that gives the reason. §4.2 lists the five mutations with an optional `input`. §4.5 step 5 says `label` / `labels` → `tags`.
    - Discovery: `NameMatcherTests.labelAliasGivesTag` pinned the old `label` → `tag` mapping with a made-up candidate `tag`. I removed that test and added `("label", "tags")` to the `aliasGivesField` rows.
  timestamp: 2026-10-09T16:41:17.006454+00:00
- actor: claude-code
  id: 01m4grmqztxj5w5qkhswdpsp0f
  text: |-
    ### implement — changed
    - evidence: 9 files — plan.md; Sources/FoundationModelsKanban/GraphQL/{ColumnActorMutations,TagMutations,MutationResolvers,UndoMutations,Schema}.swift; Tests/FoundationModelsKanbanTests/GraphQL/{MutationInputSchemaTests (new),NameRewriteTests,NameMatcherTests}.swift; Tests/FoundationModelsKanbanTests/Mutations/TagMutationTests.swift. `swift test`: 1078 tests in 76 suites passed, 0 failures; only the accepted SwiftPM "missing creator for mutated node" warning.
    - next: /review
  timestamp: 2026-10-09T16:41:19.098313+00:00
- actor: claude-code
  id: 01m4grmtw8a7gv2g2x1zy8p14d
  text: 'Correction to the step record: the count is 10 files, not 9. The list of paths in the record is correct.'
  timestamp: 2026-10-09T16:41:22.056131+00:00
depends_on:
- 01M4G9J3T6GYAK2C87GK5XF03F
position_column: doing
position_ordinal: '80'
title: 'Schema agrees with plan §4: nullability, optional addTag input, label alias'
---
## What
Three differences between the generated SDL and plan.md §4.

1. Nullability. The code makes these fields nullable on purpose, so that an error nulls only that field: `tasks(...)`, `searchTasks(...)`, `history(...)`, `Column/Actor/Tag.tasks`, `Change.updates` (`Sources/FoundationModelsKanban/GraphQL/QueryResolvers.swift:347, 372, 427` and the history resolvers). Update plan.md §4.1 to show them nullable, with one line that gives the reason. Do not change the code.
2. `addTag(input: AddTagInput!)`: each field of `AddTagInput` is optional, so §4.2 says `input` is optional. Make `input` optional (the same as `initBoard` in `GraphQL/MutationResolvers.swift:149-151`). Check each other mutation for the same rule.
3. The alias `label` → `tag` (`GraphQL/Schema.swift:1010-1011`) never matches, because no name is `tag`. Map `label` to `tags` (the field name), so that `tagTask(input:{label:["bug"]})` is rewritten to `tags`. Keep `labels` → `tags`.

## Acceptance Criteria
- [x] plan.md §4.1 agrees with `KanbanGraph.schemaSDL` for the listed fields.
- [x] `mutation { addTag { id } }` passes validation and gives `INVALID_TAG_NAME`.
- [x] Each mutation whose input has no required field has an optional `input`.
- [x] `label` is rewritten to `tags` and the rewrite is in `extensions.rewrites`.

## Tests
- [x] An SDL test in `Tests/FoundationModelsKanbanTests/GraphQL/` that checks that each mutation whose input has no required field takes an optional `input`.
- [x] Name rewrite tests for `label`.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.