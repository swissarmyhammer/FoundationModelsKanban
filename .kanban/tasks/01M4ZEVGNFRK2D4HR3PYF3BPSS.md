---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m515cav5hdr36723wqfvadx7
  text: |-
    ### finish iteration 1 — stuck
    - no step ran. The acceptance criteria say "The user decides." The orchestrator does not choose between option A (comments stay on the tombstone) and option B (copy comments to the new task in the same transaction).
    - next: the user picks A or B. Then /finish can run the task.
  timestamp: 2026-10-16T01:31:45.893730+00:00
- actor: claude-code
  id: 01m52k7v46n68m4fp8ra471bxb
  text: |-
    ### decision — user
    - The user chose option A: keep the current behavior. The comments stay on the old task (the tombstone). The tombstone body has the line with the new URI.
    - next: /implement records the decision in divergence.md (Q21). No code change is necessary unless a test is missing for this behavior.
  timestamp: 2026-10-16T14:53:13.222296+00:00
- actor: claude-code
  id: 01m53531y2wvwbs2mx1jzpszb4
  text: |-
    ### research
    - No test covers the comments after `moveTask(board:)`. `T/CrossRepo/CrossRepoTransferTests.swift` has no comment test.
    - Discovery: `Task.comments` gives no comments for a tombstoned task (`S/Derived/BrokenMergeDisplay.swift`, `comments(ofTaskAt:)` returns `[]` when the task is not live). Thus after a move, `Task.comments` of the old task (the tombstone) is empty. The comment nodes stay live and keep their edge to the old task. A reader gets them with `node(id:)` on the comment URI, and `Comment.task` gives the old task. An `undo` of the move makes the old task live again, and then `Task.comments` shows the comments again.
    - Plan: add one test in `CrossRepoTransferTests` (the comment stays live on the old task; the new task has no comments). Record option A in divergence.md Q21, E6, and the Q21 change list.
  timestamp: 2026-10-16T20:05:10.722691+00:00
- actor: claude-code
  id: 01m535neyxgtsfzq3zg67rykz8
  text: |-
    Implementation landed.
    - Test: `moveKeepsCommentsOnOldTask` in `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoTransferTests.swift`. It adds a comment to a task, moves the task to the related repo, then reads the comment with `Query.node`: the comment is live and `Comment.task` is the old task. `Task.comments` of the new task is empty. This test pins the current behavior (option A), so it passed on the first run. A change that copies or moves the comments to the new task (option B) makes it fail.
    - Helpers: `transfer` now calls a new helper `id(givenBy:named:on:)` (run a mutation, expect no error, give the id). `task(_:selecting:on:)` now calls a new helper `node(_:ofType:selecting:on:)`. This removes a copy of the same code for the comment read.
    - divergence.md: Q21 has a new bullet "Comments after a move. DECIDED: option A" (it includes the `Task.comments` behavior on a tombstone, the undo, and the copy). E6 has a new line. The Q21 change list in section 11 has a new line.
    - Card: option B criterion marked NOT APPLICABLE.
    - Mistake: I made one edit to divergence.md with a `python3` command through the shell, not with the files tool. The result is correct (git diff checked).
    - Tests: `swift test --filter CrossRepoTransferTests`: 25 tests in 1 suite passed. Full `swift test`: 1572 tests, 293 issues, almost all 60 s time limits and FSEvents waits in many suites. The baseline with the test file change stashed gave 1571 tests and 284 issues of the same kind. Thus the full-suite failures are not caused by this change. ^vm0j67z records the same machine-load failures.
  timestamp: 2026-10-16T20:15:13.885480+00:00
- actor: claude-code
  id: 01m535nh1kz18qzxdppztkenhd
  text: |-
    ### implement — changed
    - evidence: 2 files — Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoTransferTests.swift, divergence.md (and the card). `swift test --filter CrossRepoTransferTests`: 25 tests passed. Full `swift test`: 293 issues, baseline without the change: 284 issues of the same kind (time limits under load), not from this change.
    - next: /review
  timestamp: 2026-10-16T20:15:16.019857+00:00
