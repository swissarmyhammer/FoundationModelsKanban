---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4eh0dw0k1knmpkztrjwjyrc
  text: |-
    Research:
    - The hidden set is `VirtualTag.hiddenUnlessNamed = [.deleted, .done]` (Derived/VirtualTags.swift). `TaskFilter` uses it with `FilterExpr.names(_:)` (Filter/FilterEvaluator.swift). `TaskSelection`, `ChangeFilter` and `TaskSearch` (through `TaskSelection`) all use `TaskFilter`.
    - Only the DONE default uses the `.column` case of `names(_:)` ("a column atom names DONE"). The ref and `~task` cases are generic over the hidden set, and DELETED uses them.
    - `nextTask` filters on READY first, so it does not change.
    - `AgentPlan` does not use a filter. No change there.
    - The tests use `QueryFixture.liveTasksFilter = "#DONE || !#DONE"` in about 10 places (FilterCompatibility, NodeQuery, QueryResolver, NameRewrite, KanbanGraph, KanbanTool, Portability, TagMutation). Several fixtures (KanbanGraphTests, TagMutationTests, BoardWatcherTests) have only a terminal column, so their tasks are done.
    - `ChangeFilter` with no filter keeps each update already (no hidden state). With a filter it uses `TaskFilter`.
  timestamp: 2026-10-08T19:49:24.480737+00:00
- actor: claude-code
  id: 01m4ehg15vwn4266de7kpc4h2t
  text: |-
    Implementation landed (TDD: RED run had 33 failing tests, all for the expected reason; then GREEN).
    - Code: `VirtualTag.hiddenUnlessNamed = [.deleted]` (one mechanism stays). `FilterExpr.names(_:)`: the `.column` case ("a column atom names DONE") is removed; `.column` and `.assignee` now give `false`. Doc comments changed in VirtualTags, FilterEvaluator, TaskFilter, TaskSelection, Schema (`FilterArguments.filter`), QueryResolvers (`tasks`, `searchTasks`, `TaskHolderObject.tasks`), TaskSearch.
    - Tests: removed `QueryFixture.liveTasksFilter` / `liveTasksArguments` (`#DONE || !#DONE`) and each use of them; the queries now give no filter. New tests: no filter lists the done task and no tombstone (NodeQueryTests); no filter on Column/Actor/Tag `tasks` lists done tasks; `#bug` lists the done bug; `#DONE`, `!#DONE`, `#bug && !#DONE`, `%done && !#DONE` select exactly; `searchTasks` with no filter finds the done task, `!#DONE` leaves it out; history with `#bug` or `#DONE` keeps a done task; a subscription with `!~actor` sends the change of a done task. `doneNamings` now expects that only `#DONE` names DONE.
    - plan.md: §3.3 rule 3, the SDL comment of `tasks`, §6 virtual tags, the `#tag`/`^id`/`%`/`~task` rows, §6.3 "Default selection", §6.4 filter, §6.7 filter, §11 filter compatibility and column atom, and decision 22.
    - Discovery: `#DONE || !#DONE` still shows in `.kanban/tasks/01M4EGDQ98AX4RVJ8KRY3ZEWMZ.*` (this card) and `.kanban/tasks/01M4E2MCSNEA5GS581W5QZEQ1H.*` (^5qzeq1h). These are event logs and history of the board, not product text, so I did not change them. No Sources, Tests, plan.md, README, tool description or CLI help text has it.
    - Discovery: `nextTask` needs no change; it filters on READY first.
  timestamp: 2026-10-08T19:57:55.771021+00:00
- actor: claude-code
  id: 01m4ehg4xh424ct0qqre0wyrdn
  text: |-
    ### implement — changed
    - evidence: 7 Sources files (Derived/VirtualTags.swift, Filter/FilterEvaluator.swift, Filter/TaskFilter.swift, GraphQL/TaskSelection.swift, GraphQL/Schema.swift, GraphQL/QueryResolvers.swift, Search/TaskSearch.swift), 14 Tests files, plan.md. `swift build --build-tests` clean (only the accepted mlx "missing creator" warning). `swift test --skip-build` 3 times: 1021 tests in 72 suites passed each time (7.6 s, 7.5 s, 7.6 s). IntegrationTests `swift build --build-tests && swift test`: 2 tests in 2 suites passed. periphery: no unused code.
    - next: /review
  timestamp: 2026-10-08T19:57:59.601282+00:00
- actor: claude-code
  id: 01m4ehvwypvawarp7rp2h0dzz6
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (78a122f); 1 finding (1 confirmed, 1 refuted) — Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift:269 duplication/duplication
    - next: implement the open item in the "Review Findings (2026-10-08 15:02)" section. The task stays in review.
  timestamp: 2026-10-08T20:04:24.662102+00:00
