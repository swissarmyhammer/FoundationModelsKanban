---
depends_on:
- 01M4B3Z67TC96REJGDHD2DFH0R
- 01M4B3YQSXZCGCB08FVP8QCSF3
position_column: todo
position_ordinal: ae80
title: 'Filter: connect to queries, nextTask, compatibility corpus'
---
## What
Use the filter evaluator in the queries. The basis is plan.md §6.3 (Scoping arguments, Where `filter` applies) and §6 (`nextTask`).
- Scoping arguments of `Board.tasks`: `tag` = `#x`, `assignee` = `@x`, `column` = `%x`, ANDed with `filter`.
- `excludeDone`: with no value, `true`; `false` when a column is named by `column`, a `%` atom, or a column URL.
- Connect `filter` to `Board.tasks`, `Board.nextTask` (not done, ready, matches; sort by column order then ordinal; return the first or `null`), and the `tasks` fields of `Column`, `Actor`, `Tag`.
- Port `../swissarmyhammer/crates/swissarmyhammer-kanban/src/task/next.rs` behavior tests.

## Acceptance Criteria
- [ ] Each filter example in `../swissarmyhammer/crates/swissarmyhammer-tools/src/mcp/tools/kanban/description.md`, `../skills/skills/kanban/SKILL.md`, and `../skills/skills/finish/SKILL.md` gives the same tasks as in Rust, except `$project`, which gives `INVALID_FILTER`.
- [ ] `%done` lists done tasks; `%review || (%todo && #READY)` gives the tasks of both parts; a `tag`, `assignee`, or `column` argument gives the same result as its atom.
- [ ] The ported `next.rs` tests pass.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Filter/FilterCompatibilityTests.swift` and `NextTaskTests.swift`.
- [ ] Run `swift test --filter FilterCompatibilityTests` and `--filter NextTaskTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.