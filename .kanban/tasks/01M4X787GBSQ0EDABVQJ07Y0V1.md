---
assignees:
- claude-code
position_column: todo
position_ordinal: a680
title: Make transactions on many files crash safe with fsync and a file count
---
## What
divergence.md Q23 (DECIDED: fix now; K3 not cut), S5, and §11 "Q23". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem (S5): "all or nothing" covers only errors that the code catches, not a crash. The code appends in place, with no fsync. A crash between two files keeps part of a transaction.

Decided behavior:
- Call fsync on each log file after the appends of a transaction. Code: S/Events/EventLog.swift:158-167.
- Each event line of a transaction records the count of files that the transaction wrote in this board (an optional field, for example `files`). Code: S/Events/Event.swift:21-50. An old line with no count counts as complete.
- At load, find each transaction (`txn`) that is not complete in all its files (fewer files in this board have lines of that `txn` than the count says), and do not apply its events. Code: S/Events/Replay.swift and/or S/Events/Loader.swift.
- `LiveGraph.reload` (S/Observe/LiveGraph.swift:165) reloads one node, so it must also check that the transaction is complete before it applies the events.
- Note: a transaction that is not complete can become complete later (for example when git brings the missing file). Then it applies at the next load or reload.

## Acceptance Criteria
- [ ] Each commit calls fsync on each file that it appended to.
- [ ] Each new event line has the file count.
- [ ] A transaction with one file cut off is not applied, at load and in `LiveGraph.reload`.
- [ ] A complete transaction is applied.
- [ ] An old line with no count is applied.

## Tests
- [ ] A transaction with one file cut off is not applied.
- [ ] A complete transaction is applied.
- [ ] An old line with no count is applied.
- [ ] The same three cases through `LiveGraph.reload`.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.