- actor: claude-code
  id: 01m4ehw6c5keh97rcpdemkd3xy
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 7 source files, 14 test files, plan.md; the hidden set is now only DELETED
    - test: green — root swift test 3 runs, 1021 passed each (8.1 s, 7.8 s, 7.9 s); IntegrationTests 2 passed; build warnings only the 2 accepted kinds
    - commit: 78a122f
    - review: findings — Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift:269
  timestamp: 2026-10-08T20:04:34.309603+00:00
- actor: claude-code
  id: 01m4ej10t9pq47v44m927gmnrz
  text: |-
    Finding SubscriptionTests.swift:269 duplication/duplication is fixed.
    - `changeWithNoMatchingUpdateIsNotSent` is now the parameterized test `filteredSubscriptionSendsTitleChange(filterCase:)` with `@Test(arguments: titleFilterCases)`. `filterWithNoDoneAtomSendsDoneTask` is deleted.
    - New case type `TitleFilterCase` (Sendable, CustomTestStringConvertible): `filter` is a `@Sendable (ULID) -> String`, because the `^id` filter needs the ULID of the fixture task, and that ULID is known only after `writeFixture`. `addsOtherTaskFirst` controls the `addTask` line. `proves` is the old test name, and it is the case name in the test output.
    - Expected outcome: in both cases it is the same. The next event is the title change event of the fixture task (the same `#expect` as before). The doc comment of `TitleFilterCase` says this. I did not add a field with only one value, because it would be dead code.
    - Case 1: `^id` filter, addTask runs first: the change of the added task is not sent. Case 2: `!~actor`, no addTask: the change of a done task (the fixture task is in the only column, so it is done) is sent.
    - Other tests in the file: `commitSendsOneChange` and `deletedFilterLeavesOutUndelete` read two events and make different changes; the other tests change the log from outside, use related boards, or check errors. None has the same shape, so I did not fold them in.
    - Discovery: `dump validators` writes a rule file of 754 K characters, and the `files` tool cannot read it (grep output is also too large). I used the rules that the caller listed: doc comments, lines of 120 characters or fewer, no magic numbers, no duplicated code, test integrity.
    - Test count: 1021 before, 1020 now (2 test functions became 1 function with 2 cases).
  timestamp: 2026-10-08T20:07:12.457470+00:00
- actor: claude-code
  id: 01m4ej12de4nqqmwcah5ee5c26
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift. `swift build --build-tests` clean (only the accepted "missing creator" warning). `swift test --skip-build` 3 times: 1020 tests in 72 suites passed each time (7.75 s, 7.68 s, 7.87 s); the parameterized test passed with 2 test cases each run.
    - next: /review
  timestamp: 2026-10-08T20:07:14.094319+00:00
depends_on:
- 01M4EGCVYHARE5N564SE2WKEQZ
position_column: doing
position_ordinal: '80'
title: 'No filter means no filter: done tasks are not hidden by default'
---
## What
A person said on 2026-10-08: "for 'all tasks' you should have 'no filter' not some conjunction. no filter means no filter". Today a task list leaves out done tasks unless the filter names `#DONE` or a column (^5qzeq1h), so "all tasks" needs `#DONE || !#DONE`. That is wrong.

- Remove `DONE` from the "hidden unless named" set in `Filter/TaskFilter.swift` / `Derived/VirtualTags.swift`. A task list with no filter gives every live task, done ones included. A filter selects exactly what it says: `!#DONE` gives the open tasks, `#DONE` the done tasks.
- `DELETED` stays hidden unless named: a deleted task is a tombstone, not a task on the board. (If the person wants tombstones in "no filter" too, that is a one-line change of the set.)
- `nextTask` is not changed: it picks only `READY` tasks, and a done task is never `READY`.
- Remove the code that only the `DONE` default and the "a column names DONE" rule use. Keep one mechanism for the hidden set.
- Update the tests that expect done tasks to be left out by default, `Column`/`Actor`/`Tag` `tasks(filter)`, `searchTasks`, the history and subscription filter, plan.md §6.3 ("Default selection"), and any example that uses `#DONE || !#DONE`.

## Acceptance Criteria
- [x] `tasks` with no filter gives every live task, done included; `!#DONE` gives the open tasks; `#DONE` the done tasks.
- [x] `#DELETED` is still the only way to list tombstones.
- [x] No text in the repo says `#DONE || !#DONE`.

## Tests
- [x] Change the default-selection tests and add one for no filter with a done task; keep the `#DELETED` tests.
- [x] Run the full `swift test`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-08 15:02)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 21 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift:269` `duplication/duplication` — The new test filterWithNoDoneAtomSendsDoneTask repeats the body of the existing test changeWithNoMatchingUpdateIsNotSent (SubscriptionTests.swift:242-253). Both create a fixture, a graph, a subscription, a title change, one expected event, and a close. They differ only by the filter literal and one skipped addTask line. Two copies of the same test flow can drift apart, and one parameterized test would cover both cases. Give the existing test an argument list of filter strings and expected outcomes, and add the '!~actor' case as one more argument. Delete filterWithNoDoneAtomSendsDoneTask. If the addTask line must differ, pass it as a parameter as well.
