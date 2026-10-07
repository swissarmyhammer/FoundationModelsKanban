---
depends_on:
- 01M4B3WK197P3T3VZHX3JHWP3E
- 01M4B3WQYTY5YMPDNQ9RHQSMYE
- 01M4B3X4CTB14YMDBTK59N8JA0
position_column: todo
position_ordinal: 8d80
title: 'Replay: fold the events of one node'
---
## What
Build the state of one node from its own log lines. The basis is plan.md §5.3 steps 1 to 3.
- `Sources/FoundationModelsKanban/Events/Replay.swift`: take the lines of one file, skip a line that does not decode (log it with swift-log), sort the events by event `id`, and apply each patch to an empty node state.
- `set` (later wins), `unset`, `add`/`remove` on set-valued properties, `delete: true`/`false`, and `edit` (apply the body diff with `DiffApply`; record a conflict flag).
- Time values from the envelope `at`: `created` (first patch), `updated` (last patch), `deleted` (last `delete: true`, only while it is a tombstone). For a task, record each `set column` as a pair (time, column).
- Unknown properties are kept but not read (plan.md §5.3, schema changes).

## Acceptance Criteria
- [ ] Shuffle the lines of a file in random orders: the folded state and the time values are always the same.
- [ ] A bad line is skipped and the other lines still fold.
- [ ] Two `set title` patches give the value of the patch with the larger event id, for any line order.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Events/ReplayTests.swift`: each patch part, the time values, the shuffle test, bad lines, unknown properties.
- [ ] Run `swift test --filter ReplayTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.