- actor: claude-code
  id: 01m5375a4eym8dz476psym4avp
  text: |-
    ### finish iteration 2 — stuck
    - implement: changed — 2 files: Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoTransferTests.swift (new test moveKeepsCommentsOnOldTask, 2 helpers), divergence.md (Q21 option A, E6, section 11)
    - test: red — swift test full: 1572 tests, 287 issues (60 s time limits and FSEvents waits). swift test --filter CrossRepoTransferTests: 25 passed, 0 issues. The 301 tests of the 33 failing files with --no-parallel: 15 issues, all FSEvents waits.
    - cause: machine load. sourcekit-lsp (child of sah serve) ran at 560% CPU in an index-build loop. fseventsd ran at 107% CPU. The same failures occur without the change (^vm0j67z).
    - commit: not run. The tree is not green.
    - review: not run.
    - next: a human stops the sourcekit-lsp index loop. Then /finish ^yf3bpss runs the test step again. The change stays uncommitted in the working tree.
  timestamp: 2026-10-16T20:41:21.806367+00:00
- actor: claude-code
  id: 01m53fgd07nr925en6b6d4k6wb
  text: |-
    ### decision — user
    - The user says the machine is not too busy. The cause is the test time limits. Remove the time limits from the tests.
    - next: /implement removes each test time limit (the `.timeLimit` traits and the fixed deadlines in the test wait helpers). Then /test runs the full suite again.
  timestamp: 2026-10-16T23:07:13.799530+00:00
- actor: claude-code
  id: 01m53fzxg3vhw5angtyfpagp5n
  text: |-
    ### research — time limits in the tests
    - Baseline full `swift test` (before this step): 1572 tests, 290 issues. 214 of them are "Time limit was exceeded: 60.000 seconds". The full run took 186 s.
    - Probable cause of the 60 s failures: Swift Testing starts the clock of `.timeLimit` before the scope traits, so the wait of a test for a slot of `.watcherBudget` (16 slots, 83 suite files) counts in its 60 s. A test that waits in the queue fails, also when its own work is fast.
    - Inventory: `.timeLimit` on 40+ `@Suite`/`@Test` declarations; `StreamWait` (10 s for each FSEvents batch or change feed wait); `EventLogTests.becomesTrue(within:)` / `isLockReleased(within:)` / `releaseOnOwnThread` deadline; `KanbanHostTests` adoption, consumer hold, and retirement limits; `SearchReadinessTests` hold and merge limits; `StageOverlapProbe.holdSeconds` (LoaderTests); `BoardKeyTests.childWaitLimit` and `parallelGitLimit`; `CountingKeyReader.blockLimit` (BoardLocatorTests); IntegrationTests `TemporaryGitRepo.gitTimeLimit` and `ModelVariablesTests` 30 min limit.
    - Not test limits (they stay): `Git.run(timeLimit:)` in `slowCommandTimesOut` tests the production time-out feature; delays such as `keyReadDelay` and `loadDelay` make an overlap and record no failure.
  timestamp: 2026-10-16T23:15:42.211133+00:00
- actor: claude-code
  id: 01m53g5t9srmkkdjh9cpbwb25k
  text: 'Progress: I removed `.timeLimit` from 33 suite files. I deleted `StreamWait.swift`. `BoardWatcherTests.hasBatch` and `SubscriptionTests.events`/`allEvents` now read the stream until the event comes or the stream ends, with no deadline. `allEvents` now gives `[String]`, not `[String]?`. The file-scope minute constants of 4 suites are gone. A sub-agent is changing the other wait helpers (EventLog lock waits, KanbanHost, SearchReadiness, Loader probe, BoardKey child waits, CountingKeyReader block, IntegrationTests git wait and model test limit).'
  timestamp: 2026-10-16T23:18:55.545192+00:00
