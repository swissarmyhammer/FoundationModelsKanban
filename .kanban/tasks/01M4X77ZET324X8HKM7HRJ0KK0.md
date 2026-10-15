---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4zwmqz56g9x1bmh4xt51wyv
  text: |-
    Research done.
    - RefResolver.candidateRef sends .task and .comment to ulidRef. The plan: add a title-slug step for .task after ulidRef gives nil. A Lookup flag turns the step off in the anyLocalRef type loop, and anyLocalRef tries the title slug after all slug types (E4), so a column slug wins.
    - The first match uses the existing precedes order (live before tombstone, then lowest ULID). A shared title slug gives a warning, the same as SHARED_SHORT_ID.
    - Slug.normalizedText (Tags/TagSlug.swift) drops a leading `^`, so `^fix-login-bug` and `Fix login bug` both give `fix-login-bug`.
    - Rust has_ref (task_helpers.rs) ORs the title slug with the ULID match: the task itself or a task whose depends_on has the slug task. Swift matches each task with that slug (C3).
    - FilterParser: `^` is a body stop character, so `^^x` fails with missingBody. The fix is to drop the extra `^` after the `^` sigil.
  timestamp: 2026-10-15T13:39:49.861265+00:00
- actor: claude-code
  id: 01m4zxedp2ghwxahzb1xe3x018
  text: |-
    Implementation landed (TDD: red first for each part, then green).
    - Filter parser: after the `^` sigil, each next `^` is part of the sigil, so `^^short` and `^^^short` give `^short`. `^^` with no body gives the missing-body error over the two sigils.
    - Filter evaluator: `^value` also matches each task whose title slug is the slug of the value, and each task that depends on one of them (match all, C3). The ULID match stays, and the two are ORed, the same as Rust `has_ref`.
    - RefResolver: new `Graph.taskSlots(withTitleSlugOf:)`. For `.task` lookups, the title slug is the last step after ulidRef. `node(id:)` (anyLocalRef) turns the step off in the type loop and tries the title slug after all other slugs (E4), so a column slug wins. A shared title slug uses the Q20 first-match order and gives a new `SHARED_TITLE_SLUG` warning. `firstMatch` now takes a `SharedForm` (shortID or titleSlug); the SHARED_SHORT_ID message text did not change.
    - Descriptions: KanbanTool description, the filter grammar text, and the AddTaskInput/UpdateTaskInput dependsOn texts name the title slug and `^^short`. README filter section too.
    - Discovery: dependsOn and other task-ref fields now also take a title slug, because they all go through storedRef(.task).
  timestamp: 2026-10-15T13:53:51.298008+00:00
- actor: claude-code
  id: 01m4zxeg2rgemh58hrjdf1pb4d
  text: |-
    ### implement — changed
    - evidence: `swift test` 1459 tests in 112 suites passed; only the accepted mlx "missing creator" warning. Files: Sources/FoundationModelsKanban/Filter/FilterParser.swift, Filter/FilterEvaluator.swift, Identity/RefResolver.swift, GraphQL/SchemaDescription.swift, Tool/KanbanTool.swift, README.md, Tests/.../Identity/TitleSlugRefTests.swift (new), Filter/FilterParserTests.swift, GraphQL/SchemaDescriptionTests.swift, Tool/KanbanToolTests.swift
    - next: /review
  timestamp: 2026-10-15T13:53:53.752311+00:00
- actor: claude-code
  id: 01m4zy3vsqj9cc05hvywsn4fh6
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 10 files
    - test: green — swift test, 1459 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: 2f3341a
    - review: findings — Tests/FoundationModelsKanbanTests/GraphQL/SchemaDescriptionTests.swift:207, Tests/FoundationModelsKanbanTests/Identity/TitleSlugRefTests.swift:79
  timestamp: 2026-10-15T14:05:33.879727+00:00
