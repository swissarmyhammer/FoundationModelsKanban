---
depends_on:
- 01M4B3YQSXZCGCB08FVP8QCSF3
position_column: todo
position_ordinal: 9c80
title: 'Forgiving names: the name matcher'
---
## What
Match a wrong name to one canonical name. The basis is plan.md §4.5 (Match steps, Rules).
- `Sources/FoundationModelsKanban/GraphQL/NameMatcher.swift`: given a name and the list of valid names at one position, try in order and stop at the first step with exactly one match: exact; same case and style (`camelCase`, `snake_case`, `kebab-case`, any case); singular or plural; for a top-level mutation, the other word order and the verb synonyms (`create`/`new`/`insert` → `add`, `remove`/`rm`/`del` → `delete`, `edit`/`modify`/`set`/`patch` → `update`, `mv` → `move`, `done`/`finish`/`close` → `complete`, `label` → `tag`, `unlabel` → `untag`, `restore`/`unarchive`/`recover` → `undelete`, `archive` → `delete`); the alias table; one changed, added, or removed letter (names of 4 or more letters).
- A tie at a step gives a result that lists the matches; no guess.
- A list of mappings that are never made (for example `create` never maps to `init`).
- Aliases are declared in Swift next to each field (for example `description`/`desc`/`text`/`content` → `body`, `status` → `column`, `assignee` → `assignees`, `task_id` → `id`).

## Acceptance Criteria
- [ ] `taskAdd`, `createTask`, `create_task` each give `addTask`.
- [ ] A tie gives the list of matches, not one name.
- [ ] `createBoard` does not give `initBoard`.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/GraphQL/NameMatcherTests.swift`: each step, ties, the never list.
- [ ] Run `swift test --filter NameMatcherTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.