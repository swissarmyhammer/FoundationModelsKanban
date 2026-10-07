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