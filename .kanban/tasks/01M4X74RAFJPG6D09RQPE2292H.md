---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4yysngtafbp552zvyncz4vh
  text: |-
    Research done.
    - NameMatcher step 4 (`wordOrderAndSynonyms`) reads `NameQuery.mutationKeys`, which is empty for each position other than `.topLevelMutation`. The root query uses `.anyOther` in `RewriteWalk.visit(_ operation:)`, in `visitSelections` (fragments on Query), and in `moveIntoBoard` (both the root match and the Board match).
    - Root Query fields: `board`, `node`, `nodes`, `boards`. `task`, `tasks`, `columns`, `searchTasks`, `nextTask`, `history`, `summary` are on `Board`, and `moveIntoBoard` moves them. So `getTask` must miss at the root and match `task` on Board.
    - Plan: add `NamePosition.topLevelQuery`. Step 4 gets ordered key tiers, so that `getTask` gives `task` and not a tie of `task` and `tasks`: the get verbs try the singular forms, then the written noun, then the plural forms; the list verbs try plural, written, singular. `search` and `next` take the default noun `task` and keep their verb word (`searchTasks`, `nextTask`). A query verb after a query verb (`getNext`) reads the inner verb.
    - Q11: the never list has one entry (`create` -> `init`). It goes away. A noun table maps `create` and `new` to `init` for the noun `board` (and its number forms). Other nouns keep `create`/`new` -> `add`.
    - Existing tests that assert the old never list (`NameMatcherTests.createBoardDoesNotGiveInitBoard`, `neverListBlocksStepMatch`, `neverListKeepsMappingWithBothWords`, `NameRewriteTests.createBoardDoesNotMapToInitBoard`) state the reversed rule. They change to the Q11 rule.
    - Conflict found: the acceptance item `{ listTasks { nodes { id } } }` needs a `nodes` field on `TaskConnection`. plan.md §4.1 says `TaskConnection` has `edges`, `pageInfo`, `totalCount`, and no `nodes`. No alias can make `nodes { id }` into `edges { node { id } }`.
  timestamp: 2026-10-15T04:58:13.914584+00:00
- actor: claude-code
  id: 01m4yz88pvsz6fdq4xpp8x0khk
  text: |-
    Implementation landed (TDD: RED seen for each new matcher and rewrite test, then GREEN).
    - NameMatcher.swift: new `NamePosition.topLevelQuery`. Step 4 now tries key tiers in order (`MatchStep.matches(among:for:)` with one pass for each tier), so `getTask` gives `task` and not a tie of `task` and `tasks`. New `QueryVerb` table (`get/show/read/fetch` singular, `list/find/query` plural, `search` → `searchTasks`, `next` → `nextTask`, a verb after a verb such as `getNext` reads the inner verb). A noun with no field of the asked number falls back to the other number (`showColumn` → `columns`). The never list is gone; `nounVerbSynonyms` maps `create` and `new` to `init` for the noun `board` (also `boards`, `boardCreate`). Other nouns keep `create`/`new` → `add`.
    - NameRewrite.swift: a `query` operation, and each selection set on the query type (inline fragment, fragment definition), uses `.topLevelQuery`; `moveIntoBoard` uses it for the root match and for the Board match.
    - Tests: NameMatcherTests (each verb group, root fields, no-noun and root-only negatives, board verbs, other nouns); NameRewriteTests (text rewrites, fragment, and runs through the schema for getTask, listTasks, getBoard, search, next; createBoard and newBoard through execute on a TemporaryDirectory repo). The three never-list tests and the old "createBoard does not map" test now state the Q11 rule.
    - Full `swift test`: 1347 tests in 106 suites pass. Only the accepted SwiftPM "missing creator" warning.
    - BLOCKER (true conflict, a person must decide): acceptance item `{ listTasks { nodes { id } } }`. `listTasks` maps to `tasks`, but `TaskConnection` has no `nodes` field, and plan.md §4.1 says `TaskConnection` has `edges`, `pageInfo`, `totalCount`. No alias or rewrite can make `nodes { id }` into `edges { node { id } }` and keep the response shape. Options: (a) add `TaskConnection.nodes: [Task!]!` (a divergence from plan.md §4.1, needs a divergence.md entry), or (b) change the item to `{ listTasks { edges { node { id } } } }`, which passes now.

    ### implement — stuck
    - evidence: 4 files — Sources/FoundationModelsKanban/GraphQL/NameMatcher.swift, Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift, Tests/FoundationModelsKanbanTests/GraphQL/NameMatcherTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift; swift test 1347 passed, 0 failed. Open gap: `{ listTasks { nodes { id } } }` needs `TaskConnection.nodes`, which plan.md §4.1 does not have.
    - next: a person decides option (a) or (b) for the `nodes` item; then /review.
  timestamp: 2026-10-15T05:06:12.316+00:00
