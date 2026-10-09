---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gwnrtqdfft154qynbaebhy
  text: |-
    Research:
    - `WorkingCopy.renameTag` (GraphQL/TagMutations.swift) writes the new tag only when `graph.hasNode(target)` is false. A tombstone target gets only the `renamedTo` patch on the source.
    - `WorkingCopy.ensureLiveTag` already does the correct thing for both cases: an unknown tag gets one add patch, and a known tag follows the rename redirect and gets `delete: false` at the end of the chain (`apply` writes no patch for a live tag). Plan: `renameTag` calls `ensureLiveTag(target, setting:body:at:)` in place of its own `hasNode` branch. This removes the copy of the add branch.
    - Choice (task leaves it open): when the target slug is itself redirected, the undelete goes to the end of the target chain, the same as `ensureLiveTag` and `addTag` (plan.md §6.2: all refs to a redirected slug follow the redirect).
    - Undo: the inverse of `delete: false` is `delete: true`, and the inverse of the `renamedTo` set is an unset. No undo code change is expected.
    - Test helpers: session tests in `Undo/UndoTests.swift` (`projection(of:)`, `reverse(in:)`), `ChangeBuilderTests.baseSession` (adds tag `bug`), `TagMutationTests` field builders. The new test file goes in `Tests/FoundationModelsKanbanTests/Tags/`.
  timestamp: 2026-10-09T17:51:47.031881+00:00
- actor: claude-code
  id: 01m4gwvj2pcr1b802hvz4gt1dm
  text: |-
    Implementation:
    - RED: 3 new tests in `Tests/FoundationModelsKanbanTests/Tags/TagRenameToTombstoneTests.swift` failed for the expected reason (the rename returned `deleted` set, the task had no tags, the target log had no `delete: false`).
    - GREEN: `WorkingCopy.renameTag` now calls `ensureLiveTag(target, setting:body:at:)` in place of its own `hasNode` branch. An unknown target gets the add patch as before; a known target follows its rename chain, and a tombstone at the end gets `delete: false`. No undo code change was necessary: the undo writes `delete: true` on the target and unsets `renamedTo`, and the full projection equals the projection before the rename.
    - `TagMutationTests.autoColorSetting(of:)` is now internal, so the new suite reuses it.
    - plan.md §6.2 "Rename to a slug that exists" now states the `delete: false` patch and the undo.
    - Choice: when the target slug is itself redirected, the `delete: false` goes to the end of the target chain, the same as `addTag` (plan.md §6.2: all refs to a redirected slug follow the redirect).
  timestamp: 2026-10-09T17:54:56.726990+00:00
- actor: claude-code
  id: 01m4gwvkwvyh0p34pncgzgwwqp
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/GraphQL/TagMutations.swift, Tests/FoundationModelsKanbanTests/Tags/TagRenameToTombstoneTests.swift (new), Tests/FoundationModelsKanbanTests/Mutations/TagMutationTests.swift, plan.md. `swift test --filter TagRenameToTombstoneTests`: 3 passed. `swift test`: 1092 tests in 79 suites passed; only build warning is the accepted SwiftPM "missing creator for mutated node".
    - next: /review
  timestamp: 2026-10-09T17:54:58.587971+00:00
depends_on:
- 01M4G9J9NMNJR8NZPSYPC53Z77
position_column: doing
position_ordinal: '80'
title: Rename to a deleted tag makes the target tag live again
---
## What
`Sources/FoundationModelsKanban/GraphQL/TagMutations.swift:234-241`: `graph.hasNode(target)` is true for a tombstone. Thus a rename to a deleted slug writes only `renamedTo`, and the target stays deleted. Each task with the old tag loses it, and the mutation returns a tombstone. plan.md §6.2: "Rename to a slug that exists is a merge."

- When the target exists and is a tombstone, also write `delete: false` on the target, the same as `ensureLiveTag` and `tagRefs` do.
- Undo of the rename must reverse both patches.

## Acceptance Criteria
- [x] `deleteTag(defect)`, then `renameTag(from:"bug", to:"defect")`: the target is live, and each task that had `bug` has `defect`.
- [x] `undo` of that rename gives the state from before the rename (the target deleted, tasks with `bug`).

## Tests
- [x] Tests in `Tests/FoundationModelsKanbanTests/Tags/` (tag rename tests).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.