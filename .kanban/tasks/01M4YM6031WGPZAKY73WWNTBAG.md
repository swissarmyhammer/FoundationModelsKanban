---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m50yg7trjf4pjweyz08sdega
  text: |-
    Research and implementation notes:
    - Cause confirmed. With a worktree of the current repo as the second board, the events of the call have `boards: nil`, because the key of the second copy is the same as the key of the event's own board. So `boards(of:foundIn:among:)` got no key and reversed only the home board.
    - Fix: `boards(of:foundIn:among:)` now puts `key(of: home)` first in the key list, then the keys of the `boards` value. `copies(ofKey:holding:among:)` then looks in the scan, the host table, and the `boards` input for the home key. The home board always holds the txn, so this key never gives `transactionBoardNotLoaded`. `eachOnce` removes the home board when the scan gives it again.
    - Cost: an undo of a single-board txn now also asks `loadedTargets(withKey:)` for the home key. The first time, that can record a `.loadedCopies` request and make the call run again after the read. All 1540 tests pass with this.
    - RED: the new test `CrossRepoCopyUndoTests/undoReversesWorktreeOfCurrentRepo` failed. The worktree task kept its `addTask` event, and the two newest events had 2 different txns. GREEN after the fix.
    - Test helper: I moved the two expectations of `expectUndone` into the new `expectOneUndo(of:wrote:)`, so that the new test uses them and does not copy them.
    - divergence.md X5: added the sub-bullet "Second copy of the home board (closed by ^wwntbag)". plan.md was not changed.
  timestamp: 2026-10-15T23:31:33.848022+00:00
- actor: claude-code
  id: 01m50ygcamqkgfhh14c015tgq9
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/GraphQL/UndoMutations.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCopyUndoTests.swift, divergence.md. RED then GREEN on `swift test --filter CrossRepoCopyUndoTests/undoReversesWorktreeOfCurrentRepo`. Full `swift test`: 1540 tests in 122 suites passed. The only build warning is the accepted mlx "missing creator" warning.
    - next: /review
  timestamp: 2026-10-15T23:31:38.452263+00:00
- actor: claude-code
  id: 01m50yqtz5jg55hg9n3e2p12mq
  text: |-
    ### test — green
    - evidence: swift build complete, 1 warning (allowed SwiftPM "missing creator"). swift test: 1540 tests in 122 suites passed, 0 failures, 0 skipped, no time-limit failures, first run. IntegrationTests with scratch path integration-build: 3 tests in 3 suites passed, 0 failures.
    - next: review
  timestamp: 2026-10-15T23:35:42.821846+00:00
- actor: claude-code
  id: 01m50yrh5mhfh9fgpm0pwhp8wc
  text: |-
    ### commit — changed
    - evidence: local commit "fix(undo): reverse a second copy of the home board in one undo (^wwntbag)". Files: Sources/FoundationModelsKanban/GraphQL/UndoMutations.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCopyUndoTests.swift, divergence.md, and the changed .kanban/tasks files. The sha is in the step block of the caller, because a comment cannot hold its own sha. Not pushed.
    - next: none
  timestamp: 2026-10-15T23:36:05.556189+00:00
- actor: claude-code
  id: 01m50z3gk9ee5yy13kctgnztpc
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (3b05aad). 1 finding, 1 confirmed, 0 refuted. Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCopyUndoTests.swift:201 (completeness/inverse-operation-coverage): no test does redo on a worktree of the current repo.
    - next: Add a redo step to undoReversesWorktreeOfCurrentRepo, or add a sibling test that does undo and then redo on the worktree of the current repo. Make sure that redo changes each event in the two copies. Then do the review again. The task stays in review.
  timestamp: 2026-10-15T23:42:05.417823+00:00
- actor: claude-code
  id: 01m50z3v7temyamm0ky1a1sw6s
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — UndoMutations.swift, CrossRepoCopyUndoTests.swift, divergence.md X5
    - test: green — swift test, 1540 passed; IntegrationTests 3 passed
    - commit: 3b05aad
    - review: findings — Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCopyUndoTests.swift:201
  timestamp: 2026-10-15T23:42:16.314501+00:00
- actor: claude-code
  id: 01m50zk434xbmrn78yacb1h7nf
  text: |-
    Redo coverage for the review finding `completeness/inverse-operation-coverage`:
    - Added the sibling test `CrossRepoCopyUndoTests/redoRestoresWorktreeOfCurrentRepo`. It does undo, then redo, on a call that changed the current board and a second worktree of the current repo. It makes sure that one undo txn tombstoned each task, and that one redo txn with `undoes` = the undo txn makes each task live again in both copies.
    - Redo did not fail. No change to production code was necessary.
    - Check that the test can fail: I removed `[key(of: home)] +` from `boards(of:foundIn:among:)` for a short time. The new test then failed with 4 issues: the worktree task kept its `addTask` event, and the newest events had 2 different txns. I put the code back; `git diff -- Sources` is empty.
    - Test helpers: `expectOneUndo(of:wrote:)` is now `expectOneReverse(of:wrote:deleting:)`, so that the undo and redo checks use one function. The new struct `WorktreeCall` makes the repos and runs the call for the two worktree tests. The new helpers `addTask(toAppAt:andCopyAt:on:)` and `lastEvents(of:appAt:copyAt:)` hold the code that the second-copy helpers and `WorktreeCall` both use, so that no block is copied.
  timestamp: 2026-10-15T23:50:36.900644+00:00
