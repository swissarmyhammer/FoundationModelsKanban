---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4e90g6tdjfj40vc606jtzh2
  text: |-
    ### Decision from the user (2026-10-08)
    "the notion of separating derived and not derived changes seems useless to me". Thus remove `NodeUpdate.source` and the `UpdateSource` enum (PATCH, DERIVED) from the public schema, as well as the `derived` argument. Updates that come from a write to a different node stay in the result, with no flag. If two updates of one node in one Change differ only by source, merge them.
  timestamp: 2026-10-08T17:29:38.266802+00:00
- actor: claude-code
  id: 01m4e91crpdt9g683ngckcvjyq
  text: |-
    ### Decision from the user (2026-10-08, sent by the coordinator)
    "the notion of separating derived and not derived changes seems useless to me". Thus, in addition to the removal of the `derived` argument:
    - Remove `NodeUpdate.source` and the `UpdateSource` enum (PATCH, DERIVED) from the public schema. An update is an update. Keep the computation of the updates that come from a write to a different node (for example, B becomes READY when A becomes done). Those updates stay in the result, with no flag.
    - If two updates of the same node in one Change differ only by their source, merge them into one update with all the changed fields.
    - Remove the internal code that only the source distinction uses. Periphery must stay clean.
    - Change each test that reads `source` or `DERIVED`/`PATCH` so that it checks the fields of the update. Do not change what each test proves.
    - Update plan.md §6.7 and each other section that names PATCH/DERIVED or `source`.
    - The earlier instruction "tests that used `derived` must read `NodeUpdate.source`" is withdrawn.
  timestamp: 2026-10-08T17:30:07.510042+00:00
- actor: claude-code
  id: 01m4e9a710gwydx10qq6jbjdw1
  text: |-
    Research done. Discoveries and design:
    - `$` is not free: `FilterParser.removedSigil` uses it, and the compatibility corpus (`FilterCompatibilityTests.projectExamples`, `FilterParserTests.projectAtomIsInvalid`, `NextTaskTests.projectFilters`) expects `$x` to give INVALID_FILTER. **Choice: the node-type atom is `~type`** (`~task`, `~column`, `~tag`, `~actor`, `~comment`, `~board`, any case). `~` is not used by the parser, the GraphQL forgiving-names rewrite does not read the text of a string argument, and no slug or corpus name holds `~` (slugs are `[a-z0-9-]`). `~` joins the body stop characters.
    - The evaluator atoms are already false on a non-task slot (`hasVirtualTag`, `column(ofTaskAt:)`, `isAssigned`, `isReferenced` each test for a `TaskNode`). Only the top-level `isTask` gate makes the evaluator task-only. Plan: `FilterEvaluator.matches(nodeAt:)` with no gate; `TaskFilter.matches(taskAt:)` keeps the gate for task lists; `TaskFilter.matches(nodeAt:)` for the change feed.
    - `^id` on a non-task node: the value resolves one time with `RefResolver.anyLocalRef(for:)` (the resolve of the old `node` argument); a URL gives its own local ref. A task node keeps the old `^` test (the task, or a task that depends on it). The `^` atom now accepts a URL of each node type.
    - The hidden rule (`DELETED`, `DONE`) would make `^X` give nothing for a done task X, and `~task` would leave out each `completeTask` and `deleteTask` update. So, in the one `names(_:)` path: a `^` atom names each hidden tag, and `~task` names each hidden tag (the same as `%` names `DONE`).
    - `Change.updates` now reads the board of its updates (`KanbanContext.view(ofBoardOfChange:)`), not the current board, because a node test needs the slot in the right graph (CrossRepoEventBoardTests reads `board(id: lib) { history { updates(...) } }`).
    - `ChangeBuilder` never gives two updates of one node in one Change: `derivedUpdate` skips each patched node, and the update of a patched node already holds all its changed fields (stored and derived). So the "merge" decision needs no new code; a test proves one update per node.
    - README has no example of `history` or `changes`; the KanbanTool description has one example query (tasks). I add a filter example of `history` to the tool description, the `watch` help, and the README.
  timestamp: 2026-10-08T17:34:56.544019+00:00