- actor: claude-code
  id: 01m4yz9jsn8xr05k3kcand18f8
  text: 'Picked up again. Decision from the orchestrator (from the user rules): divergence.md is the authority, not plan.md. By divergence.md §4 ("be VERY FORGIVING"), add a `nodes` field (a plain list of the node type) to `TaskConnection` and to each other connection type. Record it in divergence.md §4. Do not edit plan.md.'
  timestamp: 2026-10-15T05:06:55.413383+00:00
- actor: claude-code
  id: 01m4yzm4bbwfttp81hh69p74a7
  text: |-
    Blocker resolved (the orchestrator decided by divergence.md §4 "be VERY FORGIVING").
    - `TaskConnection` is the only connection type in the public schema. It now has `nodes: [Task!]!` (a computed `nodes` on the struct: `edges.map(\.node)`), with the description `SchemaDescription.connectionNodes`.
    - TDD: RED seen for 3 new tests (no `nodes` field on `TaskConnection`), then GREEN.
      - `SchemaDescriptionTests.connectionTypesHaveDescribedNodes`: each object type with an `edges` field has a described `nodes` list of the node type of its edges. This also covers a new connection type in the future.
      - `QueryResolverTests.nodesAreTheNodeOfEachEdge`: `nodes` equals the `node` of each edge, in the same order.
      - `NameRewriteTests.listTasksNodesGivesEachTask`: `{ listTasks { nodes { id } } }` gives the same data as `{ board { listTasks: tasks { nodes { id } } } }`, with each task.
    - divergence.md §4: one bullet that records `nodes` on connection types. plan.md is not changed.
    - Full `swift test`: 1350 tests in 106 suites pass. Only the accepted SwiftPM "missing creator" warning.

    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsKanban/GraphQL/Schema.swift, Sources/FoundationModelsKanban/GraphQL/SchemaDescription.swift, Tests/FoundationModelsKanbanTests/GraphQL/SchemaDescriptionTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/QueryResolverTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift, divergence.md; this pass and the earlier pass also changed NameMatcher.swift, NameRewrite.swift, NameMatcherTests.swift. swift test: 1350 passed, 0 failed.
    - next: /review
  timestamp: 2026-10-15T05:12:41.067923+00:00
- actor: claude-code
  id: 01m4z00t213nqz7er37wj8398n
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 10 files (root verbs, createBoard/newBoard → initBoard, TaskConnection.nodes; the nodes field was an orchestrator decision by the very-forgiving principle, recorded in divergence.md §4)
    - test: green — swift test, 1350 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: 4881827
    - review: findings — Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift:335
  timestamp: 2026-10-15T05:19:36.513046+00:00
- actor: claude-code
  id: 01m4z0a5qsg0jbzj2j5fzp84pf
  text: |-
    Picked up for the open finding at NameRewriteTests.swift:335 (completeness/invariant-propagation).
    - Change: `fragmentQueryVerbMovesIntoBoard` is now a parameterized test with two cases, the same shape as `fragmentRootFieldMovesIntoBoard`. Case 1 (new): `{ ... on Query { listTasks { totalCount } } }` must rewrite to `{ ... on Query { _kanbanRoot0: board { listTasks: tasks { totalCount } } } }` with the rewrite record `listTasks -> board.tasks`, path `["listTasks"]`. Case 2 (kept): the fragment definition form, path `["Q", "listTasks"]`. No full matrix.
    - Result: the inline-fragment case passed on its first run. RewriteWalk already uses `.topLevelQuery` for an inline fragment on the query type, so no code change was necessary. There was no RED, because the behavior exists; the test is coverage for the sibling form.
    - I made the cases one parameterized test and not a second test function, so that the duplication rule does not see a copied test body.
  timestamp: 2026-10-15T05:24:43.385490+00:00
