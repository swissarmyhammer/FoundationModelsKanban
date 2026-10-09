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
- actor: claude-code
  id: 01m4gfrmy6c8edv36e4jyk4w28
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD — 2 findings (2 confirmed, 0 refuted) — Tests/FoundationModelsKanbanTests/Tool/AgentPlanPostTests.swift:150, Tests/FoundationModelsKanbanTests/Tool/AgentPlanPostTests.swift:257. The HEAD commit message agrees with the diff. Each acceptance item and each test item has a matching test in the diff.
    - next: /implement ^ahmpz3f to correct the open findings
  timestamp: 2026-10-09T14:06:09.862062+00:00
- actor: claude-code
  id: 01m4gfrpdjcv4z9qr7a73vzkxw
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 5 files
    - test: green — swift test, 1058 tests in 74 suites passed
    - commit: 15f6f12
    - review: findings — Tests/FoundationModelsKanbanTests/Tool/AgentPlanPostTests.swift:150, Tests/FoundationModelsKanbanTests/Tool/AgentPlanPostTests.swift:257
  timestamp: 2026-10-09T14:06:11.378059+00:00
- actor: claude-code
  id: 01m4gfzjhf4g7vjrtcq6wasqmf
  text: |-
    Review round 1 findings corrected (both reuse/reuse in AgentPlanPostTests.swift).
    - `Harness.init(timedBy:observingBatchesWith:)` is now the one place that makes the TemporaryDirectory and the engine of an empty-repo test. Both parameters have defaults (the fixed clock, no batch observer). `Harness()` still works.
    - The clock parameter is a maker `(EventLog) -> @Sendable () -> DateTime`, not a plain clock. Reason: `OtherProcessClock` writes to the event log of the board, so it needs the directory, and the directory must not be made in a second place. `makeHarnessWithOtherProcess` gives a maker that keeps the clock that it makes.
    - `Harness` has a new `root` property (the root directory of the repo of the engine). `watcherBatchPostsNothing` reads the event log from `harness.root`, and calls `Harness(observingBatchesWith:)`. `init(graph:at:keeping:)` takes the root; the two-board test gives `repos.app`.
    - No other copy of the setup stays in the file. The two-board test uses `GitGraphFixture.makeGraph` over git repos, which is a different setup.
  timestamp: 2026-10-09T14:09:56.783329+00:00
- actor: claude-code
  id: 01m4gfzme8d1sdw7dppdx4a89a
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/Tool/AgentPlanPostTests.swift. `swift test --filter AgentPlanPostTests`: 8 of 8 pass. `swift test`: 1058 tests in 74 suites pass; the only build warning is the accepted SwiftPM "missing creator for mutated node". Both findings are `- [x]`.
    - next: /review
  timestamp: 2026-10-09T14:09:58.728423+00:00
- actor: claude-code
  id: 01m4gg4vw2j5cdkg2jha0166sk
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD — 0 findings (0 confirmed, 0 refuted); 1 file reviewed, 2 .kanban files excluded by .reviewignore. Both round 1 findings are `- [x]`. The HEAD commit message (f6635d2) agrees with the diff: Harness.init takes timedBy and observingBatchesWith with defaults, Harness has a root property, init(graph:at:keeping:) takes the root, and the two-board test gives repos.app.
    - next: none — task is in done
  timestamp: 2026-10-09T14:12:50.178274+00:00
- actor: claude-code
  id: 01m4gg4wt7bcngvefc7hencwas
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 1 file
    - test: green — swift test, 1058 tests in 74 suites passed
    - commit: f6635d2
    - review: clean — 0 findings
  timestamp: 2026-10-09T14:12:51.143088+00:00
depends_on:
- 01M4G9HNAFASWXCDCPFTDYBDKJ
position_column: done
position_ordinal: c980
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

## Review Findings (2026-10-09 09:03)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/Tool/AgentPlanPostTests.swift:150` `reuse/reuse` — makeHarnessWithOtherProcess repeats the setup of Harness.init(). Both make a TemporaryDirectory, call KanbanGraphTests.makeGraph, and build a Harness with keeping:. Only the clock differs. A second copy of this setup can drift from the first. Add a clock parameter to Harness.init(), for example init(timedBy clock: @escaping @Sendable () -> DateTime = { KanbanGraphTests.time }). Then makeHarnessWithOtherProcess only builds the OtherProcessClock and calls that init. Keep one place that makes the directory and the engine.
- [x] `Tests/FoundationModelsKanbanTests/Tool/AgentPlanPostTests.swift:257` `reuse/reuse` — watcherBatchPostsNothing repeats the setup of Harness.init() a second time. It makes a TemporaryDirectory and calls KanbanGraphTests.makeGraph, then builds a Harness with keeping:. It also needs an observer, so it cannot call Harness.init() as it is. This is the same near-match as makeHarnessWithOtherProcess, and the two copies can drift apart. Give Harness.init() the options that the test engines need, such as a clock and a batch observer, each with a default. Then makeHarnessWithOtherProcess and watcherBatchPostsNothing both call that one init. This is the same fix as the earlier finding on line 150.
