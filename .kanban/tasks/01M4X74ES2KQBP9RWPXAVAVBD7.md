---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4ywjqgj78cr2dvz4jjw7azr
  text: |-
    Research done.
    - The rewrite lives in S/GraphQL/NameRewrite.swift (DocumentRewriter, private RewriteWalk). Schema.swift `rewriting` calls `rewrittenDocument(from:)` and then passes the caller `variables` to `execute` and `subscribe` with no change.
    - The scoped alias of an input field needs two facts: the input type name and the `Type.field` coordinate of the field whose argument holds the object (AliasScope.inputField). A variable declaration gives only the type. So the walk must also record the coordinate where each variable is used (for example `Mutation.deleteTask` for NodeReferenceInput).
    - Plan: the walk records the first usage of each variable (named type and coordinate). After the walk, the keys of each declared and used variable are rewritten with the declared type (fallback: the usage type), the same candidates (CanonicalName(field:in:)), and the same tie error. A key whose canonical name is already a key of the same object keeps its written name, so the engine reports it. A variable that the operation does not declare stays as it is. Each change goes to extensions.rewrites with the path `$<variable>`, then the written keys.
    - The public schema and the patch schema have no list of input objects. The nested array test uses a small test schema, the same as the enum test in NameRewriteTests.
    - The PatchSchema also uses `respond(to:variables:)` with `p: PatchInput`. Its keys are canonical, so the exact step keeps them.
  timestamp: 2026-10-15T04:19:29.426001+00:00
- actor: claude-code
  id: 01m4ywz33pm1z0y81qa8d003qm
  text: |-
    Implementation landed (TDD: RED was 299 issues in the new suite, all for the missing rewrite; then GREEN).
    - S/GraphQL/NameRewrite.swift: `rewrittenDocument(from:variables:operationName:)` and `RewrittenDocument.variables`. The walk records the first use of each variable (named type, `Type.field` coordinate, node) in `visitValue`. Then `rewritten(_:declaredIn:operationName:)` rewrites the keys of each declared and used variable at all depths (arrays and nested `input` objects), with `CanonicalName(field:in: .inputField(type:coordinate:))` and the same tie error. The declared type gives the input type; the type of the use is the fallback when the schema does not have the declared type. A key whose canonical name is already a key (or an earlier target) keeps its written name, so the engine reports it. Each change is in `extensions.rewrites` with the path `["$<variable>", <keys as written>]`.
    - S/GraphQL/Schema.swift: `rewriting` passes `variables` and `operationName` to the rewriter; `execute` and `subscribe` read `rewritten.variables`.
    - T/GraphQL/VariableRewriteTests.swift: each row of `AliasTableTests.inputRows` in the `variables` form (294 cases); AMBIGUOUS_NAME for `comment` on updateComment; the rewrites path; an undeclared variable stays; a taken canonical name stays; a nested list of input objects in a list (test schema, because the public schema has no list of input objects); and the acceptance call `mutation($i: AddTaskInput!) { addTask(input: $i) ... }` with name, labels, depends through execute on a temporary fixture repo.
    - Note: the rows of tables 4.2 and 4.3 that name an argument, a mutation, or a selection field cannot be variable keys, so only the input-field rows have a `variables` form.
    - Not done (out of the card scope): enum values that a variable sends as strings are not rewritten; the card names keys only.
  timestamp: 2026-10-15T04:26:14.518317+00:00
- actor: claude-code
  id: 01m4ywzyvfhp10fk0eqbe87y7j
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift, Sources/FoundationModelsKanban/GraphQL/Schema.swift, Tests/FoundationModelsKanbanTests/GraphQL/VariableRewriteTests.swift (new). `swift test`: 1333 tests in 106 suites passed; the only warning is the accepted SwiftPM "missing creator" warning.
    - next: /review
  timestamp: 2026-10-15T04:26:42.927689+00:00
- actor: claude-code
  id: 01m4yxbtz7qwhbkwfembxzfsjw
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 3 files
    - test: green — swift test, 1333 passed, 0 failed, 0 skipped; IntegrationTests 2 passed (live Qwen variables test included)
    - commit: 5453a05
    - review: findings — Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift:657
  timestamp: 2026-10-15T04:33:12.167629+00:00
