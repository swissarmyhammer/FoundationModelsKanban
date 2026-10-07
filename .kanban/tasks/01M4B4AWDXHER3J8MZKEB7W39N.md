---
comments:
- actor: wballard
  id: 01m4bqy862qx9g7k3fte5jcr9s
  text: |-
    Research done.
    - Rust `list tasks` (list.rs): scoping params are ANDed on the AST (not the text), an empty sugar value is an error, and `exclude_done` = explicit value, else `column.is_none()`. Rust `next task` (next.rs): not done, ready, matches the filter; sort by column order, then ordinal; first or null.
    - Compatibility corpus: description.md (`#bug`, `tag: bug`, `#bug && @alice`, `#bug || #regression`, `!#done`), kanban SKILL.md (`#bug`, `@alice`, `#bug && @alice`, `#READY`, `#bug || #feature`, `!#done && #READY`, `column: todo`, and the `$...` examples), finish SKILL.md (`column: review` + scope, `column: todo` + `#READY && (<scope>)`).
    - Plan: a new `GraphQL/TaskSelection.swift` holds the filter + scope atoms + `excludeDone` rule. `Board.tasks` gets `filter`, `tag`, `assignee`, `column`, `excludeDone`; `Board.nextTask(filter:)` is new; `Column`, `Actor`, `Tag` `tasks(filter:)` become resolvers through one shared protocol extension.
    - A scoping value that is a `kanban://` URL goes through the parser (same URL errors as the atom). An empty value gives INVALID_FILTER (the parser `missingBody` error), like the Rust error for an empty sugar param. Other values become a name atom directly, so a value with a space or an operator cannot inject a second atom.
    - GraphQL errors do not have `extensions.code` yet (task ^...5155). Tests read `originalError` of the GraphQL error to check INVALID_FILTER.
  timestamp: 2026-10-07T17:52:49.858848+00:00
- actor: wballard
  id: 01m4brdpa7rcgzxemaxk5g22f7
  text: |-
    Implementation landed (TDD: the new suites failed first with GraphQL validation errors, because `filter`, the scoping arguments, `excludeDone`, and `nextTask` did not exist).
    - New `GraphQL/TaskSelection.swift`: the filter, the scope atoms (built on the AST, not the text), and the `excludeDone` rule. `init(for: TasksArguments)` for `Board.tasks`; `init(filtering:excludingDone:)` for `nextTask` and the node `tasks` fields.
    - `Board.tasks` gets `filter`, `column`, `tag`, `assignee`, `excludeDone`. `Board.nextTask(filter:)` is new (not done, ready, matches, board order, first or null).
    - New protocol `TaskHolderObject` (QueryResolvers.swift): one `tasks(context:arguments:)` resolver in a protocol extension for `Column`, `Actor`, and `Tag`; each type gives only `isHolder(of:)`. `LabelObject` now refines it.
    - Divergence from the plan.md §4.1 sketch (no plan text changed): `Board.tasks` is now `TaskConnection` (nullable) and the node `tasks(filter:)` fields are `[Task!]` (nullable), so that a filter that does not parse gives `null` for that field only and the board keeps its other fields (the launcher rule: a field that can fail returns an optional). The plan sketch shows `TaskConnection!` and `[Task!]!`; plan.md §4.1 needs an update to match.
    - Behavior change of existing queries: `Board.tasks` with no arguments now leaves out the done tasks (the Rust `excludeDone` default). Existing tests that listed a done task now pass `excludeDone: false`: QueryResolverTests (paging, order) and KanbanGraphTests (the fixture has one column, which is the terminal column). `unknownCursorGivesAnError` now expects `board.tasks: null`.
    - GraphQL errors do not carry `extensions.code` yet (^...5155), so the tests read `GraphQLError.originalError as? KanbanError` to check INVALID_FILTER.
    - A scoping value with a space or an operator is one name atom (no injection); an empty value and a wrong-type URL give INVALID_FILTER.
  timestamp: 2026-10-07T18:01:15.847638+00:00
