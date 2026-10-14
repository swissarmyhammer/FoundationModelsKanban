---
assignees:
- claude-code
depends_on:
- 01M4X7471GDT9W0J6PWBQTQ6H3
position_column: todo
position_ordinal: '9880'
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
- [ ] `mutation($i: AddTaskInput!) { addTask(input: $i) { id } }` with `{"i": {"name": "x", "labels": ["bug"], "depends": []}}` works as `title`, `tags`, `dependsOn`.
- [ ] A nested list of input objects in a variable is rewritten too.
- [ ] A variable key that can mean two fields gives `AMBIGUOUS_NAME`.

## Tests
- [ ] Each row of tables 4.2 and 4.3 also in `variables` (the alias-table task has the document-text tests; this task adds the `variables` form).
- [ ] A nested array test.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.