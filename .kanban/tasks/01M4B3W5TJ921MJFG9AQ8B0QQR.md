---
depends_on:
- 01M4B3V22A3PCQRESESTYBQ2FH
position_column: todo
position_ordinal: '8780'
title: 'Body diff: make and reverse a unified diff'
---
## What
Make the diffs that the log stores for a body. The basis is plan.md §5.5.
- `Sources/FoundationModelsKanban/Body/UnifiedDiff.swift`: make a line-based unified diff from text A to text B with Swift `CollectionDifference`. No `---`/`+++` header lines. Each hunk has `@@ -a,b +c,d @@` and 3 lines of context. Use `\ No newline at end of file` as git does.
- Reverse a diff: the `-` and `+` lines change places, and the hunk header ranges change places.
- Parse a diff string into hunks (the apply step in a later task uses it).
- The same input always gives the same output.

## Acceptance Criteria
- [ ] Apply(make(A, B)) to A gives B, for random A and B (use a simple exact apply in the test).
- [ ] Apply(reverse(make(A, B))) to B gives A.
- [ ] A diff from the empty text holds all lines of B as `+` lines.
- [ ] Text with and without a final newline round-trips.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Body/UnifiedDiffTests.swift`: fixed cases plus a property test.
- [ ] Run `swift test --filter UnifiedDiffTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.