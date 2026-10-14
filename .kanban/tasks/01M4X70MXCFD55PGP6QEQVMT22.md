---
assignees:
- claude-code
position_column: todo
position_ordinal: 8a80
title: Make event ids increase from one call to the next
---
## What
divergence.md S3 (§7, §11 bugs) and the M6 final decision in §16. This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Event ids are in order inside one call, but not from one call to the next. Each call starts from a new random ULID (S/Tool/Commit.swift:31-37,62-66). Two calls in the same millisecond, or a clock that moves back, can put a later `set` before an earlier one. They can also put an undo before its target.

Why this is important now: each worktree has its own board on its own branch, and boards join when the branches merge (union merge of the log lines). The replay order after a union merge is the order of the event ids. Thus the merge of worktree boards needs ids that increase.

Change: start each call after the largest event id in the log of each board that the call writes (keep the largest id in memory, and update it on each commit and on each watcher reload). The first id of a call is greater than every id that the board already has, also when the clock moves back or two calls run in the same millisecond.

## Acceptance Criteria
- [ ] Two calls in the same millisecond give ids in call order.
- [ ] When the clock moves back, the next call still gives ids greater than the largest id in the log.
- [ ] An undo always has an id greater than its target.
- [ ] Ids from events that the watcher loads (from another process or a merge) also count as the largest id.

## Tests
- [ ] A test with a fixed clock (same millisecond for two calls) and a clock that moves back.
- [ ] A test that an undo id is greater than the target id.
- [ ] A test with a union merge of two board copies, then a new call: its ids are greater than all merged ids.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.