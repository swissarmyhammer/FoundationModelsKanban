---
assignees:
- claude-code
depends_on:
- 01M4G9HNAFASWXCDCPFTDYBDKJ
position_column: todo
position_ordinal: 8d80
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
- [ ] Each rule above has a test, and each test passes.
- [ ] A `BOARD_BUSY` call posts no `.progress` event.

## Tests
- [ ] The tests above in `AgentPlanPostTests.swift`.
- [ ] `swift test --filter AgentPlan` and `swift test` pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.