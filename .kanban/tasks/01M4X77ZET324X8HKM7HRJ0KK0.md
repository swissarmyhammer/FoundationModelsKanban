---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4zwmqz56g9x1bmh4xt51wyv
  text: |-
    Research done.
    - RefResolver.candidateRef sends .task and .comment to ulidRef. The plan: add a title-slug step for .task after ulidRef gives nil. A Lookup flag turns the step off in the anyLocalRef type loop, and anyLocalRef tries the title slug after all slug types (E4), so a column slug wins.
    - The first match uses the existing precedes order (live before tombstone, then lowest ULID). A shared title slug gives a warning, the same as SHARED_SHORT_ID.
    - Slug.normalizedText (Tags/TagSlug.swift) drops a leading `^`, so `^fix-login-bug` and `Fix login bug` both give `fix-login-bug`.
    - Rust has_ref (task_helpers.rs) ORs the title slug with the ULID match: the task itself or a task whose depends_on has the slug task. Swift matches each task with that slug (C3).
    - FilterParser: `^` is a body stop character, so `^^x` fails with missingBody. The fix is to drop the extra `^` after the `^` sigil.
  timestamp: 2026-10-15T13:39:49.861265+00:00
- actor: claude-code
  id: 01m4zxedp2ghwxahzb1xe3x018
  text: |-
    Implementation landed (TDD: red first for each part, then green).
    - Filter parser: after the `^` sigil, each next `^` is part of the sigil, so `^^short` and `^^^short` give `^short`. `^^` with no body gives the missing-body error over the two sigils.
    - Filter evaluator: `^value` also matches each task whose title slug is the slug of the value, and each task that depends on one of them (match all, C3). The ULID match stays, and the two are ORed, the same as Rust `has_ref`.
    - RefResolver: new `Graph.taskSlots(withTitleSlugOf:)`. For `.task` lookups, the title slug is the last step after ulidRef. `node(id:)` (anyLocalRef) turns the step off in the type loop and tries the title slug after all other slugs (E4), so a column slug wins. A shared title slug uses the Q20 first-match order and gives a new `SHARED_TITLE_SLUG` warning. `firstMatch` now takes a `SharedForm` (shortID or titleSlug); the SHARED_SHORT_ID message text did not change.
    - Descriptions: KanbanTool description, the filter grammar text, and the AddTaskInput/UpdateTaskInput dependsOn texts name the title slug and `^^short`. README filter section too.
    - Discovery: dependsOn and other task-ref fields now also take a title slug, because they all go through storedRef(.task).
  timestamp: 2026-10-15T13:53:51.298008+00:00
- actor: claude-code
  id: 01m4zxeg2rgemh58hrjdf1pb4d
  text: |-
    ### implement — changed
    - evidence: `swift test` 1459 tests in 112 suites passed; only the accepted mlx "missing creator" warning. Files: Sources/FoundationModelsKanban/Filter/FilterParser.swift, Filter/FilterEvaluator.swift, Identity/RefResolver.swift, GraphQL/SchemaDescription.swift, Tool/KanbanTool.swift, README.md, Tests/.../Identity/TitleSlugRefTests.swift (new), Filter/FilterParserTests.swift, GraphQL/SchemaDescriptionTests.swift, Tool/KanbanToolTests.swift
    - next: /review
  timestamp: 2026-10-15T13:53:53.752311+00:00
depends_on:
- 01M4X77PG6CNGC9JZYCN9WJGTY
position_column: doing
position_ordinal: '80'
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
- [x] `tasks(filter: "^fix-login-bug")` returns each task with the title "Fix login bug" (and their dependents).
- [x] `tasks(filter: "^^<short>")` parses and works.
- [x] `updateTask(input: {id: "fix-login-bug", ...})` changes the first matching task.
- [x] `node(id: "todo")` with a column `todo` and a task titled "Todo" gives the column.
- [x] A ULID or a short id still wins over a title slug in a task field.

## Tests
- [x] Both filter forms.
- [x] A shared title slug in a filter (match all).
- [x] A title-slug ref in a mutation (first match).
- [x] A title slug in a task field; a title slug that is the same as a column slug in `node(id:)` gives the column.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.