- actor: claude-code
  id: 01m53kxy79ahn1wyk3x80kn1x5
  text: |-
    ### Findings — the hang after the time limits were removed
    - All test time limits are gone (the `.timeLimit` traits, `StreamWait`, the lock and wait deadlines in EventLog, KanbanHost, SearchReadiness, Loader, BoardKey and BoardLocator tests, and the IntegrationTests git wait and model test limit). The build gives no warning.
    - Full `swift test`, run 1: stopped at 0% CPU after more than 30 min. Run 2: stopped after 1042 tests.
    - `sample` of the stopped process: each thread of the cooperative pool blocks in `FSEventsGetCurrentEventId > mach_msg` or `FSEventStreamStart > mach_msg`, called from `FolderStreams.add` and `replaceStream`. fseventsd does not answer, so no task can run. `swift-inspect dump-concurrency`: 1033 tests wait for a `WatcherBudget` slot.
    - fseventsd (pid 574, up 8 days) uses 100% CPU and 29 GB of memory, also with no test process. With no test process, an FSEvents probe outside this package gets its event of one write after 0.2 s to 15 s. While the test process runs, the probe gets no answer at all from `FSEventStreamStart`. When the test process ends, fseventsd answers again.
    - What did not help: a first stream with `kFSEventStreamEventIdSinceNow` instead of the current event id (the batch delay stays 5 to 15 s). I reverted that experiment and the diagnostic print. Sources/ has no change.
    - A code bug that I found: the FSEvents calls of `FolderStreams` run on the cooperative pool. I added task ^4p9q125 for it.
    - One more effect of the slow fseventsd: `ScanCacheTests.readsRunNoGit` failed when run alone, because a late batch of the setup arrived after the first scan.

    ### implement — stuck
    - evidence: 46 test files changed (time limits removed), Tests/FoundationModelsKanbanTests/Observe/StreamWait.swift deleted. `swift build --build-tests`: no warnings. Full `swift test` does not end: the process stops when fseventsd does not answer. Suites run alone pass (FolderStreamsTests 13/13; BoardWatcher, ScanCache, PathBoardKey, ReplacedRepo, CrossRepoReadinessCache: 32 tests, 2 issues in ScanCacheTests.readsRunNoGit).
    - next: a person restarts fseventsd (`sudo killall fseventsd`, or a reboot), because it uses 100% CPU and 29 GB with no client. Then run the full `swift test` again. Task ^4p9q125 fixes the pool block.
  timestamp: 2026-10-17T00:24:31.721686+00:00
- actor: claude-code
  id: 01m53kyc2qef49axz4457y2be9
  text: 'Correction to the step record: `git status` shows 41 changed test files (39 in Tests/, 2 in IntegrationTests/) and 1 deleted file (StreamWait.swift), plus divergence.md from the earlier step. It is not 46.'
  timestamp: 2026-10-17T00:24:45.911644+00:00
- actor: claude-code
  id: 01m53kz6xvvtkhkm752df56y4p
  text: |-
    ### finish iteration 3 — stuck
    - implement: stuck — time limits removed: .timeLimit traits, StreamWait.swift deleted, fixed deadlines removed from wait helpers in 41 test files (39 Tests/, 2 IntegrationTests/), lockWaitEndsAtDeadline removed. swift build --build-tests: no warnings.
    - test: full swift test hangs at 0% CPU (run 2 stopped after 1042 tests). Each Swift task thread is blocked in FSEventsGetCurrentEventId / FSEventStreamStart, called from FolderStreams.add and replaceStream on the cooperative pool. fseventsd: 8 days up, 100% CPU, 29 GB.
    - open: ScanCacheTests.readsRunNoGit, 2 issues (a late setup file event makes the next read run git).
    - commit: not run. review: not run.
    - next: ^4p9q125 moves the FSEvents calls off the cooperative pool. Then the full swift test runs again on this task.
  timestamp: 2026-10-17T00:25:13.403567+00:00
position_column: doing
position_ordinal: '8280'
title: Decide what moveTask(board:) does with the comments of the moved task
---
## What
`moveTask(board:)` (^7jyymre, divergence.md Q21) makes a new task on the target board and tombstones the old task. The comments of the old task stay on the old task (a tombstone). The new task has no comments. divergence.md Q21 and E6 do not name comments.

## Decide
- Option A: keep the current behavior. The old task body has the line with the new URI, so a reader can find the old comments through the tombstone.
- Option B: copy each comment to the new task on the target board, in the same transaction (the author ref becomes a full URI of the old board, the same as an assignee).

## Decision
The user chose option A (see the comments).

## Acceptance Criteria
- [x] The user decides. divergence.md records the decision. (Q21, E6, and the Q21 change list in section 11.)
- [x] Option A: a test with two temporary git repos shows that the comment stays live on the old task, and that the new task has no comments (`moveKeepsCommentsOnOldTask` in `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoTransferTests.swift`).
- [x] ~~For option B: a test with two temporary git repos shows the comments on the new task, and one `undo` removes them.~~ NOT APPLICABLE: the user chose option A.