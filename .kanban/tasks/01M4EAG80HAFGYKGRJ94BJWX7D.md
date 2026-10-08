---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4ebqn8fz4a5y2ytmgzm2y1e
  text: |-
    Research done. Findings and decisions:
    - Extras API (pin 5c1c638): `ToolContext.current` is a `@TaskLocal`; `ToolContext.progress(_ detail:, plan: PlanSnapshot?)` posts a `.progress` event to the sink. A test binds a context with `ToolContext(sessionID: ULID(), runPlane: RunPlane(), sink:, tool:, op:, completionToken:, isCancelled:)` and `ToolContext.$current.withValue(context) { ... }` (see Extras `ToolHostingPublicSurfaceTests`). `OperationEventSink` needs only `post(event:)`.
    - Commit result: `KanbanGraph.publishingChanges` calls `publishLiveChanges`, which calls `takeLiveChanges()` -> `[path: BoardChanges]`. Each `BoardChanges` holds the session (key, live graph) and the `LiveGraphChange` events. This is the data the commit path already has.
    - Trap: the file-watcher consumer is an unstructured `Task` made inside the first call, so it inherits `ToolContext.current`. Thus the engine must not read the task-local inside the gate code that watcher batches also run.
    - Board order lives in `BoardView.boardOrder(of:)` (private). Priority tags need it in `Readiness`, so the order moves to `Readiness` and `BoardView` reads it from there (no copy).
    DECISIONS:
    1. Where: `KanbanTool.call` reads `ToolContext.current` one time and gives it to an internal `KanbanGraph.execute(query:variables:operationName:postingPlansTo:)`. Public `execute` (CLI, GUI, tests) gives `nil`; `subscribe` and watcher batches give `nil`. With `nil`, no plan work happens.
    2. Which boards: the `[path: BoardChanges]` that `publishingChanges` already takes one time; a board is in the post when an event of its changes has a task patch node. One `.progress` event for each such board, in path order. Nothing is posted when the operation throws.
    3. Rounding: rank r (0-based) of an open live task in board order among n open live tasks; tier = r * 3 / n (integer division) over [HIGH, MEDIUM, LOW]. Thus HIGH count = ceil(n/3): 1 -> H; 2 -> H,M; 3 -> H,M,L; 7 -> 3 H, 2 M, 2 L.
  timestamp: 2026-10-08T18:17:14.255621+00:00
- actor: claude-code
  id: 01m4ecj8kxj8swb05a5ms3h8t2
  text: |-
    Implementation landed (TDD: each new test failed on an assertion first; the stub phase used empty stubs).
    Code:
    - `Derived/PriorityTier.swift` (new): `PriorityTier` high/medium/low, `init(atRank:amongOpenTasks:)` with the rounding rule, `virtualTag`.
    - `Derived/Readiness.swift`: board order moved here from `BoardView` (`taskOrder`, no copy left in QueryResolvers.swift); `priorityTier(ofTaskAt:)`; `column`/`isDone` share fileprivate Graph helpers with the board order.
    - `Derived/VirtualTags.swift`: cases `HIGH`, `MEDIUM`, `LOW` after `DONE`; not in `hiddenUnlessNamed`.
    - `Tool/AgentPlan.swift` (new): `PlanSnapshot(of:inBoard:)`, `Priority(_ tier:)`, status mapping, `BoardSummary.progressDetail`, `ToolContext.postAgentPlans(of:)`.
    - `Tool/KanbanGraph.swift`: internal `execute(...postingPlansTo:)`; `publishingChanges(postingPlansTo:)` takes the live changes one time for feed and post.
    - `Tool/KanbanTool.swift`: passes `ToolContext.current`.
    - plan.md: §2.2 `_plan` bullet, §4.1 virtualTags, §6 Virtual tags row (rounding rule), §6.3 `#tag` row and default selection, new §7.3 The agent plan, §8 layout and Extras dependency.
    Tests: new `Derived/PriorityTagsTests.swift`, `Tool/AgentPlanTests.swift`, `Tool/AgentPlanPostTests.swift` (actor `RecordingSink`), `FilterEvaluatorTests.priorityTags`. Existing expectations that list exact virtualTags were updated for the new tags (VirtualTagsTests x2, NodeQueryTests, QueryResolverTests x2, ChangeBuilderTests completeTask dependent, TaskOperationTests move out of done).
    Rules I had to interpret:
    1. "one progress event with the plan of each board": one event per changed board (an event carries one plan).
    2. "a mutation that changes no task sends nothing": decided by task patch nodes in the changes of the operation; a commit check that applied task changes of another process in the same operation also posts that board.
    3. The plan is posted inside the serial gate, so the post order matches the commit order.
    4. The tests "posts nothing" for direct execute also asserts the next tool call posts, so the test fails first on an assertion.
    Verification: periphery clean; root build no new warnings; 3 full root runs 1012/1012 pass; IntegrationTests 2/2 pass.
  timestamp: 2026-10-08T18:31:46.045196+00:00
