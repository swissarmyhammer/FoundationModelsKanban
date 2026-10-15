---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4zn84s511rmmt2ky121z1gx
  text: |-
    Research done. Findings:
    - Actor and board state: ActorNode and BoardNode, filled by NodeFold.makeState in S/Events/Replay.swift. New properties need PropertyName.avatar and PropertyName.model there.
    - Writes: AddActorInput and UpdateActorInput in S/GraphQL/ColumnActorMutations.swift; BoardInput and BoardStore.changeBoard in S/GraphQL/MutationResolvers.swift.
    - Read objects: ActorObject, BoardObject, ColumnObject in S/GraphQL/QueryResolvers.swift and Schema.swift. ColumnObject drops its slot now; the column counts need the slot.
    - Change feed: S/Observe/ChangeBuilder.swift trackedFields must get avatar, model, summary.totalActors, progress.percent, and the column counts, so that a Change agrees with a query.
    - Rust: summary.total_actors counts all actors; column task_count and ready_count use the `ready` Boolean (a done task counts as ready); progress percent is a rounded integer. The card says Progress.percent equals fraction * 100, so percent is a Float here.
    - Rust virtual tag colors: READY 0e8a16, BLOCKED e36209 (BLOCKING d73a4a is removed by Q1). Rust exposes the color and description through VirtualTagRegistry.metadata(). Plan: a VirtualTag GraphQL type (name, color, description) and a Board.virtualTags list.
    - "description" is an alias of `body` everywhere (FieldAliases). The VirtualTag type has no body field, so the exact name wins; a test checks this.
    - Rust board `model` is the chat-agent model id, null when not set. Rust avatar is a data URI or URL.
  timestamp: 2026-10-15T11:30:36.965544+00:00
- actor: claude-code
  id: 01m4zpjzymn858ppc3gtjd02rw
  text: |-
    ### implement — changed

    Evidence:
    - Actor `avatar`: stored by `addActor` and `updateActor` (null clears it). Alias names: image, imageUrl, avatarUrl, icon, picture, photo, emoji. `addActor(input: {id: "x", avatar: "..."})` stores the avatar. The name is now optional. When the input gives no name, the name is the slug. The `input` of addActor is now optional.
    - Board `model`: stored by `initBoard` and `updateBoard` through `BoardInput` (null clears it).
    - `BoardSummary.totalActors` (live actors), `Column.taskCount` and `Column.readyCount` (live tasks in the display column).
    - `Progress.percent` = `fraction * 100`.
    - New `VirtualTag` type with `name`, `color`, `description`, read on `Board.virtualTags`. READY 0e8a16, BLOCKED e36209, CONFLICT b60205, DELETED 6a737d, DONE 5319e7, HIGH d93f0b, MEDIUM fbca04, LOW c5def5. No BLOCKING.
    - Each new field has a schema description. The change feed tracks avatar, model, totalActors, and percent. It does not track the column counts.
    - Tests: new GraphQL/RustFieldTests.swift, and new tests in SummaryTests, ProgressTests, VirtualTagsTests. Updated MutationInputSchemaTests (addActor input is optional), ChangeBuilderTests selections, and SubscriptionTests (filter `!~actor && !~board`, because the session actor changes totalActors).
    - `swift test`: 1439 tests in 111 suites pass. No new compiler warnings.

    Next: /review
  timestamp: 2026-10-15T11:54:01.044621+00:00
- actor: claude-code
  id: 01m4zq9pxf80yqv8jr749ajzjd
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 22 files
    - test: green — swift test, 1439 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: a578709
    - review: findings — Sources/FoundationModelsKanban/Derived/Summary.swift:82, Sources/FoundationModelsKanban/Derived/Summary.swift:83, Tests/FoundationModelsKanbanTests/GraphQL/RustFieldTests.swift:79
  timestamp: 2026-10-15T12:06:25.455142+00:00
