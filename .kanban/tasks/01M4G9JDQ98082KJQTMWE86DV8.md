---
assignees:
- claude-code
depends_on:
- 01M4G9J9NMNJR8NZPSYPC53Z77
position_column: todo
position_ordinal: 8a80
title: Rename to a deleted tag makes the target tag live again
---
## What
`Sources/FoundationModelsKanban/GraphQL/TagMutations.swift:234-241`: `graph.hasNode(target)` is true for a tombstone. Thus a rename to a deleted slug writes only `renamedTo`, and the target stays deleted. Each task with the old tag loses it, and the mutation returns a tombstone. plan.md §6.2: "Rename to a slug that exists is a merge."

- When the target exists and is a tombstone, also write `delete: false` on the target, the same as `ensureLiveTag` and `tagRefs` do.
- Undo of the rename must reverse both patches.

## Acceptance Criteria
- [ ] `deleteTag(defect)`, then `renameTag(from:"bug", to:"defect")`: the target is live, and each task that had `bug` has `defect`.
- [ ] `undo` of that rename gives the state from before the rename (the target deleted, tasks with `bug`).

## Tests
- [ ] Tests in `Tests/FoundationModelsKanbanTests/Tags/` (tag rename tests).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.