- actor: claude-code
  id: 01m4eanaejv16njj9h2ptrnj7m
  text: |-
    Interpreted rules (implement step):
    - Prefix of the node-type atom: `~` (`~task`, `~column`, `~tag`, `~actor`, `~comment`, `~board`). The card example used `$`, but `$x` must stay the clear error of the removed `$project`, so `$` was not free. `~` is also a stop character of the atom body now. `~` takes no URL.
    - A task-only atom (`#`, `@`, `%`, the virtual tags) is false on a non-task node, so its NOT is true. Thus `#bug` keeps no comment update any more; use `#bug || ~comment`.
    - `^id` matches a node of any type (a ULID, a short id, a slug, or a URL of any node type). On a task, `^id` also matches the tasks that depend on it (the existing meaning), so it is a superset of the old `node` argument.
    - `^` and `~task` name `DONE` and `DELETED` (hidden unless named), so `^X` of a done task and the completion updates under `~task` show. This also changes task lists: `^X` now lists a done or deleted task X.
    - A bare board or comment URL gives `INVALID_FILTER` with "needs `^` before it".
    - "The updates that a write to a different node causes are always in the result": these updates are always made, have no flag, and are kept when their node matches the filter, the same as each other update. With no filter, each update is kept.
    - Merge of updates that differ only by source: ChangeBuilder already gives at most one update for each node (it skips the patched nodes when it makes the other updates), so no merge code was needed. A test checks that the ids of the updates of each Change are unique.
    - `Change.updates(filter:)` tests the nodes in the board of its updates (the current board or a related board).
    - The enum-value name rewrite has no enum argument in the public schema any more. The rewrite code is generic, so it stays; its test now uses a small schema with an enum argument.
    - `ChangeBuilder.derivedChange` is now `changeOfOtherBoard`, and `ChangeRound.derivedChanges` is now `changesOfOtherBoards`, because the source distinction is gone.

    TDD notes: the parser and evaluator tests for `~` and `^` failed on assertions with stubs first. The history, Change.updates and subscription filter tests failed on assertions with a temporary change that kept each update (25 issues), then passed. The tool description test failed on its `contains` assertion before the history example went into the description.
  timestamp: 2026-10-08T17:58:29.074365+00:00
- actor: claude-code
  id: 01m4eancjgtgnng62v6tmn7bwb
  text: |-
    step: implement
    outcome: changed
    evidence: `kanban --schema` shows `history(filter: String, since: ID, first: Int = 20): [Change!]`, `updates(filter: String): [NodeUpdate!]`, `changes(board: String, filter: String): Change!`, and no `source` or `UpdateSource`. Root: `swift build --build-tests` passed (only the accepted mlx "missing creator" warning); `swift test --skip-build` 3 times, each 996 tests in 68 suites passed. Periphery: no unused code. IntegrationTests: `swift build --build-tests && swift test` passed (2 tests in 2 suites). The task stays in doing; nothing is committed.
  timestamp: 2026-10-08T17:58:31.248376+00:00
depends_on:
- 01M4E2MCSNEA5GS581W5QZEQ1H
position_column: doing
position_ordinal: '80'
title: history and changes take only the filter
---
## What
A person decided on 2026-10-08: shortcut verbs stay, but the API must not mix filter arguments with filter expressions (see ^5qzeq1h for the task lists). `Board.history(type, node, actor, filter, derived, since, first)`, `Subscription.changes(board, type, node, actor, filter, derived)` and `Change.updates(type, node)` have the same mix.

Decisions:
- **`actor`:** remove it, and add no author atom. The person said: "i just want to filter on assigned". `@x` keeps one meaning: assigned to x. A client that wants the author reads `Change.actor` (for example, to drop its own changes in a subscription).
- **`node`:** remove it. Use the `^id` atom (a node of any type).
- **`type`:** remove it. Add a new node-type atom, for example `$task`, `$column`, `$tag`, `$actor`, `$comment`, `$board`, with the same atom syntax rules as the other atoms.
- **`derived`:** remove it, for the same reason as `actor`. The updates that a write to a different node causes are always in the result.
- **`source` (2026-10-08, later decision):** "the notion of separating derived and not derived changes seems useless to me". Remove `NodeUpdate.source` and the `UpdateSource` enum from the public schema. An update is an update. Two updates of one node in one Change that differ only by their source become one update with all the changed fields.
- **Keep:** `board` on `changes`, because it names the board to watch and is not a filter. Keep `since` and `first`, because they are paging.

Rules:
- The filter of `history` and `changes` selects the updates whose node matches. A `Change` is in the result when at least one of its updates matches. `Change.updates` takes only `filter`.
- Use the parser, the evaluator and the "hidden unless named" rule from ^d8wwdgy and ^5qzeq1h. Do not add a second filter path.
- Update plan.md §6.5 and §6.7 (and each section that names PATCH/DERIVED or `source`), the tool description and the CLI help.

## Acceptance Criteria
- [x] `kanban --schema` shows `history(filter, since, first)`, `changes(board, filter)` and `updates(filter)`, with no `type`, `node`, `actor` or `derived` argument.
- [x] `^id` and the node-type atom give the same results as the old `node` and `type` arguments, and a test proves each one.
- [x] The updates that a write to a different node causes are in the result. `kanban --schema` shows no `source` field on `NodeUpdate` and no `UpdateSource` enum. One node has at most one update in one Change.

## Tests
- [x] Change the history and subscription tests that use the removed arguments to filter expressions, with the same expected results. Change the tests that use `actor` so that they read `Change.actor`. Change the tests that read `source`, `DERIVED` or `PATCH` so that they check the fields of the update, and prove the same thing.
- [x] Run the full `swift test`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.