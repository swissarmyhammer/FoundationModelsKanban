---
comments:
- actor: wballard
  id: 01m4bcfs9v79tm9eb6jsexk2bk
  text: |-
    Research done.
    - No ARCHITECTURE.md. plan.md §8 puts Graph.swift and one file for each node type in Model/. I add Model/Node.swift for the shared types (EdgeTarget, NodeFields, NodeState, Node enum).
    - Time values use the existing DateTime scalar (GraphQL/Scalars.swift), the same type as Event.at.
    - The tombstone flag is computed from `deleted` (`isDeleted`), so the two values cannot disagree (state-modeling rule).
    - Stored edges per plan §3.1 and §5.3: Task column, assignees, tags, dependsOn, column moves; Comment task, author; Tag renamedTo. Board, Column, Actor have no edges.
    - Properties such as title, name, order, color, ordinal are not in this card. The replay card adds them when it folds patches.
    - Design: a slot is an index into an array of `Node?`. A ref keeps its slot after a remove, so a later insert of the same ref uses the same slot. A map from a local ref to the slots of the nodes that wait for it makes the resolve on insert cheap (no full scan). A remove scans the table one time.
    - Swift arrays and dictionaries are copy-on-write, so the Graph struct is copy-on-write with no custom buffer.
    - sourcekit-lsp is not installed, so callgraph data comes from tree-sitter only.
  timestamp: 2026-10-07T14:32:41.531780+00:00
- actor: wballard
  id: 01m4bcpgztnk5qnj3172hnk6ez
  text: |-
    Implementation landed (TDD).
    - RED: a stub Graph that stored nodes with no join gave 4 failed tests of 13 in `swift test --filter GraphTests` (join, replace, copy, remove).
    - GREEN: `swift test --filter GraphTests` 13 of 13 pass. Full suite: `swift test` 251 tests in 15 suites pass. Build has 0 warnings.
    - API: `Graph.update(with: Node) -> Int` (insert or replace, like `Set.update(with:)`), `Graph.remove(nodeAt: LocalRef)`, `Graph.slot(for: LocalRef) -> Int?`, `Graph.node(at: Int) -> Node?`. `Node.edges` and `Node.updateEdges(using:)` give one place for the edge walk; each node type implements `updateEdges(using:)`.
    - Each node is found by its own ref (`NodeState.ref`), so a node cannot go into the slot of a different ref.
    - Local checks: swiftlint (no_magic_numbers, missing_docs, force rules) reports nothing except the undocumented `@Test` functions, which the repo style does not document. periphery 3.8.0 `--retain-public` over a native build reports nothing in Sources/ or Tests/. Note: the default `swift build` uses the Swift Build system and writes no index store, so periphery needs `-- --build-system native --scratch-path <dir>`.
    - Divergence from plan.md §8: a new file Model/Node.swift holds EdgeTarget, NodeFields, NodeState, and the Node enum. No ARCHITECTURE.md exists.
  timestamp: 2026-10-07T14:36:22.394434+00:00
- actor: wballard
  id: 01m4bcpjh5454q4djerqfm4xmp
  text: |-
    ### implement — changed
    - evidence: 9 files — Sources/FoundationModelsKanban/Model/{Graph,Node,BoardNode,ColumnNode,ActorNode,TagNode,TaskNode,CommentNode}.swift, Tests/FoundationModelsKanbanTests/Model/GraphTests.swift; `swift test --filter GraphTests` 13/13 pass; `swift test` 251 tests in 15 suites pass, 0 warnings.
    - next: /review
  timestamp: 2026-10-07T14:36:23.973362+00:00
depends_on:
- 01M4B3VF41P7FCKEC4MFT9GWA0
position_column: doing
position_ordinal: '80'
title: 'Graph store: node table with stable slots'
---
## What
The in-memory graph. The basis is plan.md §3.1, §3.3, and §5.3 (Join).
- `Sources/FoundationModelsKanban/Model/Graph.swift`: a Swift value type (copy-on-write). A node table where each node has a stable integer slot. A map `LocalRef → slot`. A slot keeps its number for the life of the graph.
- Node state types in `Model/`: `BoardNode`, `ColumnNode`, `ActorNode`, `TagNode`, `TaskNode`, `CommentNode`. Each has `body`, a tombstone flag, and the time values `created`, `updated`, `deleted`. A task also has its list of column moves (time, column).
- Edges hold `EdgeTarget`: `.slot(Int)` or `.unresolved(StoredRef)`.
- Operations: insert or replace the state in a slot, remove a node from its slot (its edges become unresolved), resolve unresolved edges when a new slot comes.

## Acceptance Criteria
- [x] A replace of one node keeps the edges of other nodes correct.
- [x] A copy of the graph and a change to the copy does not change the original.
- [x] A remove makes the edges to that node unresolved; a later insert resolves them again.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Model/GraphTests.swift`.
- [x] Run `swift test --filter GraphTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.