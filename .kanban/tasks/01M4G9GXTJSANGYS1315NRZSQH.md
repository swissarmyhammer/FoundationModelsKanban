---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gk8x6dfah5qnfha5apd8nk
  text: |-
    Research:
    - `NodeURI.refSegmentCount` uses the board form only when the second-to-last segment is not a node type. The fix: when the last segment is `board`, use `LocalRef.boardSegmentCount`. A `task` or `comment` id cannot be `board` (it is not a ULID), so there is no conflict for them.
    - Consequence: the existing test `columnNamedBoardIsColumn` (`kanban://<key>/column/board` is a column) contradicts the card (a repo named `column` with a board URI). The card wins. The test changes. A column, actor or tag with the slug `board` now has an output URI that parses as a board URI. This is recorded as a new task.
    - All key compares (`NodeURI.localRef(inBoard:)`, `RefResolver`, `FilterEvaluator`, `Schema`, `DependencyWalk`) use the `boardKey` of a parsed `NodeURI`. Thus, normalization of the host in `NodeURI.init(parsing:)` fixes each of them. `BoardKey(remoteURL:)` already makes the host lowercase; the two sites will share one helper `BoardKey.normalizedText(of:)`.
    - Out of scope (new task): a bare board key that is not a URI (the `board:` input in `BoardLocator.resolution`, the board short form in `RefResolver.candidateRef`) is still compared with case.
    - Test fixture key is `local/kanban`. The mutation test uses `KanbanGraphTests.makeGraph(readingKeyWith:)` with a `github.com/...` key.
  timestamp: 2026-10-09T15:07:28.333446+00:00
- actor: claude-code
  id: 01m4gkg60813qxhxwhzvdbkjkq
  text: |-
    Implementation landed (TDD: RED had 17 issues for the right reasons, then GREEN).
    - `NodeURI.refSegmentCount`: when the last segment is `board`, the URI is the board URI. The second-to-last segment is not read.
    - New helper `BoardKey.normalizedText(ofSegments:)` (the name in the research comment, `normalizedText(of:)`, changed). `BoardKey(remoteURL:)` and `NodeURI.init(parsing:)` both use it: the host is lowercase, the path keeps its case.
    - The old test `columnNamedBoardIsColumn` is replaced by `boardURIOfTypeNamedRepo` (10 cases: prefixes `github.com/acme` and `local` x type names `column`, `task`, `actor`, `tag`, `comment`). The card rule makes `kanban://<key>/column/board` the board of key `<key>/column`.
    - `ColumnActorTests.makeFixtureGraph(in:readingKeyWith:)` gets an optional key reader (default: the fake key), so the new mutation tests reuse it.
    - plan.md §3.2: two new bullets, "The host part of a key ignores case" and "Board URI parse".
    - New task ^82s1wf9: a bare board key (not a URI) still compares with case, and a slug `board` gives an id that parses as a board URI.
  timestamp: 2026-10-09T15:11:26.728849+00:00
- actor: claude-code
  id: 01m4gkg8d9pnqk8td37zn94sgy
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsKanban/Identity/NodeURI.swift, Sources/FoundationModelsKanban/Identity/BoardKey.swift, Tests/FoundationModelsKanbanTests/Identity/NodeURITests.swift, Tests/FoundationModelsKanbanTests/Mutations/AddUpdateTaskTests.swift, Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift, plan.md. `swift test --filter "NodeURITests|updateTaskDependsOnMixedCaseHost|mixedCaseHostCycleIsRefused"`: 17 tests pass. `swift test`: 1068 tests in 74 suites pass, 0 failures; the only warning is the accepted SwiftPM "missing creator for mutated node".
    - next: /review
  timestamp: 2026-10-09T15:11:29.193221+00:00
position_column: doing
position_ordinal: '80'
title: Board URI parse and case-insensitive board key host
---
## What
Two defects in board identity (plan.md §3.2).

1. `Sources/FoundationModelsKanban/Identity/NodeURI.swift:79-87` (`refSegmentCount`): when the last segment is `board`, the URI is the board URI `kanban://<board-key>/board`, also when the segment before it is a node type name. Now `kanban://local/tag/board` parses as key `local` + ref `tag/board`, and `kanban://github.com/acme/task/board` throws `invalidULID`. Fix: test for the board form first.
2. `NodeURI.swift:32-34` and `Identity/BoardKey.swift:58`: the key compare is case-sensitive, and the host of an input URI is not made lowercase. `kanban://GitHub.com/o/r/task/<id>` to the current board becomes a remote ref. Fix: when a URI is parsed, normalize the host segment of the key to lowercase, with the same rule as `BoardKey(remoteURL:)`. The path keeps its case.
- Update plan.md §3.2 to say that the host part of a key ignores case.

## Acceptance Criteria
- [x] `NodeURI` parses `kanban://local/tag/board` and `kanban://github.com/acme/task/board` as board URIs with the full key.
- [x] A `dependsOn` URI with `GitHub.com` to a task of the current board is stored as a local ref (`task/<ULID>`).
- [x] The cycle check (rule 6) finds a cycle when one edge uses the uppercase host.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Identity/NodeURITests.swift`: board URIs whose repo name is `task`, `tag`, `column`, `actor`, `comment`; mixed-case host.
- [x] A mutation test (in `Tests/FoundationModelsKanbanTests/Mutations/`): `updateTask(dependsOn:)` with an uppercase host stores a local ref and the task is not blocked when the target is done.
- [x] `swift test --filter NodeURI` and `swift test` pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.