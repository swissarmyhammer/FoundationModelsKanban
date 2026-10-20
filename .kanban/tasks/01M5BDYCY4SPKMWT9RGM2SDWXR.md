---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5be6kq8a071kyhr552f0pe2
  text: |-
    Research: there were 3 sites. BoardCollect.swift `CollectedSource.read` (sort of the node refs) and `CollectMerge.sharedNodes` (sort by `node.description`), and Loader.swift `StagedLog.precedes`. A grep of Sources/ found no other sort of local refs on `description`. The only remaining `description <` compare is the `LocalRef.<` operator itself. BoardLock sorts `BoardKey` text, not local refs, so it is out of scope.

    Changes: `CollectedSource.read` now uses `.sorted()`. `sharedNodes` now uses `lhs.node < rhs.node`. `StagedLog.precedes` now uses `lhs.ref < rhs.ref`, and its doc comment now names the `LocalRef` order. `LocalRef.<` compares the same text, so the order does not change.

    TDD: this is a refactor that keeps the same behavior, so no new test can fail first. The current tests of the collect merge order and of the loader join order cover it. The collectBoards board-log behavior (^16js6jx) did not change.
  timestamp: 2026-10-20T01:18:19.880186+00:00
- actor: claude-code
  id: 01m5be6n4c5rkbd2t9576m3tma
  text: |-
    ### implement — changed
    - evidence: 2 files: Sources/FoundationModelsKanban/CrossRepo/BoardCollect.swift, Sources/FoundationModelsKanban/Events/Loader.swift. `swift test`: 1701 tests in 140 suites passed, 0 failures. The only compiler warning is the accepted SwiftPM "missing creator" warning.
    - next: /review
  timestamp: 2026-10-20T01:18:21.324259+00:00
position_column: doing
position_ordinal: '80'
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
- [x] No source file sorts local refs with a comparator on `description`.
- [x] `swift test` passes.