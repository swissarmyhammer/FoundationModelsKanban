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