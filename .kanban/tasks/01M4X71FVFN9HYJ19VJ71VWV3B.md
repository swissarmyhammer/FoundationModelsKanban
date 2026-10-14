---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4y6ef6xnxd6fyp1fbszasq2
  text: |-
    Research:
    - The refusal of virtual tag names (TagSlug.checkSlugIsNotReserved, TaskMutations marker check) and the filter atom (FilterCompiler.tagTest) use VirtualTag(named:). When the case `blocking` goes out of the enum, `addTag(name: "blocking")` works and `#BLOCKING` falls through to the real tag path. No special code is necessary.
    - `dependents` in Readiness has only two users: `TaskObject.blocks` and the BLOCKING case. Both go, so the stored `dependents` and `Graph.dependents(from:)` go too.
    - T/CrossRepo/CrossRepoReadTests.swift has no use of `blocks` or BLOCKING. Its only hit is `CountingKeyReader(blockingFirstReadOf:)`, which is a different thing. No change is necessary there.
    - Tests to change: VirtualTagsTests, ReadinessTests (dependents tests), FilterEvaluatorTests (BLOCKING lines), QueryResolverTests and NodeQueryTests (expected virtualTags and blocks), ChangeBuilderTests (selections and listFields), NameMatcherTests (taskFields list).
  timestamp: 2026-10-14T21:52:41.181725+00:00
- actor: claude-code
  id: 01m4y6sh339be1aezabyhy7crv
  text: |-
    Implementation landed (TDD). RED: 16 issues in the new and changed tests, each for the expected reason (BLOCKING still a virtual tag, `blocks` still in the schema and the change feed). GREEN: the same 32 tests pass. Full `swift test`: 1246 tests in 93 suites pass. The only warning is the accepted SwiftPM "missing creator" warning.

    Changes:
    - VirtualTag: case `blocking` is gone. The doc comment now says the match ignores case (`init(named:)`), and that `#BLOCKING` is an ordinary tag atom. The `hasVirtualTag` doc no longer names BLOCKING.
    - Readiness: the stored `dependents`, `dependents(ofTaskAt:)`, and `Graph.dependents(from:)` are gone. The type doc names only done, `ready`, and `blockedBy`.
    - QueryResolvers `TaskObject.blocks`, Schema `Field("blocks")`, and ChangeBuilder `("blocks", ...)` are gone.
    - No special code for the name `blocking`: the virtual tag name check and the filter atom use `VirtualTag(named:)`, so `blocking` is now an ordinary tag name.

    New tests: VirtualTagsTests (BLOCKING is not a virtual tag; a depended-on task has no BLOCKING), FilterEvaluatorTests (`#BLOCKING` with no real tag gives an empty result and no error; `#BLOCKING` and `#blocking` match the real tag `blocking`), TagMutationTests (`addTag(name: "blocking")` works; `#BLOCKING` matches the task with the real tag, through the GraphQL engine), NameRewriteTests (a `blocks` query gives the validation error `Cannot query field "blocks" on type "Task".` and no data), ChangeBuilderTests (no public mutation gives a `blocks` field change).

    Discovery: T/CrossRepo/CrossRepoReadTests.swift had no use of `blocks` or BLOCKING, so it has no change. All new graph tests are in suites with the `.watcherBudget` trait. All fixtures are temporary folders or in-memory ReadinessFixture boards.
  timestamp: 2026-10-14T21:58:43.555946+00:00
- actor: claude-code
  id: 01m4y6sn5jgedqx5h7yyr037xe
  text: |-
    ### implement — changed
    - evidence: 14 files — Sources/FoundationModelsKanban/Derived/Readiness.swift, Sources/FoundationModelsKanban/Derived/VirtualTags.swift, Sources/FoundationModelsKanban/GraphQL/QueryResolvers.swift, Sources/FoundationModelsKanban/GraphQL/Schema.swift, Sources/FoundationModelsKanban/Observe/ChangeBuilder.swift, Tests/FoundationModelsKanbanTests/Derived/ReadinessTests.swift, Tests/FoundationModelsKanbanTests/Derived/VirtualTagsTests.swift, Tests/FoundationModelsKanbanTests/Filter/FilterEvaluatorTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/NameMatcherTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/NodeQueryTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/QueryResolverTests.swift, Tests/FoundationModelsKanbanTests/Mutations/TagMutationTests.swift, Tests/FoundationModelsKanbanTests/Observe/ChangeBuilderTests.swift; swift test: 1246 tests in 93 suites pass, only the accepted SwiftPM warning
    - next: /review
  timestamp: 2026-10-14T21:58:47.730349+00:00
position_column: doing
position_ordinal: '80'
title: Remove the blocks field and the BLOCKING virtual tag
---
## What
divergence.md Q1 (DECIDED), X1, R5, C1, and §11 "Q1" and "C1". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Decision: we do not need dependencies in two directions. Keep only `dependsOn` and `blockedBy`. Remove the `blocks` field and the BLOCKING virtual tag, in one board and across boards. Reason: BLOCKING is for a human who wants to make less work. An agent does the blockers until they are done.

C1: after this change, BLOCKING is not special. `#BLOCKING` is an ordinary tag filter: it matches a real tag named `blocking` (usually nothing). A user can make a real tag named `blocking`. Do not add a special error, and do not keep BLOCKING as a reserved name.

Change the code:
- S/Derived/Readiness.swift:36,65,129,221-229 (the stored `dependents`).
- S/Derived/VirtualTags.swift:17,91-92.
- S/GraphQL/QueryResolvers.swift:539-541.
- S/Observe/ChangeBuilder.swift:419 (`("blocks", ...)`).
- S/GraphQL/Schema.swift (the `blocks` field).
- Fix the doc comments at S/Derived/Readiness.swift:3,125 and S/Derived/VirtualTags.swift:73.
- Also fix the bug in the doc comment at S/Derived/VirtualTags.swift:7-8: it says "case-sensitive", but the match does not use case (:51-57). The test `virtualTagCaseInsensitive` (T/Filter/FilterEvaluatorTests.swift:285) shows that the match ignores case. Write that the match ignores case.

Change the tests: the BLOCKING and `blocks` tests, and also T/Observe/ChangeBuilderTests.swift, T/GraphQL/NodeQueryTests.swift, and T/CrossRepo/CrossRepoReadTests.swift, which use these fields.

## Acceptance Criteria
- [ ] The schema has no `blocks` field. A query for `blocks` gives the normal unknown-field result of the name matcher.
- [ ] BLOCKING is not a virtual tag. No `virtualTags` value is BLOCKING.
- [ ] `#BLOCKING` matches only tasks with a real tag `blocking`.
- [ ] `addTag(name: "blocking")` works.
- [ ] The change feed has no `blocks` field change.
- [ ] The doc comment of S/Derived/VirtualTags.swift says that the match ignores case.

## Tests
- [ ] Remove or change each BLOCKING and `blocks` test.
- [ ] A test: a real tag `blocking` can be made, and `#BLOCKING` matches the task that has it.
- [ ] A test: `#BLOCKING` on a board with no `blocking` tag gives an empty result and no error.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.