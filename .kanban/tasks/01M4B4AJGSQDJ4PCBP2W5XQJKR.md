---
depends_on:
- 01M4B3YC73VSKE9VEP29E3CZNQ
position_column: todo
position_ordinal: ac80
title: 'Derived: progress, timeline, summary, broken-merge display'
---
## What
The other read-time fields. The basis is plan.md §5.3 steps 4 and 5, and §6 (Progress).
- `Sources/FoundationModelsKanban/Derived/Progress.swift`: count `- [ ]` / `- [x]` / `- [X]` lines in the body.
- `Derived/Timeline.swift`: `started` (first move to a column that is not the first column, in the current column order) and `completed` (time of the last move, only if the task is now in the terminal column), from the column moves that replay records.
- `Board.summary` counts: total, ready, blocked, done, percent.
- Display rules for a broken merged state: a task in a tombstoned or missing column shows in the first column; a comment on a tombstoned task is hidden; two columns with the same `order` sort by slug; a comment author or a `Change` actor that is a tombstoned actor resolves to the tombstone.

## Acceptance Criteria
- [ ] A new column with a larger `order` changes `completed` of the tasks in the old terminal column.
- [ ] Each broken-merge display rule gives the result that plan.md §5.3 describes.
- [ ] `summary` counts match a hand-counted fixture.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Derived/ProgressTests.swift`, `TimelineTests.swift`, `SummaryTests.swift`, `BrokenMergeDisplayTests.swift`.
- [ ] Run `swift test --filter Derived`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.