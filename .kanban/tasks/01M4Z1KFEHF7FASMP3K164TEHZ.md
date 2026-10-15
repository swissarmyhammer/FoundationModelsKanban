---
assignees:
- claude-code
position_column: todo
position_ordinal: af80
title: Take out the unused variable definition when the rewrite removes a removed Rust parameter whose value is a variable
---
## What
This is work on the Swift package (S/ = Sources/FoundationModelsKanban/). Code: S/GraphQL/NameRewrite.swift.

The name rewrite takes a removed Rust parameter (`RemovedParameter`, divergence.md Q12 as P4 changed it) out of the document with a warning. When the value of that parameter is a variable, for example `mutation($d: String) { addTask(input: {title: "x", due: $d}) { id } }`, the variable `$d` has no use after the rewrite. GraphQL then gives the NoUnusedVariables validation error, and the call fails. This is not forgiving.

The walk does not know all the uses of a variable: it does not visit directive arguments, and it records only the first use.

## Acceptance Criteria
- [ ] A removed parameter whose value is a variable works: the call runs, and the response has the "removed" warning.
- [ ] When the variable has other uses (also in a directive), its definition stays.
- [ ] When the variable has no other use, the rewrite takes out its definition (and the parentheses when no definition stays).

## Tests
- [ ] A test for each criterion. Use temporary fixture folders. Never use the `.kanban/` of this repo.
- [ ] `swift test` passes.

Found while working on ^y8nr5v3.