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
- actor: claude-code
  id: 01m4grw9e7hq94w9v06f37m6cz
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 10 files
    - test: green — swift test, 1078 tests in 76 suites passed
    - commit: b9a1bc6
    - review: findings — Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift:401
  timestamp: 2026-10-09T16:45:26.343311+00:00
- actor: claude-code
  id: 01m4gs0ma3vks0gqwty319cqzy
  text: |-
    Review finding fixed (`completeness/public-output-contract`, NameRewriteTests.swift `mutationRewriteIsInExtensions`):
    - The test now compares the full response with exact equality, the same as `labelInputFieldIsInExtensions`. The expected text is `{"data":{"taskAdd":{"id":"<task URI>"}}` + `extensionsSuffix(rewrite:)`.
    - The id of the added task is a new ULID on each run. The test reads it with `AddUpdateTaskTests.firstTask(in:)` and makes the URI with `ColumnActorTests.id(of: .task(task))`. A comment in the test gives this reason.
    - Check of the file: no other test uses `hasSuffix`. The two `hasPrefix` checks (`noMatchGivesValidationError`, `createBoardDoesNotMapToInitBoard`) examine error messages in tests that this task did not add. They are prefix checks, not suffix-only checks, so this step did not change them.
  timestamp: 2026-10-09T16:47:48.547344+00:00
- actor: claude-code
  id: 01m4gs0nvq7607bcbz6psgm6m6
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift. `swift test --filter NameRewriteTests/mutationRewriteIsInExtensions`: 1 test passed. `swift test`: 1078 tests in 76 suites passed, 0 failures; only the accepted SwiftPM "missing creator for mutated node" warning.
    - next: /review
  timestamp: 2026-10-09T16:47:50.135628+00:00
- actor: claude-code
  id: 01m4gs4z7bkz13a027mnx7q9cy
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 1 file
    - test: green — swift test, 1078 tests in 76 suites passed
    - commit: d38ce63
    - review: clean — 0 findings
  timestamp: 2026-10-09T16:50:10.795837+00:00
depends_on:
- 01M4G9J3T6GYAK2C87GK5XF03F
position_column: done
position_ordinal: cc80
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

## Review Findings (2026-10-09 11:43)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 9 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift:401` `completeness/public-output-contract` — The assertion in mutationRewriteIsInExtensions now checks only that the response ends with the extensions suffix. The data part of the response is no longer checked. The sibling test labelInputFieldIsInExtensions (line 419) still checks the whole response with exact equality. A regression in the data of the taskAdd/addTask response would now pass this test. Assert the full response with exact equality, as line 419 does. Build the expected data prefix from the addTask field response. If the data varies per run, say why in a comment and assert the prefix separately.
