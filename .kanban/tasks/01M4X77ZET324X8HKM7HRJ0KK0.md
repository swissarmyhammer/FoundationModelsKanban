---
assignees:
- claude-code
depends_on:
- 01M4X77PG6CNGC9JZYCN9WJGTY
position_column: todo
position_ordinal: a580
title: Accept a title slug and ^^short in the filter, and a title slug as a task ref
---
## What
divergence.md Q25 (DECIDED: support both), C3 (DECIDED), E4 (DECIDED), F1, F2, and §11 "Q25". K4 was not cut. This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problems: the `^` filter does not match by the slug of the task title (F1); Rust matches `^fix-login-bug`. The design allows `^^short` in a filter, but the grammar refuses it (F2).

Decided behavior:
- Filter:
  - Accept `^<title-slug>`. In a filter, it matches all tasks whose title slug is that value (match all), plus the tasks that depend on them, as `^` does now. (Rust keeps only the last task; Swift matches all.)
  - Accept `^^short` (allow `^` after `^`).
  - Code: S/Filter/FilterParser.swift:35-37,221-223 (allow `^` after `^`) and S/Filter/FilterEvaluator.swift:397-408 (`isReferenced`: match the slug of the task title).
- Task ref in a mutation or a query for one task (C3): accept a title slug. It uses the first match (live before tombstone, then lowest ULID), the same rule as a shared short id (Q20). Code: S/Identity/RefResolver.swift (a new title-slug step).
- Resolve order (E4):
  - In a field that takes only tasks: try the ULID, then the short id, then the title slug.
  - In a field that takes many types (for example `node(id:)`): a title slug comes last, after all other slugs. Thus a title slug that is the same as a column slug gives the column.

## Acceptance Criteria
- [ ] `tasks(filter: "^fix-login-bug")` returns each task with the title "Fix login bug" (and their dependents).
- [ ] `tasks(filter: "^^<short>")` parses and works.
- [ ] `updateTask(input: {id: "fix-login-bug", ...})` changes the first matching task.
- [ ] `node(id: "todo")` with a column `todo` and a task titled "Todo" gives the column.
- [ ] A ULID or a short id still wins over a title slug in a task field.

## Tests
- [ ] Both filter forms.
- [ ] A shared title slug in a filter (match all).
- [ ] A title-slug ref in a mutation (first match).
- [ ] A title slug in a task field; a title slug that is the same as a column slug in `node(id:)` gives the column.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.