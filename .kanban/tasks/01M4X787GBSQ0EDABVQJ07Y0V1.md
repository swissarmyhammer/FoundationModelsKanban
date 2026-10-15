---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5000jg7ht2gyr2jz9e8tej1
  text: |-
    Research done. Findings:
    - Each worker of BoardLoader folds one node from its own file (NodeLog). The transaction check needs all files, so it must run after the workers, in BoardLoader.readStages, before the join. Only a node with an event of an incomplete transaction folds again.
    - LiveGraph.reload reads only the changed files. The check must also see the events of the other files. So LiveGraph must keep the held events (events of an incomplete transaction), not only the applied events. Else a transaction that becomes complete later (the missing file arrives) cannot apply on the node whose file did not change.
    - A reload can also change the state of a node whose file did not change: a transaction becomes complete (its held events must apply) or becomes incomplete (a file is removed, so its applied events must be held). Plan: fold such a node again from the events in memory.
    - The commit writes through EventLogWriter (a test seam, FaultingLogWriter in CommitRollbackTests). Plan: add a synchronize call to the seam, and call it on each appended file after all appends of all boards, inside the rollback block.
    - The file count goes on each written event in BoardWrite.append (the count of node files of this board that the transaction appends to).
    - UndoMutations also calls Event.recording(operations:changing:inBoard:) to build Change values; the file count does not go there.
    - No ARCHITECTURE.md exists.
  timestamp: 2026-10-15T14:38:43.207443+00:00
- actor: claude-code
  id: 01m500w9f6y3vzh8msgprsd0ew
  text: |-
    Implementation landed (TDD: each new test failed first, then passed).
    - Event.files (optional; nil = old line, complete). Event.recording(fileCount:). BoardWrite.append sets the count of node files of its board on each written line.
    - fsync: EventLogWriter gets synchronize(logOf:in:); EventLog.synchronize(logOf:) calls FileHandle.synchronize (fsync). The commit calls it on each appended file of each board after all appends, inside the rollback block (a failed fsync rolls back like a failed append).
    - New Events/TransactionCheck.swift: IncompleteTransactions (txn is held when fewer distinct node files have its lines than the largest count) and CheckedEvents (applied + held).
    - BoardLoader.readStages runs the check after the workers, over the read files plus the in-memory events of the other files (`besides:`), folds again only the nodes that need it (also nodes whose file did not change, from memory), logs a swift-log warning for held transactions, and returns [StagedLog] with held events. LoadedBoard/JoinedBoard carry heldEvents; LiveGraph keeps heldEvents, so a held txn applies when the missing file arrives, and a txn that loses a file is held again on all its nodes. largestEventID also counts held ids.
    - Discovery: ULID(timestamp:) is random in its low bits, so a test that wants one txn for many events must make the txn ULID once.
    - No change to divergence.md, plan.md, or ARCHITECTURE.md (none exists). No IntegrationTests change needed.
    - Full `swift test`: 1477 tests in 114 suites passed; no compiler warnings except the accepted SwiftPM "missing creator" line.
  timestamp: 2026-10-15T14:53:51.462164+00:00
- actor: claude-code
  id: 01m500wc0dwk020989hc5mjy34
  text: |-
    ### implement — changed
    - evidence: `swift test` 1477 tests / 114 suites passed. Files: Sources/FoundationModelsKanban/Events/{Event.swift, EventLog.swift, EventLogWriter.swift, Loader.swift, TransactionCheck.swift (new)}, Sources/FoundationModelsKanban/Observe/LiveGraph.swift, Sources/FoundationModelsKanban/Tool/Commit.swift; Tests: Events/{EventTests.swift, TransactionCheckTests.swift (new)}, Tool/{CommitCrashSafetyTests.swift (new), CommitRollbackTests.swift}, Observe/LiveGraphApplyTests.swift
    - next: /review
  timestamp: 2026-10-15T14:53:54.061220+00:00
- actor: claude-code
  id: 01m501gxdhgq9wwrwrkfyzgfsr
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 12 files
    - test: green — swift test, 1477 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: b4e699d
    - review: clean — none
  timestamp: 2026-10-15T15:05:07.249688+00:00
position_column: done
position_ordinal: ff8480
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
- [x] Each commit calls fsync on each file that it appended to.
- [x] Each new event line has the file count.
- [x] A transaction with one file cut off is not applied, at load and in `LiveGraph.reload`.
- [x] A complete transaction is applied.
- [x] An old line with no count is applied.

## Tests
- [x] A transaction with one file cut off is not applied.
- [x] A complete transaction is applied.
- [x] An old line with no count is applied.
- [x] The same three cases through `LiveGraph.reload`.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.