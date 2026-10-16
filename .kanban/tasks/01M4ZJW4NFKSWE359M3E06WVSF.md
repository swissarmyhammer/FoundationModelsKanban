---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m51ar7amshcry4ybgvfn3ghm
  text: |-
    Research done.
    - FilterEvaluator.init calls only FilterCompiler.test(for:). That function and all its helpers declare no throws. The remote assignee code of ^x020t0g uses only `try?` (RefResolver.storedRef, anyLocalRef). Thus the init cannot throw, and the compiler will confirm this when the `throws` is removed.
    - Chain: FilterEvaluator.init -> TaskFilter.init -> ChangeFilter.test(over:) -> applied / updates(of:) / check(against:); TaskFilter.init -> TaskSelection.tasks(in:where:).
    - Callers outside the card list: Undo/History.swift `history` calls `try filter.applied(...)`. The `try` there must go too, or the compiler gives a "no calls to throwing functions" warning.
    - check(against:) has one caller (ChangeSubscription.events). After the change it does nothing, so it has no use: remove it and its call.
    - QueryResolvers.swift: each `try TaskSelection(filtering:).tasks(in:)` still needs `try` for TaskSelection.init, which parses the filter and throws INVALID_FILTER. The doc comments there already name only the parse error. No edit is necessary there.
    - ColumnActorMutations.swift `try column.tasks(filteredBy: nil)` stays: tasks(filteredBy:) still throws through TaskSelection.init.
  timestamp: 2026-10-16T03:05:38.388683+00:00
- actor: claude-code
  id: 01m51b67nw1ncsvvmaan62svqk
  text: |-
    Implementation done.
    - RED: removed the `try` before FilterEvaluator(...) in FilterEvaluatorTests. The build failed with "call can throw but is not marked with 'try'".
    - GREEN: removed `throws(KanbanError)` from FilterEvaluator.init, TaskFilter.init, ChangeFilter.applied / updates(of:) / test(over:), and TaskSelection.tasks(in:where:). Removed ChangeFilter.check(against:) and its one call in ChangeSubscription.events: after the change it did nothing. Removed the do/catch, the error log, and the finish() in ChangeFeed.send. Removed the `try` that had no throwing call in Change.updates and in History.swift `history` (History.swift is not on the card, but the compiler gives a warning there otherwise). Corrected each doc comment that named a filter error that cannot occur.
    - Test helpers: matchingRefs(of: FilterExpr) and matches(of: FilterExpr) are now non-throwing, because their doc comments named an evaluator error. The outer `try` in matchingRefs(of: String) gave a compiler warning, so I removed it.
    - QueryResolvers.swift: no edit. Each `try TaskSelection(filtering:).tasks(in:)` still needs `try` for the parse in TaskSelection.init, and the doc comments already name only INVALID_FILTER.
    - ^x020t0g check: the remote assignee code in FilterEvaluator uses only `try?`, and FilterCompiler declares no throws. The compiler accepted the non-throwing init, which proves that the chain has no throwing call.
    - Build: `swift build --build-tests` gives 0 errors and 0 warnings, other than the accepted Metal and missing-creator warnings.
    - Tests: `swift test --filter FilterEvaluatorTests` 56 passed. Full `swift test`: 1552 tests in 123 suites passed.
  timestamp: 2026-10-16T03:13:17.500827+00:00
- actor: claude-code
  id: 01m51b6eb8a63kwq0133j8g58q
  text: |-
    ### implement — changed
    - evidence: 9 files — Sources/FoundationModelsKanban/Filter/FilterEvaluator.swift, Sources/FoundationModelsKanban/Filter/TaskFilter.swift, Sources/FoundationModelsKanban/Observe/ChangeFilter.swift, Sources/FoundationModelsKanban/Observe/ChangeFeed.swift, Sources/FoundationModelsKanban/Observe/ChangeSubscription.swift, Sources/FoundationModelsKanban/Observe/Change.swift, Sources/FoundationModelsKanban/GraphQL/TaskSelection.swift, Sources/FoundationModelsKanban/Undo/History.swift, Tests/FoundationModelsKanbanTests/Filter/FilterEvaluatorTests.swift. QueryResolvers.swift needs no edit. `swift build --build-tests`: 0 errors, 0 new warnings. `swift test`: 1552 tests in 123 suites passed.
    - next: /review
  timestamp: 2026-10-16T03:13:24.328660+00:00