- actor: claude-code
  id: 01m4zyfemj0hwhtj8a1fgf0xc1
  text: |-
    Review findings fixed (both reuse/reuse).
    - SchemaDescriptionTests: new helper `places(ofInputsNamed:notNaming:)` takes the expected texts. It does the `count > 1` check and gives the places that miss a text. The same cause was also in `dependsOnInputsNameTheTitleSlug` and `boardArgumentsHaveDescriptions`, so all four tests now call the helper.
    - Shared helper: `KanbanGraphTests.response(to:inRepoAt:)` runs one document on a new engine of the board of a repo. The instance `response(to:)` in SharedShortIDTests and in TitleSlugRefTests is removed. Both suites call the shared helper.
    - TitleSlugRefTests: two more copies in the same file are removed. `countResponse(filter:)` replaces the two one-task filter tests' query-and-run pair, and `taskResponse(naming:)` replaces the two task-field tests' pair.
    - Search of the other test files: no other copy of the helper. BoardMutationTests, AddUpdateTaskTests, and CommitTests have inline `execute(_, on: makeGraph(at:))` calls in tests that existed before. They are not helper copies, and this change does not touch them.
  timestamp: 2026-10-15T14:11:53.618209+00:00
- actor: claude-code
  id: 01m4zyfgt85zd15dyqdkfc3f9t
  text: |-
    ### implement — changed
    - evidence: 4 files — Tests/FoundationModelsKanbanTests/GraphQL/SchemaDescriptionTests.swift, Tests/FoundationModelsKanbanTests/Identity/TitleSlugRefTests.swift, Tests/FoundationModelsKanbanTests/Identity/SharedShortIDTests.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift. `swift test`: 1459 tests in 112 suites passed. The only warning is the accepted SwiftPM "missing creator" warning. Both review findings are checked.
    - next: /review
  timestamp: 2026-10-15T14:11:55.848618+00:00
- actor: claude-code
  id: 01m4zywzvxtv4k22hc3gkxgvzt
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 4 test files (2 findings fixed)
    - test: green — swift test, 1459 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: a396ec9
    - review: findings — Tests/FoundationModelsKanbanTests/Identity/SharedShortIDTests.swift:119, Tests/FoundationModelsKanbanTests/Identity/TitleSlugRefTests.swift:169
  timestamp: 2026-10-15T14:19:17.245557+00:00
- actor: claude-code
  id: 01m4zz87qhps8awd4xv52rjxct
  text: |-
    Review findings fixed (both duplication/duplication, one cause).
    - New helper `KanbanGraphTests.mutationResponse(of:inRepoAt:)`, next to `response(to:inRepoAt:)`. It makes a mutation document from one field with `AddUpdateTaskTests.mutation(of:)` and runs it on a new engine of the board of a repo.
    - SharedShortIDTests.mutationWithSharedShortIDChangesLowestULID and TitleSlugRefTests.mutationWithTitleSlugChangesFirstMatch call the helper. Both copies of the two lines are removed.
    - Search of all test files: these two were the only places that build a mutation from a field and run it on a new engine through `KanbanGraphTests.response(to:inRepoAt:)`. No call puts `mutation(of:)` and `makeGraph(at:)` together on one line or on two lines. The other `mutation(of:)` + `execute(_, on: graph)` pairs run on a graph that the test already holds and uses again (BoardWatcherTests, RepoBoardTests, AddUpdateTaskTests, VirtualTagNameTests, TaskSearchTests, ListInStringTests). They do not make a new engine, so they are a different pattern, and this change does not touch them.
    - TDD: RED was the build error "type 'KanbanGraphTests' has no member 'mutationResponse'". GREEN: the two tests pass.
  timestamp: 2026-10-15T14:25:25.745908+00:00
- actor: claude-code
  id: 01m4zz89z4ywv0k73sz3j663s3
  text: |-
    ### implement — changed
    - evidence: 3 files — Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift, Tests/FoundationModelsKanbanTests/Identity/SharedShortIDTests.swift, Tests/FoundationModelsKanbanTests/Identity/TitleSlugRefTests.swift. `swift test`: 1459 tests in 112 suites passed. The only warning is the accepted SwiftPM "missing creator" warning. Both 09:15 review findings are checked.
    - next: /review
  timestamp: 2026-10-15T14:25:28.036013+00:00
- actor: claude-code
  id: 01m4zzq4kxgrkn1197bx0tj5h0
  text: |-
    ### finish iteration 3 — clean
    - implement: changed — 3 test files (2 findings fixed with one shared helper)
    - test: green — swift test, 1459 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: d5c5a50
    - review: clean — none
  timestamp: 2026-10-15T14:33:34.077728+00:00
