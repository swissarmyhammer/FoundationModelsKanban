---
assignees:
- claude-code
position_column: todo
position_ordinal: '8980'
title: Start the full compare when the watcher reports a directory inside .kanban
---
## What
divergence.md S7 (§7, and §15 "S7: fix"). The watcher can miss files when a tool moves a whole directory, because FSEvents can report only the directory. This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Change: in S/Tool/Commit.swift:346, a reported path that is a directory inside `.kanban/` (for example `.kanban/tasks/`) starts the full compare of the board files, the same as a report of `.kanban/` itself. This is part of the "file watch detection to allow manual poking of files" rule in §16.

## Acceptance Criteria
- [ ] When `.kanban/tasks/` is moved away and back (or replaced by a different folder), the live graph shows the new task files.
- [ ] A report of a single file still applies only that file.

## Tests
- [ ] A test that moves `.kanban/tasks/` (for example rename it out, then rename a changed copy in) and checks that the live graph changes.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.