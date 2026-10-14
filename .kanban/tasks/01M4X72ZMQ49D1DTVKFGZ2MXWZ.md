---
assignees:
- claude-code
depends_on:
- 01M4X6XKP0Y832GDRHQ1MG22VF
position_column: todo
position_ordinal: '9380'
title: Put a board that a call reached by a path into the key index
---
## What
divergence.md X4 (§1.1, §11 bugs; K8 stays as work). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem: a board that the call reached only by a path to a folder outside the scan places (for example `board: "/x/notes"`, where `/x/notes` is a git repo) does not go into the scan index (S/Tool/KanbanGraph.swift:703-721). A path into a folder that the scan finds is in the index. Results: a task on that board is done, but a task that depends on it stays BLOCKED; `node(id:)` with a URI of that board gives null; undo with no `board` field, of a transaction that also changed that board, gives `NOT_FOUND`. Undo with `board: "/x/notes"` works.

Note: after the task "Put the board only in a git repo", a `board:` path must be inside a git repo. This task applies to such a path outside the scan places.

Change: when a call reaches a board by a path, add that board (its key and its worktree top) to the key index of the host (or the locator), so that a later URI with that key resolves to it. Use the same order rule as for other copies with the same key.

## Acceptance Criteria
- [ ] After a call with `board: "<path outside scan places>"`, a URI with the key of that board resolves to it.
- [ ] A task that depends on a done task on that board is READY.
- [ ] `node(id:)` with a URI of that board gives the node.
- [ ] Undo with no `board` field, of a transaction that also changed that board, reverses both boards.

## Tests
- [ ] The three results above, each as a test (these are also listed in the K14 missing tests).
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.