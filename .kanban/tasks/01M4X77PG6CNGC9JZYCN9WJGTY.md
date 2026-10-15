---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4zhv1vg1hmgdqgs571b7dn0
  text: |-
    Research done. The line numbers on the card are old; the code moved.
    - `ShortID.resolve` gives `.ambiguous` for a canonical short id with two owners. Plan: add a `.shared([String])` result for that branch; the prefix branch keeps `.ambiguous`.
    - `RefResolver.ulidRef` calls the private `checkShortIDIsUnique` (reads live and tombstoned nodes) before the resolve. The public `checkShortIDIsUnique(_:writtenAs:)` has one caller: `FilterEvaluator.refTest`. Both go.
    - "First" order needs node state (live before tombstone), so the pick is in `RefResolver`, not in `ShortID`.
    - `KanbanError.ambiguity(of:among:)` makes `.sharedShortID` when prefix matches share a short id. P5: replace it with one `ambiguousID` that lists each match with an id and a title.
    - Warnings: `ResponseWarnings` is an actor, and the resolver is synchronous and made at many sites (QueryResolvers `BoardView.resolver`, MutationResolvers `runField`, TaskTransferMutations, Schema). Plan: a task-local, lock-guarded collector (precedent: `PatchValuePolicy.current` is `@TaskLocal`; GraphQL-swift runs fields in task groups, which keep task-locals). `PublicSchema.respond` binds it around the run and moves its warnings into `context.warnings`. The filter path resolves with no collector, because a filter matches all and picks nothing.
    - `isReferenced` in the filter: `.shared` counts as a match (match all).
  timestamp: 2026-10-15T10:31:02.256188+00:00
- actor: claude-code
  id: 01m4zjwgsvfnc44y2ahms0vpds
  text: |-
    Implementation landed.
    - `ShortID.Resolution` has a new case `.shared([String])` for a canonical form with more than one owner. A prefix of more than one ULID still gives `.ambiguous`. `ShortID.ulids(withShortIDOf:among:)` had no caller after the change, so it is removed with its two tests.
    - `RefResolver.ulidRef`: `.shared` picks the first match (live before tombstone, then lowest ULID) and adds a `SHARED_SHORT_ID` warning with all owner ULIDs. `.ambiguous` throws `ambiguousID` with `KanbanError.AmbiguousMatch(id:title:)`: `^short` when no other candidate has that short id, else the full ULID; title of a task, `nil` for a comment. Both `checkShortIDIsUnique` functions and `sharedShortIDOwnerCount` are removed.
    - `KanbanError.sharedShortID` and `KanbanError.ambiguity(of:among:)` are removed. The message is `... matches more than one id: ^a "Title", 01K.... Send one of these ids.`
    - Warning plumbing: new `ResolverWarnings` (in GraphQL/ResponseWarnings.swift), a `Mutex` list bound as `@TaskLocal current`. `PublicSchema.result(of:)` binds it around `execute` and moves its list into `context.warnings`. Messages are deduped, because one run can resolve the same ref more than one time. The filter resolve binds `nil`, so a filter gives no warning.
    - Filter: `refTest` no longer checks; `isReferenced` counts `.shared` as a match. The FilterCompiler functions lost `throws`. `FilterEvaluator.init` keeps its typed `throws` signature (no case throws now), so the TaskFilter/ChangeFilter/ChangeFeed chain stays unchanged. Follow-up task ^e06wvsf removes that dead chain.
    - Doc comments fixed in FilterEvaluator, ChangeFeed, ChangeFilter, ChangeSubscription, TaskSelection, RefResolver, ShortID, Errors.
    - Tests: ShortIDTests, RefResolverTests (order, tombstone, warning, ids and titles), SharedShortIDTests rewritten (mutation, query, tombstone, filter match all with a dependent, two subscription tests), KanbanErrorTests, ErrorCoverageTests, NodeQueryTests. All fixtures are temporary folders or in-memory graphs.
    - swift test: 1415 tests in 110 suites passed; only the accepted "missing creator" warning.
  timestamp: 2026-10-15T10:49:18.907086+00:00
