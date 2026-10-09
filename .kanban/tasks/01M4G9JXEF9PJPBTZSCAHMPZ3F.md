---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gf69ejrfk5majbbbkpw21j
  text: |-
    Research:
    - `KanbanGraph.runSchemaCall` catches each `KanbanError` of the run or of the commit and returns it as an error response. `publishingChanges` sees a normal return, so it posts plans from the live changes. On `BOARD_BUSY`, `CommitSession.commit` applied the changed files of the other process to the live graph, so those task patches are in the changes, and the plan goes out although the call wrote nothing.
    - Plan: `runSchemaCall` gives a result that tells if a `KanbanError` failed the call. `publishingChanges` posts plans only for a call that did not fail. The change feed still gets the changes in both cases.
    - Test seams: the engine clock (`timedBy`) runs in each run of a call (working copy, and each mutation field). A test clock that writes a task log as a different process makes the commit check find a changed log in each run (BOARD_BUSY), or in the first run only (the applied change of a successful call). `GitGraphFixture.secondEngineIDs` gives the ids of the other process. `CrossRepoFixture.SideBySide` gives two boards. `BatchRecorder` and `BoardWatcherTests.hasBatch` wait for a watcher batch.
  timestamp: 2026-10-09T13:56:08.274507+00:00
- actor: claude-code
  id: 01m4gfgk8375q98ayw275nrzr3
  text: |-
    Implementation landed.
    - `KanbanGraph.swift`: new file-private `CallResult<Value>` (`completed` / `failed`). `runSchemaCall` gives `.failed` for each caught `KanbanError` (run or commit). `publishingChanges` takes a `CallResult`, sends the live changes to the change feed in all cases, and posts plans only for `.completed`. The watcher batch gives `.completed(())` with no context.
    - plan.md §7.3: "a call whose commit fails posts nothing"; the engine decides from the result of the commit, not from a throw.
    - Tests (AgentPlanPostTests, 8 tests now): two boards in repo-path order, BOARD_BUSY posts nothing, applied change of a different process is posted after a successful `addTag`, watcher batch posts nothing. Test seam: `OtherProcessClock` writes a task log in the engine clock (`writingOnce` / `writingAtEachRead`). `KanbanGraphTests.makeGraph` got a `timedBy` parameter. `CrossRepoWriteTests.addTaskToEachBoard()` is now shared by the cross-repo write test and the new two-board test.
    - RED: only the BOARD_BUSY test failed before the fix (2 events, expected 1). The other 3 rules already held. Mutation check: the watcher test fails when the batch posts to `ToolContext.current`, and the two-board test fails when the sort order is reversed. Both probes are reverted.
    - Choice: an I/O fault that throws also posts nothing (the same as before); plan.md says so.
  timestamp: 2026-10-09T14:01:45.987472+00:00
- actor: claude-code
  id: 01m4gfgnr21mrzmktgjnjn5scw
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, plan.md, Tests/FoundationModelsKanbanTests/Tool/AgentPlanPostTests.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoWriteTests.swift. `swift test --filter AgentPlanPostTests`: 8 of 8 pass. `swift test`: 1058 tests in 74 suites pass; the only warning is the accepted SwiftPM "missing creator for mutated node".
    - next: /review
  timestamp: 2026-10-09T14:01:48.546957+00:00
depends_on:
- 01M4G9HNAFASWXCDCPFTDYBDKJ
position_column: doing
position_ordinal: '80'
title: 'Agent plan: no post on a failed commit, and tests for each §7.3 rule'
---
## What
plan.md §7.3: "a call that throws post nothing". `Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:327-338` (`runSchemaCall`) catches a `KanbanError` from the commit (for example `BOARD_BUSY`) and returns it as a normal response. `publishingChanges` (`:383-397`) then posts plans from the live changes that the commit check applied, although the call wrote nothing.

- Decide from the result of the commit, not from a throw: when the commit of the call fails (any error from the commit path), post nothing. Update §7.3 to say "a call whose commit fails posts nothing".
- Keep this rule: a successful call also posts the plan of a board that the commit check changed from a different process.
- `Tests/FoundationModelsKanbanTests/Tool/AgentPlanPostTests.swift` has 4 tests. Add tests for the §7.3 rules that have no test:
  - A call that changes two boards posts one event for each board, in the sort order of the repo path.
  - A call whose commit fails (`BOARD_BUSY`) posts nothing.
  - A changed board that the commit check applied from a different process is in the posts of a successful call.
  - A file-watcher batch posts nothing while a `ToolContext` is bound to the first call.

## Acceptance Criteria
- [x] Each rule above has a test, and each test passes.
- [x] A `BOARD_BUSY` call posts no `.progress` event.

## Tests
- [x] The tests above in `AgentPlanPostTests.swift`.
- [x] `swift test --filter AgentPlan` and `swift test` pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.