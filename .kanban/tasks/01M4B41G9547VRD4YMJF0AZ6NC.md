---
comments:
- actor: wballard
  id: 01m4c99xkc4e8j3kxz7c9qysjz
  text: 'Research done. GraphQLSwift 4.3.0 AST nodes have internal inits and `private(set)` properties, so the code cannot make a new `Name` node. Thus the rewrite parses the document, walks the AST with the schema types (public `fields` thunks, `args`, `InputObjectType.fields`, `EnumType.values`), and collects text edits at the UTF-8 offsets of `Name.loc` / `EnumValue.loc`. It then applies the edits to the source text, and runs the new text with the existing `execute(request:)` of Graphiti. `GraphQLResult` has no `extensions`, so `API.respond` encodes its own response type with `extensions.rewrites`. The root move wraps the field as `<key>: board { … }` and moves `data.<key>.<field>` back to `data.<field>` after execution; error paths drop the wrapper key. No public field takes an enum argument from the root yet (only `Change.updates(type:)`), so the enum position test runs the rewriter on a fragment on `Change`.'
  timestamp: 2026-10-07T22:56:18.028232+00:00
- actor: wballard
  id: 01m4ca5jeycsr6chq8kwc6qp1v
  text: |-
    Implementation landed (TDD). RED: a stub `DocumentRewriter` that changed nothing; 20 of 21 tests failed on assertions (the `createBoard` guard test passed, because validation already refused it). GREEN after the walk. A second RED/GREEN cycle added the error-location test: a validation error after a rewrite pointed at the rewritten text (column 22, expected 16); `callerResult(from:)` now maps each error position back to the text of the caller.

    Design: `NameRewrite.swift` parses the document, walks it with the schema types, and collects UTF-8 text edits at `Name.loc` / `EnumValue.loc`; `API.respond` (Schema.swift) runs the new text with `execute(request:)` and encodes `RewriteResponse` (`data`, `errors`, `extensions.rewrites`). A tie returns only the tie errors and does not run the document. The root move wraps the field as `_kanbanRoot<n>: board { … }`; `callerResult(from:)` moves `data._kanbanRoot<n>.<key>` back to `data.<key>` and drops the wrapper key from error paths.

    Discoveries:
    - GraphQLSwift 4.3.0 gives a `Field`, `Argument`, `SelectionSet`, `ListValue`, and `Directive` a `loc` that ends before their children (Swift evaluates `loc:` before the child parse arguments). Only `Name` and leaf values have correct ends. The walk finds the end of a field from the token chain (`Token.next`, bracket depth) instead.
    - AST inits are internal, so the code cannot build new nodes; the text-edit approach is the only one with the public API.
    - No root-reachable field takes an enum argument yet (only `Change.updates(type:)`), so the enum test runs the rewriter on a fragment on `Change`.
    - Limits, by design: a root move applies only to fields directly in a `query` operation, not inside a fragment on `Query`; variables are JSON and are not rewritten. Snake case and the alias table do not apply to the single-word enum values, and the mutation position has no alias-table entries, so those cells test the caller alias instead.

    Checks: `swift test` 792 tests in 46 suites pass; build has only the two known warnings (mlx Metal, SwiftPM "missing creator"); swiftlint (no_magic_numbers, missing_docs, force rules, line_length 120): 0 violations; swift format idiom rules: 0; periphery (native build, --retain-public, tests excluded from report): no unused code.
  timestamp: 2026-10-07T23:11:24.126028+00:00
- actor: wballard
  id: 01m4ca5mfrw3cagmh55n1wfe13
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift (new), Sources/FoundationModelsKanban/GraphQL/Schema.swift (`API.respond` runs the rewrite, `RewriteResponse` with `extensions.rewrites`), Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift (new). `swift test --filter NameRewriteTests`: 22 tests passed. `swift test`: 792 tests in 46 suites passed, 0 new warnings. swiftlint and swift format: 0 findings. periphery: no unused code.
    - next: /review
  timestamp: 2026-10-07T23:11:26.200055+00:00
- actor: wballard
  id: 01m4cacmv1dqy1jx4hk139kt68
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (c04c7f6); 1 finding (1 confirmed, 0 refuted) — Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift:293
    - next: Do the open item in "Review Findings (2026-10-07 18:13)". Then review again.
  timestamp: 2026-10-07T23:15:15.937922+00:00
- actor: wballard
  id: 01m4cacyvberd4pe0v922wxvc7
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 3 files (GraphQL/NameRewrite.swift, GraphQL/Schema.swift, NameRewriteTests.swift)
    - test: green — swift test, 792 passed; build warnings only the 2 accepted kinds
    - commit: c04c7f6
    - review: findings — Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift:293
  timestamp: 2026-10-07T23:15:26.187651+00:00
