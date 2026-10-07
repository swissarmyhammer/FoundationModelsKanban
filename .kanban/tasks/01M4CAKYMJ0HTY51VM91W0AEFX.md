---
comments:
- actor: wballard
  id: 01m4cb8czbfaht461d48dhqgwb
  text: |-
    Implementation landed (TDD).

    RED: new parameterized test `sameKeyRootFieldsGiveMergedResult` in NameRewriteTests (2 cases: a direct `tasks` with a `tasks` in `... on Query`, and two direct `tasks` fields). It uses `expectSameData(of:as:under: "board")` with the reference `{ board { tasks { totalCount edges { node { id } } } } }`. 2 assertion failures: `data.tasks` had only `totalCount`.

    GREEN: all moved root fields with the same response key now share one `board` key. The new `RewriteWalk.boardKey(forMoving:)` gives the key of an earlier move of the same response key, or makes and records a new `_kanbanRoot<n>` key. Thus the rewritten text has two `_kanbanRoot0: board { … }` fields. GraphQL merges them (`board` has no arguments), and then merges the two `tasks` fields in them, the same as for the fields that the caller wrote. `rootMoves` has one move for each response key, so `callerResult(from:)` and `restoring(_:moving:)` did not change.

    Note: when the two moved fields with one key have different arguments or different canonical names, the caller document is not valid GraphQL. The rewritten document then gives the validation error of overlapping fields, as the caller document would.

    Did not read the validator dump whole: it is 657k characters, more than the read limit. I used the rule list of the dispatch instructions. swiftlint (default rules) shows no line_length finding on the 2 files; its type_body_length and file_length findings existed before this change.
  timestamp: 2026-10-07T23:30:25.387043+00:00
- actor: wballard
  id: 01m4cb8evnn61jwpj2jzy9aa7j
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift, Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift. `swift test --filter NameRewriteTests/sameKeyRootFieldsGiveMergedResult`: RED 2 issues, then GREEN 1 test (2 cases). `swift test --filter NameRewriteTests`: 25 tests passed. `swift test`: 795 tests in 46 suites passed; the only build warning is the accepted mlx "missing creator" kind.
    - next: /review
  timestamp: 2026-10-07T23:30:27.317816+00:00
position_column: doing
position_ordinal: '80'
title: 'Root move: merge two moved root fields with the same response key'
---
## What
`Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift`: each moved root query field gets its own `_kanbanRoot<n>: board { … }` wrapper. When two moved fields have the same response key, `RewrittenDocument.restoring(_:moving:)` keeps only the first value (`OrderedDictionary(restored) { first, _ in first }`). The selections of the second field are lost with no error.

Example: `{ tasks { totalCount } ... on Query { tasks { edges { node { id } } } } }` gives `data.tasks` with `totalCount` only. GraphQL merges the two `tasks` selections, so the caller expects both `totalCount` and `edges`.

The same problem occurs for two direct root fields with the same key, for example `{ tasks { totalCount } tasks { edges { node { id } } } }`.

## Acceptance Criteria
- [x] Two moved root fields with the same response key give one `data.<key>` with the merged result of the two selections.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift`: the two examples above give the same `data.tasks` as `{ board { tasks { totalCount edges { node { id } } } } }` gives under `data.board.tasks`.
- [x] Run `swift test --filter NameRewriteTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.