- actor: claude-code
  id: 01m4zjx247h1jvrxc172028vg6
  text: |-
    ### implement — changed
    - evidence: 17 files — S/Identity/ShortID.swift, S/Identity/RefResolver.swift, S/Filter/FilterEvaluator.swift, S/GraphQL/Errors.swift, S/GraphQL/ResponseWarnings.swift, S/GraphQL/Schema.swift, S/GraphQL/TaskSelection.swift, S/Observe/ChangeFeed.swift, S/Observe/ChangeFilter.swift, S/Observe/ChangeSubscription.swift, T/Identity/ShortIDTests.swift, T/Identity/RefResolverTests.swift, T/Identity/SharedShortIDTests.swift, T/GraphQL/KanbanErrorTests.swift, T/GraphQL/ErrorCoverageTests.swift, T/GraphQL/NodeQueryTests.swift; `swift test` 1415 tests in 110 suites passed, only the accepted "missing creator" warning.
    - next: /review. Follow-up task ^e06wvsf (dead typed throws in the filter chain).
  timestamp: 2026-10-15T10:49:36.647507+00:00
- actor: claude-code
  id: 01m4zkghyxajpzc6cbtce0198v
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 16 files
    - test: green — swift test, 1415 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: b11af57
    - review: clean — none
  timestamp: 2026-10-15T11:00:15.453853+00:00
position_column: done
position_ordinal: ff80
title: Resolve a shared short id to the first match, match all in a filter, and list matches for an ambiguous ULID prefix
---
## What
divergence.md Q20 (DECIDED), P5 (DECIDED), G3, F3, and §11 "Q20". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem: a 7-character short id that two nodes share gives `AMBIGUOUS_ID` (S/Identity/ShortID.swift:109-112, S/Identity/RefResolver.swift:411-424). Swift checks tasks and comments, live and tombstoned (S/Identity/RefResolver.swift:399-424), so a tombstone can make the short id of a live task ambiguous. The filter `^id` also gives `AMBIGUOUS_ID` (F3).

Decided behavior:
- A shared 7-character short id resolves to the first match, in mutations and queries. There is no `AMBIGUOUS_ID` for a short id.
- "First" is the same each time: a live node comes before a tombstone, then the lowest ULID.
- In a filter, `^short` matches each task with that short id (match all), and the tasks that depend on one of them (as the `^` filter does now).
- A ULID prefix (not a 7-character short id) that matches more than one ULID still gives `AMBIGUOUS_ID` (P5). The error lists the matching ids and their titles, so that the next call can succeed.
- Keep `AMBIGUOUS_ID` for ULID prefixes and names.

Change the code:
- The canonical short-id branch of S/Identity/ShortID.swift:109-112 (keep the prefix branch).
- S/Identity/RefResolver.swift:127-129,384-424 (`checkShortIDIsUnique`, `ulidRef`).
- S/Filter/FilterEvaluator.swift:322-326 (match all).
- S/GraphQL/Errors.swift:24-26,124,162,264-270 (`sharedShortID`); add the matching ids and titles to the prefix error.
- Fix the doc comments at S/Filter/FilterEvaluator.swift:7-8, S/Observe/ChangeFeed.swift:112, S/Observe/ChangeFilter.swift:63, S/Observe/ChangeSubscription.swift:44, and S/GraphQL/TaskSelection.swift:8,44.
- Fix the doc comments that name `sharedShortID` or `AMBIGUOUS_ID` at S/Identity/RefResolver.swift:21,36,381-382,409 and S/Filter/FilterEvaluator.swift:44,95,121,316,320.

## Acceptance Criteria
- [x] Two tasks with the same short id: `updateTask(id: "<short>")` changes the live one with the lowest ULID.
- [x] A live task and a tombstone with the same short id: the short id resolves to the live task.
- [x] `tasks(filter: "^<short>")` returns both tasks.
- [x] An ambiguous ULID prefix gives `AMBIGUOUS_ID`, and the error lists each matching id and title.

## Tests
- [x] Change T/Identity/SharedShortIDTests.swift, T/Identity/ShortIDTests.swift:134 (`sharedShortIDIsAmbiguous`), and T/GraphQL/KanbanErrorTests.swift:135-156 to the new rules.
- [x] A test for the live-before-tombstone order and the lowest-ULID order.
- [x] A test for `^short` match all in a filter.
- [x] A test that the `AMBIGUOUS_ID` error for a prefix lists the ids and titles.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.