- actor: claude-code
  id: 01m51bemfy2xyesrp8scd1sx0m
  text: |-
    ### test - green
    - evidence: swift build - complete, only the allowed SwiftPM "missing creator" warning. swift test - 1552 tests in 123 suites passed, 0 failures, 0 skipped. swift test --package-path IntegrationTests with the scratch path in the scratchpad - 3 tests in 3 suites passed, 0 failures, 0 skipped. No compiler warnings other than the allowed one.
    - output files: build.log, test1.log, integration1.log in the scratchpad.
    - next: review
  timestamp: 2026-10-16T03:17:52.766222+00:00
- actor: claude-code
  id: 01m51bfcemj4z2yeeaa47k8rjj
  text: |-
    ### commit - changed
    - evidence: local commit "refactor(filter): remove typed throws that the filter chain cannot give (^e06wvsf)". The sha is in the step report. Files: FilterEvaluator, TaskFilter, ChangeFilter, ChangeFeed, ChangeSubscription, Change, TaskSelection, History, FilterEvaluatorTests, and the changed .kanban/tasks files. Package.resolved and .kanban/mcp.17281.log were not staged.
    - next: review
  timestamp: 2026-10-16T03:18:17.300535+00:00
- actor: claude-code
  id: 01m51bx2v06ky47g15yqrvhawz
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (dac1015). 0 findings (0 confirmed, 0 refuted, 7 validators attempted, 0 failed). 9 files reviewed. 4 .kanban/ files are not reviewed because .reviewignore excludes them. The task has no prior Review Findings section.
    - checkboxes: I examined the 3 boxes against the work and ticked them. (1) In FilterEvaluator, TaskFilter, ChangeFilter, ChangeFeed, ChangeSubscription, Change, and TaskSelection, each `throws(KanbanError)` that stays comes from a call that can fail: FilterExpr parse, ChangeFilter(parsing:), TaskSelection.init, or a board view lookup. `check(against:)` has no use and is removed. No code calls `try` before FilterEvaluator(...), TaskFilter(...), applied, updates(of:), or test(over:). (2, 3) The test step record shows `swift test` with 1552 tests in 123 suites passed, 0 failures, 0 skipped, and only the allowed warnings.
    - next: none. The task is in done.
  timestamp: 2026-10-16T03:25:46.208054+00:00
- actor: claude-code
  id: 01m51bxggjcs81nxg9x4vnnaqs
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 9 files in Filter/, Observe/, GraphQL/TaskSelection.swift, Undo/History.swift, FilterEvaluatorTests.swift
    - test: green — swift test, 1552 passed; IntegrationTests 3 passed
    - commit: dac1015
    - review: clean — 0 findings
  timestamp: 2026-10-16T03:26:00.210231+00:00
position_column: done
position_ordinal: ff8f80
title: Remove the typed throws that the filter evaluator chain can no longer give
---
## What
After ^n9wjgty (divergence.md Q20), `FilterEvaluator.init(evaluating:over:inBoard:)` gives no error: a `^id` value of a shared short id matches each task with it. The init keeps `throws(KanbanError)` only for its callers.

Make the chain honest:
- Sources/FoundationModelsKanban/Filter/FilterEvaluator.swift: remove `throws(KanbanError)` from `init(evaluating:over:inBoard:)`.
- Sources/FoundationModelsKanban/Filter/TaskFilter.swift: `init(filtering:over:inBoard:)` then has no error.
- Sources/FoundationModelsKanban/Observe/ChangeFilter.swift: `applied`, `updates(of:)`, `check(against:)`, `test(over:)` then have no error; remove `check(against:)` if it has no use.
- Sources/FoundationModelsKanban/Observe/ChangeFeed.swift `send(...)`: remove the `do`/`catch` that ends the stream when the filter fails.
- Sources/FoundationModelsKanban/Observe/ChangeSubscription.swift, Observe/Change.swift, GraphQL/TaskSelection.swift, GraphQL/QueryResolvers.swift: remove each `try` that then has no throwing call, and fix the doc comments.
- Tests/FoundationModelsKanbanTests/Filter/FilterEvaluatorTests.swift: remove the `try` before `FilterEvaluator(...)`.

## Acceptance Criteria
- [x] No function of the filter chain declares a typed `throws` that it cannot give.
- [x] `swift test` passes with no new warning.

## Tests
- [x] The existing filter, change feed, and subscription tests pass.