- actor: wballard
  id: 01m4brdsnbzgpqqc5esbay7tat
  text: |-
    ### implement — changed
    - evidence: `swift test` 559 tests in 34 suites passed; `swift build --build-tests` 0 warnings; `swift test --filter FilterCompatibilityTests` 22 tests passed; `swift test --filter NextTaskTests` 12 tests passed; periphery 3.8.0 (`-- --build-system native --build-tests`) no unused code; swiftlint no_magic_numbers/line_length/force rules 0 violations. Files: Sources/FoundationModelsKanban/GraphQL/TaskSelection.swift (new), Sources/FoundationModelsKanban/GraphQL/QueryResolvers.swift, Sources/FoundationModelsKanban/GraphQL/Schema.swift, Tests/FoundationModelsKanbanTests/Filter/TaskQueryFixture.swift (new), Tests/FoundationModelsKanbanTests/Filter/FilterCompatibilityTests.swift (new), Tests/FoundationModelsKanbanTests/Filter/NextTaskTests.swift (new), Tests/FoundationModelsKanbanTests/GraphQL/QueryResolverTests.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift
    - next: /review
  timestamp: 2026-10-07T18:01:19.275480+00:00
- actor: wballard
  id: 01m4brkwtmd6bdj0tjz4msdak1
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (07214fa). 0 findings, 0 confirmed, 0 refuted. 7 of 7 validators completed, 0 failed. 8 files reviewed. 4 .kanban files not reviewed (.reviewignore).
    - next: none. The task is in done.
  timestamp: 2026-10-07T18:04:39.124550+00:00
- actor: wballard
  id: 01m4brm3d7h6w62gdkezznyszb
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 8 files (GraphQL/TaskSelection.swift, QueryResolvers.swift, Schema.swift; TaskQueryFixture, FilterCompatibilityTests, NextTaskTests, QueryResolverTests, KanbanGraphTests)
    - test: green — swift test, 559 passed, 0 warnings
    - commit: 07214fa
    - review: clean — 0 findings
    - note for a person: `Board.tasks` and the node `tasks(filter:)` fields are nullable, against the plan.md §4.1 sketch (non-null), because GraphQLSwift drops all `data` when a non-null field throws. plan.md §4.1 needs an update to match.
  timestamp: 2026-10-07T18:04:45.863771+00:00
depends_on:
- 01M4B3Z67TC96REJGDHD2DFH0R
- 01M4B3YQSXZCGCB08FVP8QCSF3
position_column: done
position_ordinal: '9980'
title: 'Filter: connect to queries, nextTask, compatibility corpus'
---
## What
Use the filter evaluator in the queries. The basis is plan.md §6.3 (Scoping arguments, Where `filter` applies) and §6 (`nextTask`).
- Scoping arguments of `Board.tasks`: `tag` = `#x`, `assignee` = `@x`, `column` = `%x`, ANDed with `filter`.
- `excludeDone`: with no value, `true`; `false` when a column is named by `column`, a `%` atom, or a column URL.
- Connect `filter` to `Board.tasks`, `Board.nextTask` (not done, ready, matches; sort by column order then ordinal; return the first or `null`), and the `tasks` fields of `Column`, `Actor`, `Tag`.
- Port `../swissarmyhammer/crates/swissarmyhammer-kanban/src/task/next.rs` behavior tests.

## Acceptance Criteria
- [x] Each filter example in `../swissarmyhammer/crates/swissarmyhammer-tools/src/mcp/tools/kanban/description.md`, `../skills/skills/kanban/SKILL.md`, and `../skills/skills/finish/SKILL.md` gives the same tasks as in Rust, except `$project`, which gives `INVALID_FILTER`.
- [x] `%done` lists done tasks; `%review || (%todo && #READY)` gives the tasks of both parts; a `tag`, `assignee`, or `column` argument gives the same result as its atom.
- [x] The ported `next.rs` tests pass.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Filter/FilterCompatibilityTests.swift` and `NextTaskTests.swift`.
- [x] Run `swift test --filter FilterCompatibilityTests` and `--filter NextTaskTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.