- actor: claude-code
  id: 01m4yxkdejp4k9jpkfb0y8d7fn
  text: |-
    Finding NameRewrite.swift:657 (duplication) is fixed in the whole file.
    - New private struct `InputNames` in S/GraphQL/NameRewrite.swift holds `types` (the input type of each canonical name) and `candidates` (the CanonicalName of each name with its aliases). `init(types:in:)` makes the candidates from the types and an AliasScope. `init(fieldsOf:under:)` takes a GraphQLInputObjectType and a coordinate, and gives the field types and the candidates with the `.inputField` scope.
    - `visitValue` and `rewrittenFields` call `InputNames(fieldsOf:under:)`. The copied lines are gone.
    - The same cause was also in `visitBody` + `visitNamedValues`: the arguments of a field mapped types to candidates in `visitNamedValues`. `visitBody` now makes `InputNames(types:in: .argument(...))`, and `visitNamedValues(_:among:under:at:)` takes the `InputNames` and no longer computes candidates. Now one place maps types to candidates.
    - No change in behavior. This is a refactor, so the existing NameRewrite, AliasTable, and VariableRewrite tests cover it. No new test.
    - swift test: 1333 tests in 106 suites passed. The only compiler warning is the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-15T04:37:20.466081+00:00
- actor: claude-code
  id: 01m4yxkf7b8w6rc874rbfym1tc
  text: |-
    ### implement — changed
    - evidence: 1 file — Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift (new InputNames helper; visitBody, visitNamedValues, visitValue, rewrittenFields use it). swift test: 1333 tests in 106 suites passed, 0 failed; only the accepted SwiftPM "missing creator" warning.
    - next: /review
  timestamp: 2026-10-15T04:37:22.283847+00:00
depends_on:
- 01M4X7471GDT9W0J6PWBQTQ6H3
position_column: doing
position_ordinal: '80'
title: Apply the name rewrite to the keys in variables at all depths
---
## What
divergence.md Q8 (DECIDED: yes, at all depths), N1, K5 (kept), and §11 "Q8". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem (N1): the name rewrite changes only the document text (S/GraphQL/NameRewrite.swift:450-498). `variables` go to the engine with no change (S/GraphQL/Schema.swift:1093-1101,1216-1221). When a script sends a whole `input` object as a variable (`addTask(input: $input)`), no alias and no fold applies to the names in it. Scalar variables in a literal `input` are not affected.

Decided behavior:
- Rewrite the keys in `variables` at all depths (nested objects and arrays), by the input type of each variable. The declared type of the variable in the operation gives the target input type; for nested fields, use the type of each field.
- Use the same matcher steps and the same alias tables for each input type (from the alias-table task) as for the document text. `AMBIGUOUS_NAME` and the no-match error work the same way.
- A variable that the operation does not declare is left as it is.

## Acceptance Criteria
- [x] `mutation($i: AddTaskInput!) { addTask(input: $i) { id } }` with `{"i": {"name": "x", "labels": ["bug"], "depends": []}}` works as `title`, `tags`, `dependsOn`.
- [x] A nested list of input objects in a variable is rewritten too.
- [x] A variable key that can mean two fields gives `AMBIGUOUS_NAME`.

## Tests
- [x] Each row of tables 4.2 and 4.3 also in `variables` (the alias-table task has the document-text tests; this task adds the `variables` form).
- [x] A nested array test.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-14 23:29)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift:657` `duplication/duplication` — The new `rewrittenFields` repeats the input-object setup that already exists in `visitValue`. It computes the field types with `fields().mapValues(\.type)`, builds the `AliasScope.inputField` scope, and maps the keys to `CanonicalName` candidates. Copies of this logic drift apart: a change to alias scope or candidate rules must be made in both places. Extract one helper that takes a `GraphQLInputObjectType` and a coordinate and returns the field types and the candidate names. Call it from `visitValue` and from `rewrittenFields`, and delete the copied lines at 657-659.
