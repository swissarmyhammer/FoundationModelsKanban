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
- actor: claude-code
  id: 01m4gkq9rawr4nqd7jv74053x0
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 6 files
    - test: green — swift test, 1068 tests in 74 suites passed
    - commit: c9a7756
    - review: findings — Sources/FoundationModelsKanban/Identity/NodeURI.swift:83
  timestamp: 2026-10-09T15:15:19.946790+00:00
- actor: claude-code
  id: 01m4gqcp5ehfeakhy4zqgsa770
  text: |-
    Round 2 research (finding NodeURI.swift:83, decision: the slug `board` is reserved).
    - The owner answered a question: display names are not restricted. `updateColumn`, `updateActor` and `updateTag` change only the display name; the slug and the URI do not change. Thus these mutations refuse nothing. The rule applies to the slug of a node that a mutation makes.
    - Creation paths of a column, actor, or tag: `WorkingCopy.addNode` (addColumn, addActor, moveTask auto column, `ensureLiveTag` for addTag / tagRefs of addTask, updateTask, tagTask / #marker tags, renameTag target). Two paths do not use `addNode`: `authorRef` in CommentMutations (an unknown author actor gets a `set` patch) and `KanbanGraph.sessionActor(named:)`.
    - Existing pattern: two `KanbanError` cases can share one code (`notFound` and `boardNotFound`). New cases `reservedSlug(name:)` (INVALID_SLUG) and `reservedTagName(name:)` (INVALID_TAG_NAME) keep the old `invalidSlug`/`invalidTagName` messages and callers.
    - `TagName(normalizing:)` and `Slug(columnOrActorName:)` also run in lookups (RefResolver, TagMarkers at read time). The check must not go there, or an old log with `#board` would read differently.
    - Replay does not call the mutation code, so an old log with a `board` node still loads.
    - Reserved slug constant: `PatchNodeType.board.pathSegment` (the board segment of the board URI).
  timestamp: 2026-10-09T16:19:26.510064+00:00
- actor: claude-code
  id: 01m4gqvzv6yhk8amw7s6nzadre
  text: |-
    Round 2 implementation landed (TDD: RED had 16 failing cases for the right reason, no refusal; GREEN after the check).
    - One constant `Slug.reservedForBoard` (= `PatchNodeType.board.pathSegment`) in Tags/TagSlug.swift, and one check `LocalRef.checkSlugIsNotReserved()`.
    - The check runs in `WorkingCopy.addNode` (addColumn, addActor and `ensure: true` on a new actor, moveTask new column, addTag, renameTag target, tags of addTask/updateTask/tagTask, #marker tags), in `authorRef` (new comment author), and in `KanbanGraph.sessionActor(named:)`.
    - New error cases share the old codes: `KanbanError.reservedSlug(type:)` (INVALID_SLUG), `KanbanError.reservedTagName` (INVALID_TAG_NAME). Message: `The slug "board" is reserved for the board URI kanban://<board-key>/board, so a column cannot have it. ...`.
    - The owner answered: display names are not restricted. `updateColumn`, `updateActor`, `updateTag` refuse nothing (the slug does not change). A node that an old log has stays usable (`ensure: true` on an old `board` actor returns it).
    - Replay does not use the check. Test `oldLogWithReservedSlugLoads` proves the old log loads.
    - Tests: new Tests/FoundationModelsKanbanTests/Mutations/ReservedSlugTests.swift (one parameterized test over 15 mutation cases with the shared helper `ColumnActorTests.failure(of:after:in:)`, session actor, old log). NodeURITests: `refRoundTripsThroughURI` (6 node types x 11 keys) and `reservedSlugURIParsesAsBoard`. KanbanErrorTests: codes and messages of the two cases.
    - plan.md §3.2: bullet "The slug `board` is reserved".
    - ^82s1wf9: the `board` slug part is removed from its description, with a comment.

    ### implement — changed
    - evidence: 13 files — Sources/FoundationModelsKanban/Tags/TagSlug.swift, Sources/FoundationModelsKanban/GraphQL/Errors.swift, Sources/FoundationModelsKanban/GraphQL/ColumnActorMutations.swift, Sources/FoundationModelsKanban/GraphQL/CommentMutations.swift, Sources/FoundationModelsKanban/GraphQL/TagMutations.swift, Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift, Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Tests/FoundationModelsKanbanTests/Mutations/ReservedSlugTests.swift (new), Tests/FoundationModelsKanbanTests/Identity/NodeURITests.swift, Tests/FoundationModelsKanbanTests/GraphQL/KanbanErrorTests.swift, plan.md. `swift test`: 1075 tests in 75 suites pass, 0 failures; the only build warning is the accepted SwiftPM "missing creator for mutated node".
    - next: /review
  timestamp: 2026-10-09T16:27:47.942206+00:00
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

## Review Findings (2026-10-09 10:13)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 5 file(s) reviewed, 7 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/Identity/NodeURI.swift:83` `completeness/inverse-operation-coverage` — The parse now reads any URI ending in `/board` as the board URI, even when the segment before it is a column name. A column whose slug is `board` is written by `LocalRef.uri(inBoard:)` (LocalRef.swift:211-213) as `kanban://<key>/column/board`. That text now parses back as `.board`, so the round trip from a column to a URI and back loses the column. The change deleted `columnNamedBoardIsColumn`, the one test that covered this case, and added no round-trip check for it. Decide whether a column or actor slug of `board` is legal. If it is, parse `column/board` and `actor/board` (and the other typed refs) as the typed ref, and only treat a trailing `board` as the board when it has no type segment before it. Then restore a column-named-board test and add `kanban://<key>/column/board` to the round-trip list. If a slug of `board` is not legal, add a test that proves the slug is refused, so the rule is written down.
