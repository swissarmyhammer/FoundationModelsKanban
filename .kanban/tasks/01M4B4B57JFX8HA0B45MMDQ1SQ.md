---
depends_on:
- 01M4B4002GZV6E43G5CQ74BJNZ
position_column: todo
position_ordinal: b080
title: 'Mutations: comments'
---
## What
Comment mutations. The basis is plan.md §4.2 and §3.2 (a comment is a full node).
- `MutationResolvers.swift` (comment part): `addComment(task, body, actor)`, `updateComment(id, body)`, `deleteComment(id)`, `undeleteComment(id)`.
- Mint a ULID with a unique short id. Author = explicit `actor`, else the session actor; an unknown author is created (an actor `set` patch).
- Comment refs need only the comment id (any short form). `body` is written as an `edit` diff.
- `Task.comments` lists live comments, oldest first.

## Acceptance Criteria
- [ ] `addComment` returns the comment with `id`, `shortId`, `author`, and `body`.
- [ ] `updateComment(id:)` and `deleteComment(id:)` work with only the comment id.
- [ ] An unknown author is created in the same call.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Mutations/CommentTests.swift`: port the Rust comment dispatch tests.
- [ ] Run `swift test --filter CommentTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.