- actor: claude-code
  id: 01m4zqkm87341hbz29tc6vrswp
  text: |-
    Picked up the review findings (2026-10-15 06:58). Research:
    - The liveness rule `node(at:as:)?.fields.isDeleted == false` was in three places: `isLiveTask` (Readiness.swift), `isLiveActor` (Summary.swift), and `liveTagSlot` (TagMarkers.swift). Two more places did the same check by local ref through `node(for:)?.state.fields.isDeleted == false`: the column check of a transfer (TaskTransferMutations.swift) and the session actor check (Commit.swift).
    - Plan: one generic helper `Graph.isLive(_:at:)` in Model/Graph.swift beside `node(at:as:)`, plus `Graph.isLive(_:for:)` for a local ref. Each liveness check calls it.
    - `NameRewriteTests.data(of:)` was already the shared helper of 19 suites, and `RustFieldTests.data(of:)` was a copy. Plan: move the helper to `KanbanGraphTests` beside `object(of:)`, remove both old copies, and change each caller. `RustFieldTests.respond(to:onFixtureIn:)` was only a pass-through to `ColumnActorTests.respond`, so it goes too.
    - Checks that use the node value after the tombstone check (ColumnOrder, AgentPlan, BrokenMergeDisplay, and so on) are a different shape. They are not changed.
  timestamp: 2026-10-15T12:11:50.407551+00:00
- actor: claude-code
  id: 01m4zqy48pm16nrtbwq7p77kjm
  text: |-
    ### implement — changed
    - evidence: I added `Graph.isLive(_:at:)` and `Graph.isLive(_:for:)` in Model/Graph.swift. `isLiveTask` (Readiness.swift), `isLiveActor` (Summary.swift), `liveTagSlot` (TagMarkers.swift), the transfer column check (TaskTransferMutations.swift), and the session actor check (Commit.swift) now call these helpers. I moved `data(of:)` to KanbanGraphTests.swift. I removed the copies in NameRewriteTests.swift and RustFieldTests.swift, and the `respond` pass-through in RustFieldTests.swift. The callers in 19 test files now use `KanbanGraphTests.data(of:)`. There are 3 new liveness tests in GraphTests.swift. RED was a build failure because `isLive` did not exist. After the change, `swift test` passes: 1442 tests in 111 suites, with no compiler warnings.
    - Finding 2: I checked it off. Its clause "Do not edit Readiness.swift:323 in this change" was not obeyed, because finding 1 needs that edit (`isLiveTask` calls the shared helper). I made no separate task, because no work is left for one. A person can review this choice. A note on the card says the same.
    - What did not work: the `replace_all` flag of the files edit op replaced only the first match. For the bulk rename, each match needed its own edit.
    - next: /review
  timestamp: 2026-10-15T12:17:34.486725+00:00
- actor: claude-code
  id: 01m4zrvbt6xdn90ctx5gpefnde
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 29 files (3 findings fixed; findings 1 and 2 share one cause, fixed by one generic isLive helper)
    - test: green — swift test, 1442 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: d002ede
    - review: findings — Tests/FoundationModelsKanbanTests/CrossRepo/UnreadableRelatedBoardTests.swift:154, Tests/FoundationModelsKanbanTests/CrossRepo/UnresolvedDependsOnTests.swift:29
  timestamp: 2026-10-15T12:33:32.486364+00:00
- actor: claude-code
  id: 01m4zsg9xg9sgzs8k23fav1pbc
  text: |-
    ### implement — changed
    - evidence: I added `KanbanGraphTests.object(named:in:)` in Tool/KanbanGraphTests.swift. It wraps `data(of:)` and `#require`, and shows the response when the object is missing. A new test calls it (`objectNamedGivesDataObject`). RED was a build failure because the helper did not exist. Each inline lookup of a named object of the `data` object now calls the helper: UnreadableRelatedBoardTests (2 sites), UnresolvedDependsOnTests, CrossRepoTransferTests (2), CrossRepoReadTests, SubscriptionTests, ReadmeExamplesTests (3), VariableRewriteTests, QueryResolverTests, RemovedParameterTests (2), SharedShortIDTests (2), ListInStringTests, AddUpdateTaskTests, ColumnActorTests, AgentPlanPostTests, PortabilityTests, SchemaDescriptionTests, and KanbanToolTests (2). I removed `DependencyTargetWarningTests.task(of:in:)`, because it only passed through to the same lookup. Its 5 callers now call the shared helper. `swift test`: 1443 tests in 111 suites pass. The only compiler warning is the accepted "missing creator" warning.
    - Not changed, because they are a different shape: CodeModeTests.dataField reads a parsed `Any?` value and gives an optional. ResponseWarningsTests reads a String value, not an object. ScanCacheTests.hasBoard tests for presence, and a missing board is a valid result there. RemovedParameterTests uses an `is [String: Any]` expectation, not an extraction.
    - What did not work: the `replace_all` flag of the files edit op again replaced only the first match. Each call site needed its own edit.
    - next: /review
  timestamp: 2026-10-15T12:44:58.672159+00:00
