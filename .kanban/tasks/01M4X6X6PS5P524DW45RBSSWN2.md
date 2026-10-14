---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Add one warnings list to each GraphQL response
---
## What
divergence.md §14 "Warnings" (DECIDED with P1–P4): use one list for all warnings in the response, at `extensions.warnings`. This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

- Add one warnings collector for each call of `KanbanGraph.execute`. Resolvers, the name rewrite, and the load of related boards append to it.
- Put the list in the response as `extensions.warnings` (an array of strings, or of objects with `message` and an optional `code`). When the list is empty, do not add the key.
- These later tasks write to this list: Q7 (a related board that cannot be read), P1 (an unknown `before`/`after` ref), P2 (`priority`), P3 (a `dependsOn` URI to a missing task), and P4 (a removed Rust parameter). Make the API easy to call from a resolver and from the name rewrite (which runs before the engine).
- The tool output (`KanbanTool`) must show the warnings to the agent.
- Warnings of one call must not leak into a different call (calls can run at the same time).

## Acceptance Criteria
- [ ] A call that adds a warning returns it in `extensions.warnings`.
- [ ] A call with no warning has no `extensions.warnings` key.
- [ ] Two calls at the same time each get only their own warnings.
- [ ] The `KanbanTool` result shows the warnings.

## Tests
- [ ] A test resolver (or the name rewrite) that adds a warning, and a check that the response has it.
- [ ] A test that two calls at the same time do not share warnings.
- [ ] A `KanbanTool` test that the warning text is in the tool result.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.