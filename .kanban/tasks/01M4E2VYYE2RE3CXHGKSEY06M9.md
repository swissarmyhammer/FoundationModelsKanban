---
assignees:
- claude-code
depends_on:
- 01M4E2MCSNEA5GS581W5QZEQ1H
position_column: todo
position_ordinal: '8180'
title: history and changes take only the filter
---
## What
A person decided on 2026-10-08: shortcut verbs (for example `completeTask`) stay, but the API must not mix filter arguments with filter expressions. `Board.history(type, node, actor, filter, derived, since, first)` and `Subscription.changes(board, type, node, actor, filter, derived)` have the same mix as the task lists had (see ^5qzeq1h).

- Remove the `type`, `node` and `actor` arguments of `history` and `changes`. Express each one in the filter:
  - `node` → the `^id` atom (a node, any type).
  - `type` → a new atom for the node type, for example `$task`, `$column`, `$tag`, `$actor`, `$comment`, `$board`. Use the same atom syntax rules as the other atoms.
  - `actor` (the author of the change) → see the open question below.
- The filter of `history` and `changes` selects the updates whose node matches. A `Change` is in the result when at least one of its updates matches. `Change.updates(type, node)` takes only a `filter` too.
- Keep `board` on `changes` (it names the board to watch, not a filter), and keep `since` and `first` (paging).
- Use the parser, the evaluator and the generic derived-tag mechanism of ^d8wwdgy and ^5qzeq1h. Do not add a second filter path.
- Update plan.md §6.5 and §6.7, the tool description, and the CLI help.

## Open question (blocks the start)
- How does the filter name the author of a change? `@x` already means "assigned to x" for a task. Options: a new author atom, or `@x` matches the author for change filters.
- Does `derived: Boolean` become a derived tag of an update (for example `#DERIVED`), or does it stay?

## Acceptance Criteria
- [ ] `kanban --schema` shows `history(filter, since, first)`, `changes(board, filter)` and `updates(filter)` with no `type`, `node` or `actor` argument.
- [ ] Each removed argument has a filter expression with the same result, and a test proves it.

## Tests
- [ ] Change the history and subscription tests that use the removed arguments to filter expressions, with the same expected results.
- [ ] Run the full `swift test`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.