- actor: wballard
  id: 01m4camdxqt5adnjfy68xxapcq
  text: |-
    Finding NameRewrite.swift:293 `completeness/invariant-propagation` fixed (TDD). The preferred fix applies to both places: inline fragments and named fragment definitions.

    RED: 2 new parameterized tests in NameRewriteTests (`fragmentRootFieldMovesIntoBoard`, 3 cases: `... on Query`, `...` with no type condition, and `fragment Q on Query`; `fragmentRootFieldGivesRootResult`, 2 cases through `QueryFixture.respond`). 8 assertion failures: the text was not rewritten, `rewrites` was `[]`, and `data` was nil because validation failed.

    GREEN: the move check is now in `visitSelections(of:on:at:as:)`. It runs when the parent type is the query type. The operation root, the InlineFragment branch, and the fragment definition all go through `visitSelections`, so one check covers all three places. `moveIntoBoard(_:at:)` reads `schema.queryType` and takes the path, so a rewrite in fragment `Q` has the path `["Q", "tasks"]`.

    Why the named fragment is correct with the text rewrite: no field in the schema returns the query type. Thus a fragment on `Query` can only be spread at the root of `data`, and the `_kanbanRoot<n>` key comes back at the root, where `callerResult(from:)` restores it. A spread in a mutation or a subscription is not valid GraphQL, so validation refuses it.

    Discovery, recorded as task ^1w0aefx: two moved root fields with the same response key (for example a direct `tasks` and a `tasks` in a fragment) get two wrapper keys, and `restoring(_:moving:)` keeps only the first value. GraphQL would merge them. The bug existed before this change, for two direct `tasks` fields too.

    Checks: `swift test` gave 794 tests in 46 suites, all pass. The only build warning is the accepted mlx "missing creator" kind.
  timestamp: 2026-10-07T23:19:30.999344+00:00
- actor: wballard
  id: 01m4camfn9xaefbwt18q7h6nw7
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift, Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift. `swift test --filter NameRewriteTests/fragmentRootField`: RED 8 issues, then GREEN 2 tests (5 cases). `swift test`: 794 tests in 46 suites passed; the only build warning is the accepted mlx "missing creator" kind.
    - next: /review
  timestamp: 2026-10-07T23:19:32.777837+00:00
depends_on:
- 01M4B40W9YCS7ZKYB43KFK6T3Z
- 01M4B406Z7RVSBJKKJ8KJW0CY2
- 01M4B40CFSF002B4DKM3T8J6GV
- 01M4B4B57JFX8HA0B45MMDQ1SQ
- 01M4B4B1G28KK1NVCXHK9GDAYR
position_column: doing
position_ordinal: '80'
title: 'Forgiving names: rewrite the document'
---
## What
Rewrite the parsed GraphQL document before validation. The basis is plan.md §4.5 (Positions, Rules) and §12 items 14 and 16.
- `Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift`: walk the parsed document and use `NameMatcher` at each position: top-level mutation, field in a selection, argument and `input` field, enum value, root query field.
- Keep the response key: add a GraphQL alias (`taskAdd: addTask(...)`, `desc: body`). Keep an alias that the caller wrote.
- Root query field: if the root has no such field but `Board` has it, move it into `board { … }`, and after execution move the result back, so the response has `data.tasks`.
- `extensions.rewrites`: a list of `{ from, to, path }`.
- A tie gives an error that lists the matches. No match: normal validation runs and gives the "did you mean" error.

## Acceptance Criteria
- [x] `taskAdd`, `addTask`, and `createTask` give the same patches, and the response key is the name that the caller wrote; `createBoard` does not map to `initBoard`.
- [x] `archiveTask` runs `deleteTask`, and `restoreTask` runs `undeleteTask`, through `execute`.
- [x] `{ tasks { … } }` gives the same result as `{ board { tasks { … } } }`, under `data.tasks`; each rewrite is in `extensions.rewrites`.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift`: wrong case, `snake_case`, plural, alias, one wrong letter, at each position; ties; root move; the archive and restore verbs.
- [x] Run `swift test --filter NameRewriteTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-07 18:13)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift:293` `completeness/invariant-propagation` — The root-field move into `board` runs only for a direct Field of a query operation. The same root query field inside an inline fragment on the query type (for example `{ ... on Query { tasks } }`) or inside a fragment definition on the query type is not moved. Those selections reach `visit(_:on:at:as:)` through `visitSelections` (line 313) and the InlineFragment branch (lines 335-339), which never call `moveIntoBoard`. The caller's `tasks` then fails validation with 'Cannot query field', even though the same name is accepted at the top level. Route root-level selections in inline fragments on the query type, and in fragment definitions on the query type, through the same move check as line 293. Or state in a doc comment that the move applies only to direct selections. Add one test with `{ ... on Query { tasks { totalCount } } }` that asserts the chosen behaviour.