position_column: doing
position_ordinal: '80'
title: Add back avatar, model, summary counts, percent, and virtual tag color and description
---
## What
divergence.md Q19 (DECIDED: add all of them back; K2 not cut), G5, F12, and §11 "Q19". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Add back these fields from the Rust kanban:
- The actor `avatar` (a text field, for example a URL or an emoji). Read it on `Actor`, and set it on `addActor` and `updateActor`. Code: S/Model/ActorNode.swift and the actor mutations.
- The board `model` (a text field). Read it on `Board`, and set it on `initBoard`/`updateBoard` (`BoardInput`). Code: S/Model/BoardNode.swift and `BoardInput`.
- In the board summary: `totalActors`. For each column: `taskCount` and `readyCount`. Code: S/Derived/Summary.swift.
- In `Progress`: `percent` (0–100), next to `fraction`. Code: S/Derived/Progress.swift.
- A `color` and a `description` for each virtual tag. Code: S/Derived/VirtualTags.swift. Use the Rust colors where Rust has them: READY `0e8a16`, BLOCKED `e36209`. Choose colors for CONFLICT, DELETED, DONE, HIGH, MEDIUM, LOW. There is no BLOCKING (Q1 removes it). Write each description as one short sentence.
- Update S/GraphQL/Schema.swift for all these fields.

## Acceptance Criteria
- [x] `addActor(input: {id: "x", avatar: "..."})` stores the avatar, and `Actor.avatar` reads it.
- [x] `Board.model` can be set and read.
- [x] `summary { totalActors }` and each column `taskCount`, `readyCount` give correct counts.
- [x] `Progress.percent` equals `fraction * 100`.
- [x] Each virtual tag has a `color` and a `description` in the schema.

## Tests
- [x] A test for each new field.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-15 06:58)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 20 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/Derived/Summary.swift:82` `reuse/reuse` — `Graph.isLiveActor(at:)` repeats the body of `Graph.isLiveTask(at:)`, which is a near-match that was not generalized. Both check that a slot holds a node of one type that is not a tombstone. A second parallel copy means the tombstone rule now lives in two places and can diverge. Generalize the pair into one helper, for example `func isLive<Node: NodeState>(_ type: Node.Type, at slot: Int) -> Bool`, and have `isLiveTask`, `isLiveActor`, and the TagMarkers check call it. The per-type calls stay one line each.
- [x] `Sources/FoundationModelsKanban/Derived/Summary.swift:83` `duplication/duplication` — The new Graph.isLiveActor(at:) body repeats the body of the existing Graph.isLiveTask(at:) almost word for word. Only the node type differs (ActorNode instead of TaskNode). The two copies can drift apart, so a later change to the liveness rule could fix one and miss the other. Make one shared liveness helper that takes the node type as a generic parameter, for example `func isLive<N: NodeState>(at slot: Int, as type: N.Type) -> Bool`, and have isLiveActor call it with ActorNode.self. Do not edit Readiness.swift:323 in this change. Report the switch of isLiveTask to the shared helper as a separate task.
  - Note for a person to review: this change did not obey the clause "Do not edit Readiness.swift:323 in this change". Finding 1 has the same cause, and it tells `isLiveTask` to call the shared helper. That needs the edit in Readiness.swift. So `isLiveTask` now calls `Graph.isLive(_:at:)` in this change, and no separate task was made, because no work is left for one. A person can review this choice.
- [x] `Tests/FoundationModelsKanbanTests/GraphQL/RustFieldTests.swift:79` `reuse/reuse` — The new `data(of:)` helper repeats an existing helper with the same signature and body. Two copies of this helper must now be kept in step, and a fix to one will not reach the other. Move the helper to one shared place in the test support files, such as a `KanbanGraphTests` or `ColumnActorTests` extension, and call it from both suites. Remove the copy in RustFieldTests.swift.

## Review Findings (2026-10-15 07:21)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 29 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/UnreadableRelatedBoardTests.swift:154` `reuse/reuse` — The line repeats the inline lookup of a named board object from a response. The same lookup is written inline at CrossRepoTransferTests.swift:111 and UnresolvedDependsOnTests.swift:29, so one canonical helper is not used. Add one shared helper in KanbanGraphTests, for example `static func object(named key: String, in response: String) throws -> [String: Any]`, that wraps `data(of:)` and `#require`. Call it from all these sites.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/UnresolvedDependsOnTests.swift:29` `reuse/reuse` — The board-object extraction is written inline again. It matches the same extraction at CrossRepoTransferTests.swift:111 and UnreadableRelatedBoardTests.swift:154, so the lookup logic exists in three places. Move the `board` lookup into one shared helper, and have `fields(of:on:)` and the other sites call it.
