---
comments:
- actor: wballard
  id: 01m4c0nxn2pxqyp0ywag2459r3
  text: |-
    Research done.
    - `Task.comments` exists already (QueryResolvers `TaskObject.comments` -> `Graph.comments(ofTaskAt:)`, live comments sorted by ULID, hidden on a tombstoned task). `Comment.author` resolves a tombstoned actor.
    - Plan: new file `GraphQL/CommentMutations.swift` (same pattern as `TaskMutations.swift` and `ColumnActorMutations.swift`), registered in `PublicSchema`. Reuse `changeNode`, `addNode`, `updateNode`, `changeDeleted`, `NodeReferenceInput` from `ColumnActorMutations.swift`; these must become `internal` (now `private`/`fileprivate`).
    - Author rule: no `actor` -> session actor (runMutation writes its actor patch). An `actor` short form that names no node gets an actor `set name` patch with the slug of the text. A full URI must name an actor (ACTOR_NOT_FOUND otherwise).
    - Rust tests to port: `dispatch/tests/comments.rs` (3 tests), plus not-found and order tests of `comment/{add,update,delete,list}.rs`. Rust `test_add_comment_unknown_actor_errors` is replaced by the plan rule: the unknown author is created.
  timestamp: 2026-10-07T20:25:34.114905+00:00
- actor: wballard
  id: 01m4c133hde5cv70pws4mzz9z5
  text: |-
    Implementation landed (TDD: 12 tests in CommentTests failed on assertions first, then passed).
    - New `Sources/FoundationModelsKanban/GraphQL/CommentMutations.swift`: names, `AddCommentInput` (task, body, actor), `UpdateCommentInput` (id, body as FieldUpdate), the four resolvers, `WorkingCopy.authorRef(for:defaultingTo:resolvingWith:at:)`, and `addCommentMutations()`. The comment code is in its own file, the same as `TaskMutations.swift` and `ColumnActorMutations.swift` (the card named `MutationResolvers.swift`; its `MutationName` doc now points to the per-type files).
    - Author rule: no `actor` -> session actor (runMutation writes its actor patch). A slug or a name that names no node -> actor `set name` patch with the text. An actor node that exists (live or tombstoned) gets no patch. A full URI must name an actor, else ACTOR_NOT_FOUND.
    - Reuse: `changeDeleted`, `NodeReferenceInput`, `addNode`, `updateNode` in ColumnActorMutations.swift are now internal. TaskMutations.swift has a new `RefResolver.actorRef(for:includingTombstones:)` that `actorRefs(for:)` uses.
    - Test helpers made internal for reuse: `AddUpdateTaskTests.mutation(of:)`, `sigilRef(of:)`, `fixtureTask()`; `ColumnActorTests.lastPatch(of:isDelete:in:)`.
    - `Task.comments` (oldest first, live only) already existed; tests cover it.
    - Full suite: 670 tests pass, no build warnings. Periphery shows only the warnings that were there before (Errors.swift, KanbanGraphTests.swift).
  timestamp: 2026-10-07T20:32:46.125953+00:00
- actor: wballard
  id: 01m4c136s9rmrrm90pyk2sdx4r
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsKanban/GraphQL/CommentMutations.swift (new), ColumnActorMutations.swift, TaskMutations.swift, MutationResolvers.swift, Schema.swift; Tests/FoundationModelsKanbanTests/Mutations/CommentTests.swift (new), AddUpdateTaskTests.swift, ColumnActorTests.swift. `swift test --filter CommentTests`: 12 tests (14 cases) pass. `swift test`: 670 tests in 40 suites pass. `swift build --build-tests`: 0 warnings. periphery: no new warnings.
    - next: /review
  timestamp: 2026-10-07T20:32:49.449075+00:00
depends_on:
- 01M4B4002GZV6E43G5CQ74BJNZ
position_column: doing
position_ordinal: '8280'
title: 'Mutations: comments'
---
## What
Comment mutations. The basis is plan.md §4.2 and §3.2 (a comment is a full node).
- `MutationResolvers.swift` (comment part): `addComment(task, body, actor)`, `updateComment(id, body)`, `deleteComment(id)`, `undeleteComment(id)`.
- Mint a ULID with a unique short id. Author = explicit `actor`, else the session actor; an unknown author is created (an actor `set` patch).
- Comment refs need only the comment id (any short form). `body` is written as an `edit` diff.
- `Task.comments` lists live comments, oldest first.

## Acceptance Criteria
- [x] `addComment` returns the comment with `id`, `shortId`, `author`, and `body`.
- [x] `updateComment(id:)` and `deleteComment(id:)` work with only the comment id.
- [x] An unknown author is created in the same call.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Mutations/CommentTests.swift`: port the Rust comment dispatch tests.
- [x] Run `swift test --filter CommentTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.