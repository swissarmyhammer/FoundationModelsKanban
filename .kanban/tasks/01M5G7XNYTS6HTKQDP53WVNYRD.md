---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5g85e8qhn35vndr8tp47jkd
  text: 'Research: verified against code. `Readiness.hasVirtualTag`: READY = live && !isDone && isReady; BLOCKED = live && !isReady (done or not); DELETED = isDeleted; DONE = live && isDone. `BlockerWalk.blockers`: a dependency blocks when `!isDone(target) || hasDependencyPath(from: target, to: slot)`; dependencies come from `Graph.liveDependencies`, which drops tombstoned targets; an unresolved target is not done (`related.isDone`). Terminal column = `ColumnOrder.terminal` = last live column by `order`. `FilterExpr.names` makes `^` and `~task` atoms name DELETED, so they also list deleted tasks (`SchemaDescription.taskFilter` says the same). `SchemaDescription.taskBlockedBy`: blockedBy lists each dependency that is not done or is in a cycle with the task, without unresolved ones — so SKILL.md''s "`blockedBy` lists the dependencies that are not done" is also wrong and in scope. SKILL.md already uses `INCOMPATIBLE_BOARD` (matches `Errors.swift`); no `BOARD_INCOMPATIBLE` in the file. KanbanSkillTests reads SKILL.md (virtual tag table names each tag, examples run). No validators match .md files.'
  timestamp: 2026-10-21T22:09:02.231091+00:00
- actor: claude-code
  id: 01m5g88btbvv9xtw0xsbazsmq2
  text: |-
    ### implement — changed
    - evidence: 1 file — Documentation/kanban/SKILL.md. Rewrote the nextTask ready sentence, the Dependencies lead sentence (a dependency blocks when not done or it leads back to the task; a dependency on a deleted task is ignored), the `blockedBy` bullet (lists the blocking dependencies, not the unresolved ones — the old "not done" wording missed done dependencies in a cycle), and the READY/BLOCKED/DELETED/DONE table rows (DELETED now names `^id` and `~task` atoms). `INCOMPATIBLE_BOARD` was already correct; no `BOARD_INCOMPATIBLE` in the file. `swift test --filter KanbanSkillTests`: 8 tests passed. `swift test`: 1750 tests in 146 suites passed, 0 failures, no compiler warnings (only the external mlx-swift bundle "missing creator" build-system note).
    - next: /review. Not committed.
  timestamp: 2026-10-21T22:10:38.027786+00:00
position_column: doing
position_ordinal: '80'
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
- [x] The SKILL.md virtual tag table, the nextTask paragraph, and the blocked sentence match the code
- [x] KanbanSkillTests pass

## Tests
- [x] `swift test` is green