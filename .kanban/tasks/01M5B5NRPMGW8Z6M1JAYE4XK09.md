---
assignees:
- claude-code
position_column: todo
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
- [ ] A transaction with one named file cut off is held, and the warning names the missing ref.
- [ ] A transaction is held when a file that the list does not name holds a line of the `txn`, and a named file is missing.
- [ ] A complete transaction is applied.
- [ ] An old line with a number is checked by count, and an old line with no field is applied.
- [ ] A collect transaction lists only the files of its new lines, and it is applied after a load.
- [ ] Tests use temporary folders only.