- actor: claude-code
  id: 01m4ecjbhft62ztnyn93wqm1p2
  text: |-
    ### implement — changed
    - evidence: new Sources/FoundationModelsKanban/Derived/PriorityTier.swift, Sources/FoundationModelsKanban/Tool/AgentPlan.swift; changed Derived/Readiness.swift, Derived/VirtualTags.swift, GraphQL/QueryResolvers.swift, Tool/KanbanGraph.swift, Tool/KanbanTool.swift, plan.md; tests new Derived/PriorityTagsTests.swift, Tool/AgentPlanTests.swift, Tool/AgentPlanPostTests.swift, changed ReadinessFixture, VirtualTagsTests, FilterEvaluatorTests, NodeQueryTests, QueryResolverTests, ChangeBuilderTests, TaskOperationTests. `swift build --build-tests` only accepted warnings; `swift test --skip-build` x3 (120 s limit): 1012 tests pass each; IntegrationTests `swift build --build-tests && swift test`: 2 tests pass; periphery: no unused code.
    - next: /review
  timestamp: 2026-10-08T18:31:49.039443+00:00
- actor: claude-code
  id: 01m4ecxrjq8ds11y31jn6pmg5c
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (05ed623). 0 findings, 0 confirmed, 1 refuted, 21 attempted, 0 failed. 17 files reviewed. Not reviewed: 4 files in .kanban/ (.reviewignore) and plan.md (no validator matches).
    - next: none. The task is in done.
  timestamp: 2026-10-08T18:38:02.839720+00:00
- actor: claude-code
  id: 01m4ecxz58b0303fc3zm0dnxya
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — new Derived/PriorityTier.swift, Tool/AgentPlan.swift; Readiness, VirtualTags, QueryResolvers, KanbanGraph, KanbanTool; plan.md §7.3; 3 new and 7 changed test files
    - test: green — root swift test 3 runs, 1012 passed each (8.4 s, 7.7 s, 8.2 s); IntegrationTests 2 passed; build warnings only the 2 accepted kinds
    - commit: 05ed623
    - review: clean — 0 findings
  timestamp: 2026-10-08T18:38:09.576377+00:00
