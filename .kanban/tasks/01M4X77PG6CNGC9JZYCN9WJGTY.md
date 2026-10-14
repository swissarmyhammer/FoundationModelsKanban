---
assignees:
- claude-code
position_column: todo
position_ordinal: a480
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
- [ ] Two tasks with the same short id: `updateTask(id: "<short>")` changes the live one with the lowest ULID.
- [ ] A live task and a tombstone with the same short id: the short id resolves to the live task.
- [ ] `tasks(filter: "^<short>")` returns both tasks.
- [ ] An ambiguous ULID prefix gives `AMBIGUOUS_ID`, and the error lists each matching id and title.

## Tests
- [ ] Change T/Identity/SharedShortIDTests.swift, T/Identity/ShortIDTests.swift:134 (`sharedShortIDIsAmbiguous`), and T/GraphQL/KanbanErrorTests.swift:135-156 to the new rules.
- [ ] A test for the live-before-tombstone order and the lowest-ULID order.
- [ ] A test for `^short` match all in a filter.
- [ ] A test that the `AMBIGUOUS_ID` error for a prefix lists the ids and titles.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.