- actor: claude-code
  id: 01m4z0aaqpn0c93p6wmmky45z3
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift (fragmentQueryVerbMovesIntoBoard now covers the inline-fragment form and the fragment-definition form). `swift test --filter NameRewriteTests/fragmentQueryVerbMovesIntoBoard`: 2 cases passed. Full `swift test`: 1350 tests in 106 suites passed, 0 failed. Only the accepted SwiftPM "missing creator" warning. No production code change was necessary.
    - next: /review
  timestamp: 2026-10-15T05:24:48.502381+00:00
position_column: doing
position_ordinal: '80'
title: Add root query verbs and map createBoard and newBoard to initBoard
---
## What
divergence.md Q10 and Q11 (DECIDED: yes), N3, N4, and §11 "Q10", "Q11". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/). Code: S/GraphQL/NameMatcher.swift and S/GraphQL/NameRewrite.swift.

Q10, root query verbs (N3): now `getTask`, `listTasks`, `getBoard`, `listColumns`, `search`, and `next` all fail, because step 4 (word order and verb synonyms) applies only to mutations. Add verbs at the root of a query:
- `get`, `show`, `read`, `fetch` + a noun → the singular field (for example `getTask` → `task`, `getBoard` → `board`, `showColumn` → `column`).
- `list`, `find`, `query` + a noun → the plural field (for example `listTasks` → `tasks`, `listColumns` → `columns`).
- `search` (and `searchTask`, `searchTasks`) → `searchTasks`.
- `next` (and `getNext`, `nextTask`) → `nextTask`.
- Where a root field does not exist for a noun (for example columns are on `board`), map to the field that gives that list if there is one clear target; else keep the normal no-match error.

Q11 (N4): `createBoard` and `newBoard` map to `initBoard`. There is no `addBoard`, so there is no conflict. Now the never-list stops `create → init`, and the verb synonyms map `new` to `add` (S/GraphQL/NameMatcher.swift:50,90), so `newBoard` gives `addBoard`, which does not exist. Change this so that, for the noun `Board`, `create` and `new` map to `init`. For other nouns, `create` and `new` still map to `add`.

## Acceptance Criteria
- [x] `{ getTask(id: "<id>") { title } }` works as `task`.
- [x] `{ listTasks { nodes { id } } }` works as `tasks`.
- [x] `{ getBoard { name } }` works.
- [x] `{ search(query: "x") { ... } }` works as `searchTasks`.
- [x] `{ next { id } }` works as `nextTask`.
- [x] `mutation { createBoard(...) }` and `mutation { newBoard(...) }` work as `initBoard`.
- [x] `createTask` still maps to `addTask`.

## Tests
- [x] A test for each verb group (`get`, `show`, `read`, `fetch`, `list`, `find`, `query`, `search`, `next`).
- [x] Tests for `createBoard`, `newBoard`, and `createTask`.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-15 00:15)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 8 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `divergence.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift:335` `completeness/invariant-propagation` — The root query verb fix is tested only in a fragment definition on the query type (`{ ...Q } fragment Q on Query { listTasks ... }`). The same verb in an inline fragment (`{ ... on Query { listTasks ... } }`) has no test. The existing `tasks` rule has a test for both forms (lines 289-313), so the verb path has an untested sibling form. Add one case for a query verb in an inline fragment, such as `{ ... on Query { listTasks { totalCount } } }`, to the verb tests. Check that it rewrites to `_kanbanRoot0: board { listTasks: tasks ... }` with the same rewrite record. Do not add a full matrix.
