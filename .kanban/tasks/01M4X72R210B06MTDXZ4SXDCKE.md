---
assignees:
- claude-code
position_column: todo
position_ordinal: '9280'
title: Block each task in a dependency cycle across boards
---
## What
divergence.md X8 (§1.1, §2, §11 bugs). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem: a cycle across boards that comes from a merge does not block. `hasDependencyPath` follows only edges in the same board (S/Derived/Readiness.swift:144-151,175-181). Example: `a` depends on `B#b`, and `b` is done and depends on `A#a`. Then `a` is READY, and `nextTask` returns it. The rule (§5.3 step 5 of the design): each task in a cycle is blocked. A cycle in one board already blocks each task.

Change: the cycle part of readiness follows edges into loaded related boards too (with the same rules for tombstones and unknown targets). Each task in a cycle across boards is BLOCKED, and `nextTask` does not return it. Readiness stays memory only: it reads no file and runs no `git`.

## Acceptance Criteria
- [ ] In the example, `a` is BLOCKED and not READY, and `nextTask` does not return it.
- [ ] A cycle across three boards blocks each task in it.
- [ ] A chain across boards with no cycle keeps its current readiness.

## Tests
- [ ] The two-board example (make the cycle with raw log lines or a merge, because the write path refuses a cycle).
- [ ] A cycle across three boards.
- [ ] `nextTask` skips a task in a cycle across boards.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.