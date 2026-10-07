---
depends_on:
- 01M4B3ZDK527CRVKQQRT87RGHJ
- 01M4B3Y4M87387J50EQCD36VB0
- 01M4B4A8735GAP57Q8ZVDP5HY2
position_column: todo
position_ordinal: '9780'
title: 'Mutations: board, auto-init, session actor'
---
## What
The first public mutations and the rules that all later mutations use. The basis is plan.md §4.2 and §6. Column and actor mutations are in a separate task.
- `Sources/FoundationModelsKanban/GraphQL/MutationResolvers.swift` (board part): `initBoard(name, body)` (default columns `todo` "To Do" 0, `doing` "Doing" 1, `review` "Review" 2, `done` "Done" 3; on an existing board only the given fields that differ) and `updateBoard(name, body)`. Each mutation takes one `input` object; `input` is optional when it has no required field.
- `body` input: full text; the tool writes an `edit` patch with the diff from the current body, and nothing if the text is equal.
- Auto-init: the first mutation on a repo with no board makes the board with the default columns; the default name is the repo directory name.
- Session actor: the `actor` of `KanbanGraph.init`, else the OS user. A call that writes to a board makes sure that the session actor exists there (an actor `set` patch if it is new).

## Acceptance Criteria
- [ ] The first mutation in an empty repo makes the board, the 4 columns, and the session actor.
- [ ] `mutation { initBoard { name } }` (no `input`) works; a no-op mutation writes no patch.
- [ ] No log line holds the key of its own board.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Mutations/BoardMutationTests.swift`: port the Rust auto-init and session actor fallback dispatch tests as GraphQL documents.
- [ ] Run `swift test --filter BoardMutationTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.