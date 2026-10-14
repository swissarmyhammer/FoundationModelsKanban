---
assignees:
- claude-code
position_column: todo
position_ordinal: 8d80
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