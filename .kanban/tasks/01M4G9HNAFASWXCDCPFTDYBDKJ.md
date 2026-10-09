---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gczbbe93fpmjmft0mnetxs
  text: |-
    Research done.
    - `CommitSession.commit(_:along:)` in Tool/Commit.swift appends each changed board in turn through `BoardWrite.append(recording:changing:)`. That function appends each node file through `EventLog.append(contentsOf:toLogOf:)`, and then calls `live.adopt`.
    - `writes` is a local array. When an append throws, `commit` throws before `live = writes[0].live`, so the session keeps its old live graph. But the lines of the earlier appends stay on disk. The next call then sees a changed log and reads the partial transaction.
    - `BoardLock` is `~Copyable`. It releases the locks at the end of its scope, also when `commit` throws.
    - A file signature holds the size, the modification time, and the last event id. A truncate changes the modification time. To keep the signatures the same, the rollback must also restore the modification time.
    - KanbanGraph makes each session (the current board and each related board) in `loadSession(at:key:searchingWith:)`. Thus one writer that the engine gets reaches each board of a cross-board commit.
    - A two-board test can use `CrossRepoFixture.SideBySide` and `GitGraphFixture.makeGraph`.
  timestamp: 2026-10-09T13:17:23.694361+00:00
- actor: claude-code
  id: 01m4gdfkye3es2jbysqcwwabw9
  text: |-
    Implementation landed (TDD: the 5 new tests failed first with 17 issues, then passed).
    - New seam: `EventLogWriter` protocol and `FileEventLogWriter` (Events/EventLogWriter.swift). `CommitSession.init` takes `writingWith:`; `KanbanGraph` internal init takes `writingLogsWith:` (default `FileEventLogWriter()`) and gives it to each session, current and related.
    - New `LogFileMark` (Events/LogFileMark.swift) and `EventLog.mark(ofLogOf:)`: stat of the file before the first append (size and `st_mtimespec`, or no file). `restore()` truncates and sets the exact mtime back with `utimensat`, or unlinks a new file.
    - Commit.swift: `BoardWrite.append` now only writes and returns the events; `BoardWrite.adopt(writing:)` is separate. New `CommitSession.append(_:recording:)` records the marks of all boards, appends all boards, then adopts all boards on a copy of `writes`. On any error of an append or of an adopt (signature read), it rolls back each mark while the locks are held, and throws the original error. A restore that fails is logged with swift-log and does not stop the other restores.
    - plan.md §5.4 steps 5.3 to 5.5 describe the record, the all-or-nothing adopt, and the rollback.
    Choices where the card is open (closest to plan.md all-or-nothing):
    - The rollback also restores the modification time, so the file signatures equal the recorded signatures and the next call commits in its first run (no extra run from a changed log).
    - A failure of the new-signature read after all appends also rolls back, so an error always means nothing on disk.
    - Only the node log files roll back. A `.kanban/` subdirectory or git file that the append made stays; it holds no event.
    - Discovery: before this change the live graph did not change on a failed append (the `writes` array is local), but the files kept the partial transaction, and the next commit check read them back.
  timestamp: 2026-10-09T13:26:16.782760+00:00
- actor: claude-code
  id: 01m4gdfr518bbfd3jpan6wn3pm
  text: |-
    ### implement — changed
    - evidence: 8 files — Sources/FoundationModelsKanban/Events/EventLogWriter.swift (new), Sources/FoundationModelsKanban/Events/LogFileMark.swift (new), Sources/FoundationModelsKanban/Tool/Commit.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Tests/FoundationModelsKanbanTests/Tool/CommitRollbackTests.swift (new), Tests/FoundationModelsKanbanTests/Tool/CommitTests.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift, plan.md. `swift test --filter CommitRollbackTests`: 5 of 5 pass. `swift test`: 1049 tests in 74 suites pass. No compiler warning other than the accepted SwiftPM "missing creator for mutated node".
    - next: /review
  timestamp: 2026-10-09T13:26:21.089416+00:00
position_column: doing
position_ordinal: '80'
title: 'Commit: no partial transaction on disk when an append fails'
---
## What
`Sources/FoundationModelsKanban/Tool/Commit.swift:536-538` and `:627-629` append one node file at a time, and then one board at a time. If an append throws after an earlier append succeeded, the call returns an error, but the earlier lines stay in the logs. plan.md §5.4 steps 5.3–5.5 describe an all-or-nothing commit.

Also, `append(recording:changing:)` in `Sources/FoundationModelsKanban/Tool/Commit.swift` calls `live.adopt` for each board in turn. Thus when the append of board 2 fails, board 1 is already adopted into its live graph.

- Before the first append, record the size of each file that the commit will append to (for a new file, record that it did not exist).
- If an append fails, truncate each changed file back to its size, and remove each new file, for each board. Do this while the locks are still held. Then throw the original error.
- Change `append(recording:changing:)` so that no board is adopted (`live.adopt`) until all appends of all boards succeed.
- The live graph and the signatures must not change when the commit fails.
- Make the append step testable: inject a file writer (or a fault hook) into the commit path, so that a test can make the Nth append fail.
- Update plan.md §5.4 to describe the rollback.

## Acceptance Criteria
- [ ] When the second append of a cross-board transaction fails, no file of either board changes, and the call returns an error.
- [ ] After a failure on board 2, the live graph of board 1 is unchanged.
- [ ] When an append to a new node file fails, the file does not exist after the call.
- [ ] The next call works normally and sees no part of the failed transaction.

## Tests
- [ ] A test in `Tests/FoundationModelsKanbanTests/Tool/` (for example `CommitRollbackTests.swift`) with a fault-injecting writer, for one board and for two boards.
- [ ] A two-board test: the append of board 2 fails, then a query of board 1 gives the same result as before the call.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.