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
- actor: claude-code
  id: 01m4gds0kkhnxj462y6sgtf9y1
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD — 1 finding (1 confirmed, 2 refuted): Tests/FoundationModelsKanbanTests/Tool/CommitRollbackTests.swift:103 (reuse/reuse). The commit message of 83ca850 agrees with the diff. The diff meets all 4 acceptance criteria and all 3 test items. The implement step must check these 7 items.
    - next: /implement the open finding, then check the 7 met items.
  timestamp: 2026-10-09T13:31:24.659636+00:00
- actor: claude-code
  id: 01m4gds1q2545c23fexyqskjbm
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 8 files
    - test: green — swift test, 1049 tests in 74 suites passed
    - commit: 83ca850
    - review: findings — Tests/FoundationModelsKanbanTests/Tool/CommitRollbackTests.swift:103
  timestamp: 2026-10-09T13:31:25.794418+00:00
- actor: claude-code
  id: 01m4ge0vvf0wp5mh5a5bkmqkef
  text: |-
    Review round 1 finding is fixed in CommitRollbackTests.swift.
    - New `expectFault(_ call: () async throws -> Void)` holds the one do/catch check. `expectFault(running:settingTitlesOf:_:)` and `expectTwoBoardFault(on:)` both call it. The first one captures the `inout` session in the closure that it gives.
    - The same cause was also in other parts of the file, and these parts are now shared too: the one-board setup (TemporaryDirectory, writeBoard, FaultingLogWriter, makeSession) is now `makeFailingBoard()` -> `FailingBoard`. The two setTitle calls that 3 tests repeated are now in `expectFault(running:settingTitlesOf:_:)`. The two-board setup (directory, app, lib, graph) is now `makeTwoBoards()` -> `TwoBoards`, which replaces `makeTwoBoardGraph(at:failingIn:)`. Two `EventLog(repositoryAt: lib)` calls are now one `libLog`.
    - Each fixture struct keeps its TemporaryDirectory, so the directory stays until the test ends.
    - I verified the 7 acceptance and test items against the code: `CommitSession.append(_:recording:)` appends all boards first, adopts on a copy only after all appends succeed, and rolls back each LogFileMark on an error while the locks are held. plan.md §5.4 step 5 states the rollback. I set all 7 items and the finding to checked.
  timestamp: 2026-10-09T13:35:41.935298+00:00
- actor: claude-code
  id: 01m4ge0y1x2rvtwsn7afeynp25
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/Tool/CommitRollbackTests.swift. `swift test --filter CommitRollbackTests`: 5 of 5 pass. `swift test`: 1049 tests in 74 suites pass. The only compiler warning is the accepted SwiftPM "missing creator for mutated node". Finding and 7 met items checked (8/8).
    - next: /review
  timestamp: 2026-10-09T13:35:44.189921+00:00
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
- [x] When the second append of a cross-board transaction fails, no file of either board changes, and the call returns an error.
- [x] After a failure on board 2, the live graph of board 1 is unchanged.
- [x] When an append to a new node file fails, the file does not exist after the call.
- [x] The next call works normally and sees no part of the failed transaction.

## Tests
- [x] A test in `Tests/FoundationModelsKanbanTests/Tool/` (for example `CommitRollbackTests.swift`) with a fault-injecting writer, for one board and for two boards.
- [x] A two-board test: the append of board 2 fails, then a query of board 1 gives the same result as before the call.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-09 08:28)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/Tool/CommitRollbackTests.swift:103` `reuse/reuse` — `expectTwoBoardFault(on:)` repeats the do/catch body of `expectFault(running:_:)` (same `Issue.record` on success, same `catch let error as EventLogError` with `#expect(error == FaultingLogWriter.fault)`). Only the run call differs. The near-match is not extended, so the expected-fault check now exists in two places. Extract the shared check into one helper that takes the call as a closure, for example `expectFault(_ call: () async throws -> Void)`, and have `expectFault(running:_:)` and `expectTwoBoardFault(on:)` both call it with their own run statement. This is a judgment call because `expectFault` takes an `inout` session, so the closure must capture it.