depends_on:
- 01M4X77PG6CNGC9JZYCN9WJGTY
position_column: done
position_ordinal: ff8380
title: Accept a title slug and ^^short in the filter, and a title slug as a task ref
---
## What
divergence.md Q25 (DECIDED: support both), C3 (DECIDED), E4 (DECIDED), F1, F2, and §11 "Q25". K4 was not cut. This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problems: the `^` filter does not match by the slug of the task title (F1); Rust matches `^fix-login-bug`. The design allows `^^short` in a filter, but the grammar refuses it (F2).

Decided behavior:
- Filter:
  - Accept `^<title-slug>`. In a filter, it matches all tasks whose title slug is that value (match all), plus the tasks that depend on them, as `^` does now. (Rust keeps only the last task; Swift matches all.)
  - Accept `^^short` (allow `^` after `^`).
  - Code: S/Filter/FilterParser.swift:35-37,221-223 (allow `^` after `^`) and S/Filter/FilterEvaluator.swift:397-408 (`isReferenced`: match the slug of the task title).
- Task ref in a mutation or a query for one task (C3): accept a title slug. It uses the first match (live before tombstone, then lowest ULID), the same rule as a shared short id (Q20). Code: S/Identity/RefResolver.swift (a new title-slug step).
- Resolve order (E4):
  - In a field that takes only tasks: try the ULID, then the short id, then the title slug.
  - In a field that takes many types (for example `node(id:)`): a title slug comes last, after all other slugs. Thus a title slug that is the same as a column slug gives the column.

## Acceptance Criteria
- [x] `tasks(filter: "^fix-login-bug")` returns each task with the title "Fix login bug" (and their dependents).
- [x] `tasks(filter: "^^<short>")` parses and works.
- [x] `updateTask(input: {id: "fix-login-bug", ...})` changes the first matching task.
- [x] `node(id: "todo")` with a column `todo` and a task titled "Todo" gives the column.
- [x] A ULID or a short id still wins over a title slug in a task field.

## Tests
- [x] Both filter forms.
- [x] A shared title slug in a filter (match all).
- [x] A title-slug ref in a mutation (first match).
- [x] A title slug in a task field; a title slug that is the same as a column slug in `node(id:)` gives the column.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-15 08:58)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 9 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/GraphQL/SchemaDescriptionTests.swift:207` `reuse/reuse` — `filterArgumentsNameTheRefForms` is a parallel copy of `filterArgumentsNameTheSigils` (lines 196-205). The two tests differ only in the list of strings they check, so the shared check should be a helper that takes the expected strings. Extract a helper such as `assertInputs(named:, description contains each of:)` and call it from both tests with `filterSigils` and `filterRefForms`.
- [x] `Tests/FoundationModelsKanbanTests/Identity/TitleSlugRefTests.swift:79` `reuse/reuse` — The new `response(to:)` helper reimplements the same helper that already exists in SharedShortIDTests. Both run a document on a new engine of the same board with the same body, so the test suite keeps two copies of one behavior that can drift apart. Move the helper to `KanbanGraphTests` (or a shared test extension) as a single `response(to:directory:)`, and call it from both suites. Or have `TitleSlugRefTests` reuse `SharedShortIDTests.response` directly.

## Review Findings (2026-10-15 09:15)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Tests/FoundationModelsKanbanTests/Identity/SharedShortIDTests.swift:119` `duplication/duplication` — The two lines that build a mutation from a field and run it on a new engine are copied verbatim into TitleSlugRefTests. The copies can drift apart, and a fix to one would not reach the other. Add a helper next to KanbanGraphTests.response, for example `static func mutationResponse(of field: String, inRepoAt root: URL) async throws -> String`, that wraps AddUpdateTaskTests.mutation(of:) and response(to:inRepoAt:). Call it from both tests and delete both copies of the two lines.
- [x] `Tests/FoundationModelsKanbanTests/Identity/TitleSlugRefTests.swift:169` `duplication/duplication` — The two lines that build a mutation from a field and run it on a new engine are copied verbatim from SharedShortIDTests. The copies can drift apart, and a fix to one would not reach the other. Replace both copies with one shared helper on KanbanGraphTests, for example `mutationResponse(of:inRepoAt:)`, and call it from this test and from SharedShortIDTests.mutationWithSharedShortIDChangesLowestULID.