position_column: done
position_ordinal: c180
title: 'Send the ACP agent plan through ToolContext when a task changes; add #HIGH, #MEDIUM, #LOW derived tags'
---
## What
A person asked for this on 2026-10-08. The kanban tool must comply with the ACP agent plan (https://agentclientprotocol.com/protocol/v2/agent-plan). FoundationModelsExtras already has the API: `PlanSnapshot` (`id`, `entries`; `Entry(content:priority:status:)`; `Priority` high/medium/low; `Status` pending/in_progress/completed/cancelled) and `ToolContext.progress(_ detail: String, plan: PlanSnapshot?)` (commit ee4a798; the current pin 5c1c638 includes it, so no pin change). `ToolContext.current` is a task-local that is set while a host runs a tool call. The model never gets the plan; it goes to the client.

Rules:
- **When:** after a tool call (`KanbanTool.call`, and any other tool entry point) commits a transaction that changes at least one task (add, update, move, complete, assign, tag, delete, undelete, undo, redo), and `ToolContext.current` is not nil, post one `progress` event with the plan of each board that the transaction changed. A query, or a mutation that changes no task, sends nothing. With no `ToolContext.current` (for example the CLI or a direct `execute`), send nothing and do no extra work.
- **Plan id:** the board key, so that each board is one plan and an update replaces it.
- **Entries:** the full list, never a partial list: the live tasks of the board in board order (column order, then ordinal). `content` is the task title.
- **Status:** a task with `DONE` → `completed`; a task in the first column → `pending`; any other live task → `in_progress`. Deleted tasks are not in the plan.
- **Priority:** add three derived tags, `HIGH`, `MEDIUM`, `LOW`, from the place of a task in board order among the open (not `DONE`) live tasks: the first third is `HIGH`, the second third `MEDIUM`, the rest `LOW` (round so that a board with 1 or 2 open tasks gives `HIGH` first). A done task gets `LOW` in the plan and no priority tag. Use the same derived-tag code as `READY`, `BLOCKED`, `DONE` (`Derived/VirtualTags.swift`), so `#HIGH` etc. work in filters and show in `virtualTags`. They are not "hidden unless named" tags.
- **Detail:** a short text line for the model, for example "3 of 7 tasks done", from `BoardSummary`.

Files: `Sources/FoundationModelsKanban/Derived/VirtualTags.swift`, `Tool/KanbanTool.swift` (and where the commit result is known, for example `Tool/KanbanGraph.swift`), a new file for the plan builder (for example `Tool/AgentPlan.swift`), plan.md (a new section on the agent plan, and the derived-tag list).

## Decisions (implement step)
- **Where the post happens:** `KanbanTool.call` reads `ToolContext.current` one time and gives it to the internal `KanbanGraph.execute(query:variables:operationName:postingPlansTo:)`. The post is in one place: `KanbanGraph.publishingChanges(postingPlansTo:)`, after the operation returns, inside the serial gate. The public `execute`, `subscribe`, and the file-watcher batches give `nil`, so the CLI and a direct `execute` do no plan work.
- **Which boards:** the `[path: BoardChanges]` that `takeLiveChanges()` already gives the change feed; it is taken one time and given to both the feed and the post. A board is posted when an event of its changes has a task patch node. One `.progress` event for each such board, in path order. A call that throws posts nothing.
- **Rounding:** open task at rank r (from 0) of n open tasks gets tier `r * 3 / n` (integer division) over [HIGH, MEDIUM, LOW]; the first tier holds ceil(n/3) tasks. 1 → H; 2 → H, M; 3 → H, M, L; 7 → 3 H, 2 M, 2 L. Written in `PriorityTier.init(atRank:amongOpenTasks:)` and plan.md §6.

## Acceptance Criteria
- [x] A tool call that adds or moves a task under a bound `ToolContext` posts one `.progress` event whose `plan` has the board key as id and one entry for each live task in board order, with the title as `content` and the status and priority of the rules.
- [x] A query, a mutation that changes no task, and a call with no `ToolContext.current` post nothing.
- [x] `#HIGH`, `#MEDIUM`, `#LOW` appear in `virtualTags` and select the right tasks in a filter; they change when a task moves.

## Tests
- [x] Unit tests for the plan builder (status and priority mapping, ordering, rounding for 1, 2, 3, and 7 open tasks).
- [x] Tool tests that bind a `ToolContext` with a recording sink (see how FoundationModelsExtras tests do it, for example `ToolContextTests`) and check the posted events.
- [x] Derived-tag tests for `HIGH`, `MEDIUM`, `LOW`, including the inverse (a task that moves changes tier).
- [x] Run the full `swift test`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.