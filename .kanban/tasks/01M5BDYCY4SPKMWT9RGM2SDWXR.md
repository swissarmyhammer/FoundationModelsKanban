---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: Use the LocalRef order in BoardCollect and the loader in place of the text comparators
---
## What
`LocalRef` is now `Comparable` by its text (^ye4xk09). Some files still sort local refs with a comparator on `description`:
- `Sources/FoundationModelsKanban/CrossRepo/BoardCollect.swift`: the sort of the node refs of a source board, and the sort of the shared nodes by `node.description`.
- `Sources/FoundationModelsKanban/Events/Loader.swift`: `StagedLog.precedes` compares `ref.description`.

## Do
- Use the `LocalRef` order (`sorted()`, or `lhs.ref < rhs.ref`) at each site. Keep the same order.
- Use the file editing tool only. Do not edit plan.md.

## Acceptance Criteria
- [ ] No source file sorts local refs with a comparator on `description`.
- [ ] `swift test` passes.