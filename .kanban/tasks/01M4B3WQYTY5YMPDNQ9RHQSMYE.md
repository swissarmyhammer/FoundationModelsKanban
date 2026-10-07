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
- actor: wballard
  id: 01m4bcytyc9ht3m6escv2qp0aa
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD; 10 findings (10 confirmed, 1 refuted). ActorNode.swift:9, BoardNode.swift:6, BoardNode.swift:21, ColumnNode.swift:9, ColumnNode.swift:24, CommentNode.swift:10, Node.swift:24, Node.swift:27, TagNode.swift:9, TaskNode.swift:22 (all in Sources/FoundationModelsKanban/Model/).
    - next: Correct all 10 items in the "Review Findings (2026-10-07 09:37)" section. Then do the review again.
  timestamp: 2026-10-07T14:40:54.732888+00:00
- actor: wballard
  id: 01m4bczatd3md8kx6tkd7zzye3
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 9 files (Model/Graph, Node, BoardNode, ColumnNode, ActorNode, TagNode, TaskNode, CommentNode, GraphTests)
    - test: green — swift test, 251 passed, 0 warnings
    - commit: aba8fa7
    - review: findings — Model/ActorNode.swift:9, Model/BoardNode.swift:6, Model/BoardNode.swift:21, Model/ColumnNode.swift:9, Model/ColumnNode.swift:24, Model/CommentNode.swift:10, Model/Node.swift:24, Model/Node.swift:27, Model/TagNode.swift:9, Model/TaskNode.swift:22
  timestamp: 2026-10-07T14:41:10.989589+00:00
- actor: wballard
  id: 01m4bdb6151gr4tfztqht1e62z
  text: |-
    Duplication findings done. Node.swift has one default `updateEdges(using:)` in an `extension NodeState`. The empty copies in ActorNode, BoardNode, and ColumnNode are deleted (no other node type had an empty copy).

    BLOCKER RESOLVED. The 8 `code-hygiene/dead-code-swift` assignOnlyProperty findings had a possible conflict: the card text, the `dead-code-swift` rule, and a dispatch line. The coordinator decided option A: the written `dead-code-swift` rule governs this case (section "assignOnlyProperty and the reads periphery cannot see"). The properties stay, because the card requires them. Each of the 8 named properties has a reason line in its doc comment and `// periphery:ignore` above it.
  timestamp: 2026-10-07T14:47:39.301170+00:00
- actor: wballard
  id: 01m4bdb8y8nn1e9ngvhsbvrhjj
  text: |-
    ### implement — stuck
    - evidence: 4 files — Sources/FoundationModelsKanban/Model/{Node,ActorNode,BoardNode,ColumnNode}.swift; `swift test` 251 tests in 15 suites pass, 0 warnings. 2 of 10 findings checked (duplication). 8 dead-code-swift findings open: a conflict (see the BLOCKER comment).
    - next: a person picks option A, B, or C for the assignOnlyProperty findings. Then /implement again.
  timestamp: 2026-10-07T14:47:42.280250+00:00
- actor: wballard
  id: 01m4bdefzgjt6sd2w26ffwv88v
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsKanban/Model/{Node,ActorNode,BoardNode,ColumnNode,TagNode,TaskNode,CommentNode}.swift; all 10 findings checked. periphery 3.8.0 `--retain-public` on a native build (`swift build --build-tests --build-system native --scratch-path <dir>`, then `--skip-build --index-store-path <dir>/arm64-apple-macosx/debug/index/store`): 0 reports in Sources/FoundationModelsKanban/Model/. `swift test`: 251 tests in 15 suites pass, 0 warnings.
    - discovery: periphery also reports items that this task did not change: assignOnlyProperty `code`, `message`, `path`, `extensions` in GraphQL/Errors.swift, and an unused `import ULID` in Tests/.../Filter/FilterParserTests.swift. The native build gives only the SwiftPM deprecation notice for `--build-system native`.
    - next: /review
  timestamp: 2026-10-07T14:49:27.792914+00:00
- actor: wballard
  id: 01m4bdkefn2mvnqfxwm0tesny1
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 16d3362). 7 files reviewed. 0 findings, 0 confirmed, 0 refuted. All 10 prior items in "Review Findings (2026-10-07 09:37)" are checked.
    - next: The task moved to done. No more work is necessary.
  timestamp: 2026-10-07T14:52:10.101917+00:00
- actor: wballard
  id: 01m4bdkmv1zhz8nfzb37j33yby
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 7 files (Model/Node, ActorNode, BoardNode, ColumnNode, TagNode, TaskNode, CommentNode); 10/10 findings checked
    - test: green — swift test, 251 passed, 0 warnings
    - commit: 16d3362
    - review: clean — 0 findings
  timestamp: 2026-10-07T14:52:16.609217+00:00
depends_on:
- 01M4B3VF41P7FCKEC4MFT9GWA0
position_column: done
position_ordinal: 8c80
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

## Review Findings (2026-10-07 09:37)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 9 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/Model/ActorNode.swift:9` `code-hygiene/dead-code-swift` — var.instance `fields` is assignOnlyProperty.
- [x] `Sources/FoundationModelsKanban/Model/BoardNode.swift:6` `code-hygiene/dead-code-swift` — var.instance `fields` is assignOnlyProperty.
- [x] `Sources/FoundationModelsKanban/Model/BoardNode.swift:21` `duplication/duplication` — Empty `updateEdges` method is a verbatim copy of ActorNode's; consolidate to protocol extension default. Delete lines 18-21 from this file. Add a default implementation to NodeState protocol extension in Node.swift after line 50: `extension NodeState { mutating func updateEdges(using transform: (EdgeTarget) -> EdgeTarget) {} }`.
- [x] `Sources/FoundationModelsKanban/Model/ColumnNode.swift:9` `code-hygiene/dead-code-swift` — var.instance `fields` is assignOnlyProperty.
- [x] `Sources/FoundationModelsKanban/Model/ColumnNode.swift:24` `duplication/duplication` — Empty `updateEdges` method is a verbatim copy of ActorNode's; consolidate to protocol extension default. Delete lines 21-24 from this file. Add a default implementation to NodeState protocol extension in Node.swift after line 50: `extension NodeState { mutating func updateEdges(using transform: (EdgeTarget) -> EdgeTarget) {} }`.
- [x] `Sources/FoundationModelsKanban/Model/CommentNode.swift:10` `code-hygiene/dead-code-swift` — var.instance `fields` is assignOnlyProperty.
- [x] `Sources/FoundationModelsKanban/Model/Node.swift:24` `code-hygiene/dead-code-swift` — var.instance `created` is assignOnlyProperty.
- [x] `Sources/FoundationModelsKanban/Model/Node.swift:27` `code-hygiene/dead-code-swift` — var.instance `updated` is assignOnlyProperty.
- [x] `Sources/FoundationModelsKanban/Model/TagNode.swift:9` `code-hygiene/dead-code-swift` — var.instance `fields` is assignOnlyProperty.
- [x] `Sources/FoundationModelsKanban/Model/TaskNode.swift:22` `code-hygiene/dead-code-swift` — var.instance `fields` is assignOnlyProperty.