- actor: claude-code
  id: 01m50zkagdnq14b7ckgpat0d02
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCopyUndoTests.swift. `swift test --filter CrossRepoCopyUndoTests`: 7 tests in 1 suite passed. Full `swift test`: 1541 tests in 122 suites passed, 0 failures, on the first run. The only build warning is the accepted mlx "missing creator" warning. The new test failed when the home-key fix was removed for a short time; the fix is back, and Sources has no diff. The review finding item is now `- [x]`.
    - next: /review. The task stays in doing.
  timestamp: 2026-10-15T23:50:43.469164+00:00
- actor: claude-code
  id: 01m510hms46dy707ex8kjew35z
  text: |-
    ### test — green
    - evidence: `swift build` clean (only the allowed SwiftPM "missing creator" warning). Full `swift test`, final run: 1541 tests in 122 suites, 0 failed, 0 skipped. No compiler warning.
    - run 1: 24 issues, all "Time limit was exceeded: 60.000 seconds" (machine load). The 5 failing suites alone (CrossRepoTransferTests, DependencyTargetWarningTests, CrossRepoEventBoardTests, CrossRepoCycleTests, CrossRepoCopyUndoTests): 37 tests passed. The new redo test passed. No time limit was raised.
    - run 2: 1 real failure, not a time limit. Test "Each example script gives the result that the skill shows" in KanbanSkillTests: `redo` gave null data, or the task was missing after `redo`.
    - cause: `ReadmeExamplesTests.ExampleBoard` made no first commit, so the engine made it. The commit is empty, has the same message "Initial commit", the same author, and the same second. Boards of tests that run at the same time thus got the same key (the key is the hash of the first commit). The engine of each test saw the other board as a copy of its own board. Both sessions use the same actor, so `redo` of one test took the newest `undo` of the other test. This was a race in the test fixture, not a fault in the product code.
    - fix: in `/Users/wballard/github/swissarmyhammer/FoundationModelsKanban/Tests/FoundationModelsKanbanTests/ReadmeExamplesTests.swift`, `ExampleBoard.init` now makes an empty first commit with a new UUID in the message before it makes the engine. The suite doc comment and the init doc comment say this. Each board now has its own key.
    - proof: run 3 (full suite after the fix) passed: 1541 tests, 0 issues. The skill test passed together with `examplesUseCanonicalNames`.
    - note: I added a temporary print probe to `UndoMutations.swift` and a probe test, and I made one temporary one-line change to the home key search to find the cause. I removed all of them. `UndoMutations.swift` is the same as HEAD. The two runtime `warning FoundationModelsKanban ... Replay skips a log line` lines are log output from tests that feed bad lines on purpose, not compiler warnings.
    - next: review
  timestamp: 2026-10-16T00:07:17.028674+00:00
- actor: claude-code
  id: 01m510jgs8g973x1n3q8h65qhg
  text: |-
    ### commit — changed
    - evidence: local commit "test(undo): cover redo on a second copy of the home board (^wwntbag)". Files: Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCopyUndoTests.swift, Tests/FoundationModelsKanbanTests/ReadmeExamplesTests.swift, and the changed .kanban/tasks files. The sha is in the step block of the caller, because a comment cannot hold its own sha. Not pushed.
    - next: review
  timestamp: 2026-10-16T00:07:45.704187+00:00
position_column: doing
position_ordinal: '80'
title: 'Undo: find a second copy with the key of the home board in the same transaction'
---
## What
Found during ^14fa5z2. The `boards` value of an event holds only the keys of the other boards: the key of its own board is removed (S/Tool/Commit.swift `Event.recording(operations:changing:inBoard:)`). When one transaction writes two copies (worktrees) of the same repo, and the undo finds the transaction first in one of these copies (the home board), the other copy with the same key is not in `boards`. Then `BoardStore.boards(of:foundIn:among:)` in S/GraphQL/UndoMutations.swift does not look for it, and the undo reverses only part of the transaction.

## Change
- [x] Also look for the key of the home board in the host table and in the `boards` input, and reverse each other copy with that key that holds events of the txn.

## Tests
- [x] A transaction that writes the current board and a second worktree of the current repo is reversed on both by one `undo`.
- [x] Tests use temporary fixture folders, never the `.kanban/` of this repo.
- [x] `swift test` passes.

## Review Findings (2026-10-15 18:36)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 2 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `divergence.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCopyUndoTests.swift:201` `completeness/inverse-operation-coverage` — The new test undoReversesWorktreeOfCurrentRepo covers only the undo direction. The fix changes boards(of:foundIn:among:), which the redo field also calls through reverse(.redo, ...) (UndoMutations.swift:82, 224). No test runs redo on a worktree of the current repo, so the redo direction of the new case is unproven. Add a redo step to undoReversesWorktreeOfCurrentRepo, or a sibling test that undoes and then redoes the same call on the worktree of the current repo. Assert that the redo tombstones or restores each event in both copies, using the same expectOneUndo-style check.
