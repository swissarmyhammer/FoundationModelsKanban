---
depends_on:
- 01M4B3XTMZSS5T07B8HEZXK9ZH
- 01M4B3XZ1QTBXDAFR0ZPWAFXGZ
position_column: todo
position_ordinal: '9280'
title: 'Derived fields: readiness and virtual tags'
---
## What
Readiness and virtual tags at read time. The basis is plan.md §5.3 step 4 and §6 (Terminal column, `ready`, Virtual tags). Progress, times, summary, and the broken-merge display rules are in a separate task.
- `Sources/FoundationModelsKanban/Derived/Readiness.swift`: terminal column (max `order`), done, `ready` (all `dependsOn` targets done; an unknown or unresolved target counts as not done), `blockedBy`, `blocks`. A cycle from a merge: each task in the cycle is blocked, and the walk stops at a visited task.
- `Derived/VirtualTags.swift`: `READY` (not done, all dependencies done), `BLOCKED` (at least one dependency not done), `BLOCKING` (not done, some task depends on it) — port `../swissarmyhammer/crates/swissarmyhammer-kanban/src/virtual_tags.rs` — and `CONFLICT` (the body has a conflict block).

## Acceptance Criteria
- [ ] A task that depends on an unknown task is blocked.
- [ ] A dependency cycle from a merge gives blocked tasks, and the walk ends.
- [ ] The ported `virtual_tags.rs` tests pass, and a task with a conflict block has `CONFLICT`.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Derived/ReadinessTests.swift` and `VirtualTagsTests.swift`.
- [ ] Run `swift test --filter ReadinessTests` and `--filter VirtualTagsTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.