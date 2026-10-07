---
depends_on:
- 01M4B4002GZV6E43G5CQ74BJNZ
position_column: todo
position_ordinal: 9a80
title: 'Mutations: tags and tag rename'
---
## What
Tag mutations. The basis is plan.md §4.2 and §6.2. Comment mutations are in a separate task.
- `addTag`/`updateTag`/`deleteTag`/`undeleteTag(id, name, color, body)`: `addTag` is idempotent on slug; `updateTag` does not change the slug; auto color when no color is given; tag name rule (`INVALID_TAG_NAME`).
- `renameTag(from!, to!)`: new tag `set` (copied values, only if `to` does not exist), and old tag `set renamedTo = tag/<to>`. A rename to an existing slug is a merge (only the redirect). A rename that makes a cycle gives `TAG_RENAME_CYCLE`.
- All refs to a redirected slug follow the redirect (`addTag` returns the target and writes nothing, `updateTag`, `deleteTag`, `renameTag`).

## Acceptance Criteria
- [ ] After `renameTag(bug → defect)`, tasks with `bug` show `defect`, `#bug` and `#defect` both match, and `addTask(tags: ["bug"])` writes an edge to `defect`.
- [ ] `deleteTag(id: "bug")` after the rename deletes `defect`; a rename cycle gives `TAG_RENAME_CYCLE`.
- [ ] A rename to an existing tag writes only the redirect.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Mutations/TagMutationTests.swift`: rename, chain, merge rename, cycle refusal, undelete, plus the matching Rust dispatch tests.
- [ ] Run `swift test --filter TagMutationTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.