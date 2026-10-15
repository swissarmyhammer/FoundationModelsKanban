---
assignees:
- claude-code
position_column: todo
position_ordinal: b580
title: Replace the related engine of a session view when a new repo is at the same path
---
## What
Found during ^58v2scm. This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

`KanbanGraph.loadRelatedBoard(_:)` keeps the engine of a related board in `relatedBoards`, by the canonical path of its repo folder. It adds an engine only when the path has no engine (`if relatedBoards[path] == nil`). `SessionFeeds.add(_:forBoardAt:)` also keeps the first feed of a path.

When a repo is replaced at the same path (move the old folder away, make a new repo there), the host forgets the path ref result and reads git again (the `.place` and `.repo` forget paths of ^58v2scm). The host then gives a new copy with the new key, and `KanbanHost.relatedEngine` loads a new engine (a new `FolderIdentity`). But the view keeps the old engine of the path. `RelatedBoards.board(resolvedAs:)` reads the board by path, so `{ board(id: "<path>") { key } }` still gives the old key and the old tasks.

Seen in `PathRefCacheTests.replacedRepoIsReadAgain`: after the `.place` change, the host read git again (the git-call counter went up), and `host.board(ofFolderAt:)` gave the new key, but the GraphQL read through the session view gave the old key.

## Change
- In `loadRelatedBoard`, when the engine of the path has a different `identity` from the loaded engine, replace the engine and its feed in the view.
- Decide what the change feed of the view does with the old feed (end it, or keep its subscribers on the new feed).

## Acceptance Criteria
- [ ] After a repo is replaced at the same path, the next call with the path ref gives the board of the new repo (key and tasks).
- [ ] The change feed of the view sends the changes of the new board, and no changes of the old board.

## Tests
- [ ] A test replaces the repo of a path ref and checks the key of `{ board(id: "<path>") { key } }` through the session view.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.