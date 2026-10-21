---
assignees:
- claude-code
position_column: todo
position_ordinal: '8680'
title: Correct the READY, BLOCKED and DELETED text in Documentation/kanban/SKILL.md to match the virtual tag rules
---
## What
^dd9g87w corrected `VirtualTag.explanation` (Sources/FoundationModelsKanban/Derived/VirtualTags.swift), but Documentation/kanban/SKILL.md still has the old wording:
- The virtual tag table: `READY` "is open, and each of its dependencies is done."; `BLOCKED` "has at least one dependency that is not done."; `DELETED` "A list shows a deleted task only when the filter names `#DELETED`."; `DONE` "is in the last column."
- The `nextTask` paragraph: "A ready task is open, and each of its dependencies is done."
- "A task is blocked until each of its dependencies is done."

The code (`Readiness.hasVirtualTag`, `BlockerWalk.blockers(ofTaskAt:)`, `Graph.liveDependencies`): READY = live, not done, no dependency blocks it. BLOCKED = live (done or not), and a dependency that is not a tombstone is not done or leads back to the task through dependencies; a dependency that no loaded board has is not done. A tombstoned dependency is ignored. DONE = live and in the terminal column. A deleted task also shows for a ^id or ~task filter atom (see `SchemaDescription.taskFilter`).

Rewrite those lines so they are plainly true. Keep the wording short.

## Acceptance Criteria
- [ ] The SKILL.md virtual tag table, the nextTask paragraph, and the blocked sentence match the code
- [ ] KanbanSkillTests pass

## Tests
- [ ] `swift test` is green