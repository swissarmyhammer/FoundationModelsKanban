---
comments:
- actor: wballard
  id: 01m4bb80dzm1x95qfb3a5sbnzk
  text: 'Note from ^grhp82e (filter parser): `FilterExpr(parsing:)` already gives `INVALID_FILTER` for a URL of the wrong type for its sigil (the message gives the correct sigil and the full URL as the example), and for a board URL or a comment URL, bare or after a sigil. Thus each `.atom(kind, .uri(uri))` that the evaluator gets has `uri.ref.nodeType == kind.nodeType`. The evaluator still must resolve the key of the URL (current board, or a different board). The AST is in `Sources/FoundationModelsKanban/Filter/FilterExpr.swift`.'
  timestamp: 2026-10-07T14:10:58.111262+00:00
- actor: wballard
  id: 01m4bq5zyz017dravkaymb1nsp
  text: |-
    Research done.
    - Rust sources: `swissarmyhammer-filter-expr/src/lib.rs` (eval_* tests) and `eval.rs`; the kanban adapter is `TaskFilterAdapter` in `swissarmyhammer-kanban/src/task_helpers.rs`; the kanban filter scenarios are `tests/filter_integration.rs` (s01-s17) and `src/task/list.rs` (`@alice-smith`, slug of the actor name).
    - Rust `^ref` resolves the short form among the candidates of ONE task: its own id and its `depends_on` ids (`short_ref_matches` -> `resolve_short_ref`). An ambiguous prefix among those candidates does not match. The Swift port keeps this rule with `ShortID.resolve(_:among:)`, so a prefix that is ambiguous on the board can still match a task.
    - Rust `^ref` also matched the slug of a task title. plan.md §6.3 does not list that form, so the port does not add it.
    - Plan: `Filter/FilterEvaluator.swift` compiles the AST one time into a task predicate. Tags use `RefResolver` (rename redirect) and `Graph.tagSlots(of:)`, virtual tags use `Readiness.virtualTags(ofTaskAt:)`, columns use `Readiness.column(ofTaskAt:)` (a task with no live column shows in the first column), dependencies use the live dependencies of `Readiness` (edges and markers). `Readiness` gets one accessor for the live dependencies of a task.
    - The test fixture `ReadinessFixture` gets tags, assignees, and names for actors and columns.
  timestamp: 2026-10-07T17:39:35.007694+00:00
- actor: wballard
  id: 01m4bqgjkv3vxc7g3ejg6h0bjh
  text: |-
    Implementation landed (TDD: the new suite failed to compile first, because `FilterEvaluator` and `namesColumn` did not exist).
    - `FilterEvaluator(evaluating:over:inBoard:)` compiles the AST one time into a slot predicate; `matches(taskAt:)` tests one task. A slot that holds no task never matches. `FilterExpr.namesColumn` is the helper for `excludeDone`.
    - `Readiness.dependencies(ofTaskAt:)` is new (the live dependencies, edges and markers). `blockers` and the cycle walk now use it.
    - Test fixture `ReadinessFixture` got `addTag`, task `taggedWith:`/`assignedTo:`, and `named:` for actors and columns. Existing callers are unchanged.
    - Discoveries: a virtual tag and a real tag share one `#` atom, so `#READY` also matches a real tag `ready` (Rust behavior, tested). The parser already gives INVALID_FILTER for a wrong-type URL; the evaluator also gives "no match" for a hand-built AST with a wrong-type URL (tested). A `^` short form does not match a dependency on a task of a different board; only the full URL does.
    - The connection to the queries (`tasks(filter:)`, `nextTask`, scoping arguments) stays in ^wmczz5z... see the task "Filter: connect to queries, nextTask, compatibility corpus".
  timestamp: 2026-10-07T17:45:21.787516+00:00
- actor: wballard
  id: 01m4bqgmxakdm2yr43tqyrb681
  text: |-
    ### implement — changed
    - evidence: `swift test` 525 tests in 32 suites passed, 0 warnings; `swift test --filter FilterEvaluatorTests` 44 tests passed; periphery (`-- --build-system native`) no unused code; swiftlint no_magic_numbers/force_unwrapping/line_length 0 violations. Files: Sources/FoundationModelsKanban/Filter/FilterEvaluator.swift (new), Sources/FoundationModelsKanban/Derived/Readiness.swift, Tests/FoundationModelsKanbanTests/Filter/FilterEvaluatorTests.swift (new), Tests/FoundationModelsKanbanTests/Derived/ReadinessFixture.swift
    - next: /review
  timestamp: 2026-10-07T17:45:24.138809+00:00
- actor: wballard
  id: 01m4bqgrzaks8wnfqnz8jb6y71
  text: 'Correction to the comment above: the task that connects the evaluator to the queries is ^eb7w39n ("Filter: connect to queries, nextTask, compatibility corpus"). The reference `^wmczz5z` in that comment is wrong.'
  timestamp: 2026-10-07T17:45:28.298340+00:00
- actor: wballard
  id: 01m4bqqb5f3t0f3tk8d5tg62xw
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (f2a58c5). 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. The ignore rule (.reviewignore) excluded 4 .kanban/ files.
    - next: none. The task moved to done.
  timestamp: 2026-10-07T17:49:03.535649+00:00
- actor: wballard
  id: 01m4bqqgm0nvdrv2g4zpjwwsc7
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 4 files (Filter/FilterEvaluator.swift, Derived/Readiness.swift, FilterEvaluatorTests.swift, ReadinessFixture.swift)
    - test: green — swift test, 525 passed, 0 warnings
    - commit: f2a58c5
    - review: clean — 0 findings
  timestamp: 2026-10-07T17:49:09.120943+00:00
depends_on:
- 01M4B3WBH8MREZBK6W0GRHP82E
- 01M4B3Y4M87387J50EQCD36VB0
- 01M4B3YC73VSKE9VEP29E3CZNQ
position_column: done
position_ordinal: '9880'
title: Filter evaluator
---
## What
Evaluate a parsed filter against one task. The basis is plan.md §6.3. The connection to the queries is in a separate task.
- `Sources/FoundationModelsKanban/Filter/FilterEvaluator.swift`: `#tag` (edges, markers, rename redirect, virtual tags), `@user` (actor slug or slug of the actor name), `^id` (the task itself or a `dependsOn` target, from edges and markers, by any short form or full URI), `%column` (column slug or slug of the column name). All matches ignore case.
- URL atoms resolve by key: the current key resolves in this board; a tag, actor, or column URL of a different board matches nothing; a `^` URL of a different board matches tasks that depend on that task. A URL of the wrong type, a board URL, or a comment URL gives `INVALID_FILTER`.
- A value that names nothing matches nothing (no error).
- A helper that reports whether a filter names a column (a `%` atom or a column URL); the `excludeDone` rule uses it.

## Acceptance Criteria
- [x] The evaluator tests of `../swissarmyhammer/crates/swissarmyhammer-filter-expr/src/lib.rs` pass (with `$project` removed).
- [x] Each URL form matches the same tasks as its short form.
- [x] A URL of the wrong type gives `INVALID_FILTER` with the correct form in the message.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Filter/FilterEvaluatorTests.swift`, against fixture graphs.
- [x] Run `swift test --filter FilterEvaluatorTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.