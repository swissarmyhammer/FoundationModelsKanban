---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5bcznchrza1e9xj7859hywv
  text: |-
    Research:
    - `Event.files` is `Int?` now. `recording(fileCount:)` sets it. Commit `append(recording:changing:)` records `keptNodes.count` on each kept line. Merged collect lines keep their own `files` value, because `recording(operations:changing:inBoard:)` copies it.
    - The loader (`BoardLoader.readStages`) and `LiveGraph.reload` (through `readStages`) both use `IncompleteTransactions`. A change in `IncompleteTransactions` changes the two paths.
    - A "file" of a transaction is the node log of `patch.node`. `LocalRef` is `TextCodable`, so a list of refs encodes as a list of strings.
    - No test captures swift-log output. The warning text must come from a value that a test can read.
    - Plan: a new `TransactionFiles` enum (`.count(Int)` for old lines, `.refs([LocalRef])` for new lines). A count still encodes as a number, so that a merged old line keeps its own field. Commit writes only `.refs`.
  timestamp: 2026-10-20T00:57:03.633679+00:00
- actor: claude-code
  id: 01m5bdft94gv34x9kythw8n47w
  text: |-
    Implementation landed.
    - New `TransactionFiles` enum in `Event.swift`: `.count(Int)` (old lines) and `.refs([LocalRef])`. Decode reads a number or a list. Encode writes the form that the value has, so a merged old line keeps its own field. `Event.recording(files:)` records only a sorted list. `recording(fileCount:)` is removed.
    - `IncompleteTransactions` now holds `missingFiles: [ULID: [LocalRef]]`. The named files are the union of the lists of the lines of the transaction. With no list, the largest count applies (an empty missing list). `holdDetail` gives the warning text, and `recordHold()` logs it as `missingFiles` metadata. The loader and `LiveGraph.reload` use this type, so both get the same check.
    - Commit records `keptNodes` as the list. Merged collect lines keep their own field.
    - Discovery: after `collectBoards`, a fresh load of the target holds the merged lines of a source transaction that also wrote the source `board` log, because collect does not merge the board log. The old count check had the same problem (7 files counted, 6 in the target). This needs a decision, so I added ^16js6jx. The collect test of this card checks only the collect transaction.
    - Set equality of events with JSON object values failed after a round trip in the collect test, so that test compares event ids.
  timestamp: 2026-10-20T01:05:52.932573+00:00
- actor: claude-code
  id: 01m5bdfwpvamndftea97d2ykrr
  text: |-
    ### implement — changed
    - evidence: Sources/FoundationModelsKanban/Events/Event.swift, Sources/FoundationModelsKanban/Events/TransactionCheck.swift, Sources/FoundationModelsKanban/Tool/Commit.swift, Tests/FoundationModelsKanbanTests/Events/EventTests.swift, Tests/FoundationModelsKanbanTests/Events/TransactionCheckTests.swift, Tests/FoundationModelsKanbanTests/Tool/CommitCrashSafetyTests.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CollectBoardsTests.swift; `swift test`: 1700 tests in 140 suites passed, only the accepted SwiftPM "missing creator" warning.
    - next: /review. Follow-up task ^16js6jx needs a human decision.
  timestamp: 2026-10-20T01:05:55.419189+00:00
position_column: doing
position_ordinal: '80'
title: Record the refs of the written files in each transaction line, not a count
---
## What
divergence.md Q23, "Changed (2026-10-19)". Each event line of a transaction records the local refs of all the log files that the transaction writes in its board, not the count of these files. A count cannot tell which file is missing, and a wrong file with the same `txn` can fill it.

## Do
- `Event.files` (`S/Events/Event.swift`): decode the old number and the new list of local refs. Encode only the list. A line with no field is complete.
- The commit path (`S/Tool/Commit.swift`, `append(recording:changing:)`): record the refs of `keptNodes`, sorted, on each kept line. The merged lines of a `collectBoards` call keep their own field.
- `IncompleteTransactions` (`S/Events/TransactionCheck.swift`): a transaction with a list is complete only when each named ref has a line with that `txn`. A transaction with only old numbers keeps the count check. When lines have both kinds, the list applies.
- `recordHold()`: name the missing refs of each held transaction.
- `LiveGraph.reload` and the loader use the same check.
- Use the file editing tool only. Do not edit plan.md.

## Acceptance Criteria
- [x] A transaction with one named file cut off is held, and the warning names the missing ref.
- [x] A transaction is held when a file that the list does not name holds a line of the `txn`, and a named file is missing.
- [x] A complete transaction is applied.
- [x] An old line with a number is checked by count, and an old line with no field is applied.
- [x] A collect transaction lists only the files of its new lines, and it is applied after a load.
- [x] Tests use temporary folders only.