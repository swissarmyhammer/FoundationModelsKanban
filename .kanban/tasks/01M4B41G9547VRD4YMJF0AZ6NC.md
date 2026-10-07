---
depends_on:
- 01M4B40W9YCS7ZKYB43KFK6T3Z
- 01M4B406Z7RVSBJKKJ8KJW0CY2
- 01M4B40CFSF002B4DKM3T8J6GV
- 01M4B4B57JFX8HA0B45MMDQ1SQ
- 01M4B4B1G28KK1NVCXHK9GDAYR
position_column: todo
position_ordinal: 9f80
title: 'Forgiving names: rewrite the document'
---
## What
Rewrite the parsed GraphQL document before validation. The basis is plan.md §4.5 (Positions, Rules) and §12 items 14 and 16.
- `Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift`: walk the parsed document and use `NameMatcher` at each position: top-level mutation, field in a selection, argument and `input` field, enum value, root query field.
- Keep the response key: add a GraphQL alias (`taskAdd: addTask(...)`, `desc: body`). Keep an alias that the caller wrote.
- Root query field: if the root has no such field but `Board` has it, move it into `board { … }`, and after execution move the result back, so the response has `data.tasks`.
- `extensions.rewrites`: a list of `{ from, to, path }`.
- A tie gives an error that lists the matches. No match: normal validation runs and gives the "did you mean" error.

## Acceptance Criteria
- [ ] `taskAdd`, `addTask`, and `createTask` give the same patches, and the response key is the name that the caller wrote; `createBoard` does not map to `initBoard`.
- [ ] `archiveTask` runs `deleteTask`, and `restoreTask` runs `undeleteTask`, through `execute`.
- [ ] `{ tasks { … } }` gives the same result as `{ board { tasks { … } } }`, under `data.tasks`; each rewrite is in `extensions.rewrites`.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift`: wrong case, `snake_case`, plural, alias, one wrong letter, at each position; ties; root move; the archive and restore verbs.
- [ ] Run `swift test --filter NameRewriteTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.