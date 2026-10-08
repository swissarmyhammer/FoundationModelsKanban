---
assignees:
- claude-code
depends_on:
- 01M4EGCVYHARE5N564SE2WKEQZ
position_column: todo
position_ordinal: '80'
title: 'No filter means no filter: done tasks are not hidden by default'
---
## What
A person said on 2026-10-08: "for 'all tasks' you should have 'no filter' not some conjunction. no filter means no filter". Today a task list leaves out done tasks unless the filter names `#DONE` or a column (^5qzeq1h), so "all tasks" needs `#DONE || !#DONE`. That is wrong.

- Remove `DONE` from the "hidden unless named" set in `Filter/TaskFilter.swift` / `Derived/VirtualTags.swift`. A task list with no filter gives every live task, done ones included. A filter selects exactly what it says: `!#DONE` gives the open tasks, `#DONE` the done tasks.
- `DELETED` stays hidden unless named: a deleted task is a tombstone, not a task on the board. (If the person wants tombstones in "no filter" too, that is a one-line change of the set.)
- `nextTask` is not changed: it picks only `READY` tasks, and a done task is never `READY`.
- Remove the code that only the `DONE` default and the "a column names DONE" rule use. Keep one mechanism for the hidden set.
- Update the tests that expect done tasks to be left out by default, `Column`/`Actor`/`Tag` `tasks(filter)`, `searchTasks`, the history and subscription filter, plan.md §6.3 ("Default selection"), and any example that uses `#DONE || !#DONE`.

## Acceptance Criteria
- [ ] `tasks` with no filter gives every live task, done included; `!#DONE` gives the open tasks; `#DONE` the done tasks.
- [ ] `#DELETED` is still the only way to list tombstones.
- [ ] No text in the repo says `#DONE || !#DONE`.

## Tests
- [ ] Change the default-selection tests and add one for no filter with a done task; keep the `#DELETED` tests.
- [ ] Run the full `swift test`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.