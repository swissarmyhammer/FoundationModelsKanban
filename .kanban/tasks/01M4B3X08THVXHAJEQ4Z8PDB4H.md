---
depends_on:
- 01M4B3WK197P3T3VZHX3JHWP3E
position_column: todo
position_ordinal: 8b80
title: 'Event log: append, lock, and file signatures'
---
## What
Read and write the log files of one board. The basis is plan.md §5.2, §5.4 step 5, and §5.6 (file signature).
- `Sources/FoundationModelsKanban/Events/EventLog.swift`: paths `.kanban/board.jsonl`, `columns/<slug>.jsonl`, `actors/<slug>.jsonl`, `tags/<slug>.jsonl`, `tasks/<ULID>.jsonl`, `comments/<ULID>.jsonl`.
- Append events to one node file. Make directories when needed. On the first write, make `.kanban/.gitattributes` (`*.jsonl merge=union`) and `.kanban/.gitignore` (`.lock`).
- Lock: exclusive `flock` on `.kanban/.lock`. A function that locks many boards in the sort order of the board key.
- `FileSignature`: size, modification time, id of the last event. Calculate it for one file; list all node files of a board with their signatures.

## Acceptance Criteria
- [ ] An append adds one line for each event and does not change other lines.
- [ ] Two processes that lock the same board run one after the other (test with two child processes or two file descriptors).
- [ ] The signature changes after an append and does not change after a read.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift`, in a temporary directory.
- [ ] Run `swift test --filter EventLogTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.