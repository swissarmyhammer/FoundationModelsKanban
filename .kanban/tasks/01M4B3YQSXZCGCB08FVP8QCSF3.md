---
comments:
- actor: wballard
  id: 01m4bksdszm3ysrv82ahab4de7
  text: |-
    Research done.
    - Schema.swift has a placeholder `Board` struct, a `BoardStore` actor and `KanbanContext(store:clock:)`. GraphQLEngineTests builds that placeholder. The new types replace it, so only the `makeContext` fixture of GraphQLEngineTests changes (it builds a `Graph` with a `BoardNode`). The expected JSON of each test stays the same.
    - Graphiti 3.1 has no `ID` mapping. A custom `Scalar(..., as: "ID")` does not collide with the built-in `ID`, because the schema adds the specified scalars only when a type refers to them.
    - Graphiti `ConnectionType` has no `totalCount`, and `Edge` has an internal init. Thus `TaskConnection` and `TaskEdge` are own types. Graphiti `PageInfo` has a public init, so it is reused with an own `Type(PageInfo.self)` registration.
    - `Interface(P.self)` needs a protocol. `Reflection.isProtocol` reads `P.Protocol`, so the protocol needs no `Protocol` suffix.
    - The resolvers read one snapshot of the graph for each query (`Readiness` computes the dependencies one time).
    - `Graph.dependencies(of:inBoard:)` and `Readiness.blockers` can give unresolved edges (other boards). A `Task` output needs a node, so an unresolved target is not in `dependsOn`/`blockedBy` until the cross-repo task.
  timestamp: 2026-10-07T16:40:17.471305+00:00
- actor: wballard
  id: 01m4bmb966frv3jvsgwskw2zew
  text: |-
    Implementation landed.
    - The placeholder `Board` struct is gone. `BoardStore` is now an actor that holds the `Graph` and the board key. `KanbanContext(store:clock:)` stays. GraphQLEngineTests changes only in `makeContext` (a `Graph` with a `BoardNode`). All its assertions are the same, and they pass.
    - `Schema.swift`: `NodeObject` protocol = the `Node` interface; `BoardObject`, `ColumnObject`, `ActorObject`, `TagObject`, `TaskObject`, `CommentObject`, `TaskConnection`, `TaskEdge`; Graphiti registration with a `nodeType(_:as:fields:)` helper (a `@FieldComponentBuilder` closure; an array literal of `Field` values does not type-check).
    - `QueryResolvers.swift`: `BoardView` (one snapshot for each query: `Readiness`, board key, task board order), the field resolvers, `Graph.boardNode`.
    - `Scalars.swift`: `NodeID` is the `ID` scalar.
    - Discovery: Graphiti makes a non-optional Swift return type a non-null GraphQL field. A throw in a non-null root field made GraphQLSwift drop `data` completely. Thus `Query.board` and `Board.task` return an optional, so that they are nullable as plan.md §4.1 says.
    - Discovery: inside a `SchemaBuilder` extension, `Type<...>` in a type position does not compile ("protocol 'Type'"). Use `Graphiti.\`Type\``.
    - Cursor = the task `id` (full URI); `after` also accepts a short form. An `after` that names no live task gives NOT_FOUND.
    - A dependency on a task of a different board is not in `dependsOn`/`blockedBy` until the cross-repo task (no node to show).

    ### implement — changed
    - evidence: `swift build --build-tests` (no warnings); `swift test` 451 tests in 29 suites passed; `swift test --filter 'QueryResolverTests|GraphQLEngineTests'` 25 passed; periphery `--retain-public --retain-codable-properties -- --build-tests --build-system native`: no unused code.
    - files: Sources/FoundationModelsKanban/GraphQL/Schema.swift, Sources/FoundationModelsKanban/GraphQL/QueryResolvers.swift (new), Sources/FoundationModelsKanban/GraphQL/Scalars.swift, Tests/FoundationModelsKanbanTests/GraphQL/QueryResolverTests.swift (new), Tests/FoundationModelsKanbanTests/GraphQL/QueryFixture.swift (new), Tests/FoundationModelsKanbanTests/GraphQLEngineTests.swift
    - next: /review
  timestamp: 2026-10-07T16:50:02.566104+00:00
- actor: wballard
  id: 01m4bmk2zm4h1n8e5chm8chfeg
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD; 2 findings (2 confirmed, 0 refuted) — Sources/FoundationModelsKanban/GraphQL/Schema.swift:290, Sources/FoundationModelsKanban/GraphQL/Schema.swift:421
    - next: Put the five Node interface Field declarations in one shared helper. Use that helper in the Interface definition and in nodeFields. Then review again.
  timestamp: 2026-10-07T16:54:18.356124+00:00
- actor: wballard
  id: 01m4bmkd2gwx56jk9aetnwrxa6
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 6 files (GraphQL/Schema.swift, GraphQL/QueryResolvers.swift, GraphQL/Scalars.swift, QueryResolverTests.swift, QueryFixture.swift, GraphQLEngineTests.swift)
    - test: green — swift test, 451 passed, 0 warnings
    - commit: 6c5aa08
    - review: findings — Sources/FoundationModelsKanban/GraphQL/Schema.swift:290, Sources/FoundationModelsKanban/GraphQL/Schema.swift:421
  timestamp: 2026-10-07T16:54:28.688470+00:00
- actor: wballard
  id: 01m4bmsqnnhbdyh82msbz8vh8r
  text: |-
    Review findings fixed (duplication/duplication, Schema.swift Node fields).
    - Research in Graphiti 3.1.0: `Interface<Resolver, Context, InterfaceType>` takes `[FieldComponent<InterfaceType, Context>]` and `Type` takes `[FieldComponent<ObjectType, Context>]`. For the interface, `InterfaceType` is the existential `any NodeObject`. The existential does not conform to `NodeObject`, so a helper with the constraint `Object: NodeObject` cannot serve the interface.
    - Fix: `nodeFields<Object: Sendable>(of node: KeyPath<Object, any NodeObject>)` is the one list of the five Node fields. Each field reads `node.appending(path: \.id)` and so on. A new protocol extension property `NodeObject.nodeInterface: any NodeObject { self }` gives the key path for the interface and for each object type. `nodeType` and `addNodeInterface` both call the helper.
    - Discovery: a builder closure with one explicit `return` statement does not get the result builder transform. Thus `Interface(...) { return Self.nodeFields(of: \.nodeInterface) }` passes the array as it is, with no warning. An array value in a builder closure without `return` does not type-check, because `FieldComponentBuilder.buildExpression` takes one component only. A function reference (`fields: Self.labelFields`) also skips the transform.
    - Same cause in the file: `Actor` and `Tag` had the same three fields (`name`, `color`, `tasks`). New protocol `LabelObject` (associated type `Color`, because the actor color is `String?` and the tag color is `String`) and helper `labelFields()`. Both types now use `nodeType(..., fields: Self.labelFields)`.
    - SDL check: a temporary test wrote the public and patch SDL before and after the change. `diff` gave no difference for both schemas. The temporary test file is deleted.

    ### implement — changed
    - evidence: Sources/FoundationModelsKanban/GraphQL/Schema.swift; `swift build --build-tests` 0 warnings; `swift test` 451 tests in 29 suites passed; SDL (public and patch) identical before and after.
    - next: /review
  timestamp: 2026-10-07T16:57:56.149001+00:00
- actor: wballard
  id: 01m4bmxybpzefgkt6j7k0v701q
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (commit 4d00f32). 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. 1 file reviewed. 2 files in `.kanban/` not reviewed (.reviewignore). All prior Review Findings items are checked.
    - next: none. The task is in done.
  timestamp: 2026-10-07T17:00:14.070644+00:00
- actor: wballard
  id: 01m4bmy486v6z9x1zpp0s44hbp
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 1 file (GraphQL/Schema.swift); 2/2 findings checked; SDL unchanged (diff)
    - test: green — swift test, 451 passed, 0 warnings
    - commit: 4d00f32
    - review: clean — 0 findings
  timestamp: 2026-10-07T17:00:20.102475+00:00
depends_on:
- 01M4B3V9XKKT81TCZFJJT4PE6E
- 01M4B3YC73VSKE9VEP29E3CZNQ
- 01M4B4AJGSQDJ4PCBP2W5XQJKR
- 01M4B3Y4M87387J50EQCD36VB0
position_column: done
position_ordinal: '9580'
title: Public schema types and board queries
---
## What
The read side of the public GraphQL schema. The basis is plan.md §4.1. `node`, `nodes`, and the tombstone rules are in a separate task.
- `Sources/FoundationModelsKanban/GraphQL/Schema.swift`: the `Node` interface (`id`, `body`, `created`, `updated`, `deleted`) and the types `Board`, `Column`, `Actor`, `Tag`, `Task`, `Comment`, `TaskConnection` (cursor paging: `edges`, `pageInfo`, `totalCount`), `BoardSummary`, `Progress`.
- `GraphQL/QueryResolvers.swift`: resolvers read a `Graph` and the current board key from a context. Each `id` is the full URI. `Board.columns`, `Board.actors`, `Board.tags`, `Board.task(id:)`, `Board.tasks(first:, after:)` (the scoping arguments and `filter` are wired in the filter task). Task order: column order, then ordinal.
- `Query.board(id:)` for the current board only (related boards come with the cross-repo task).

## Acceptance Criteria
- [x] A deep query (task → dependsOn → comments → author) returns the correct nested graph from a fixture graph.
- [x] Paging with `first` and `after` returns each task one time, and `totalCount` is correct.
- [x] Each `id` in the output is a full `kanban://` URI with the current board key.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/GraphQL/QueryResolverTests.swift`: GraphQL documents against fixture graphs; compare response JSON.
- [x] Run `swift test --filter QueryResolverTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-07 11:51)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 6 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/GraphQL/Schema.swift:290` `duplication/duplication` — Identical Field declarations appear twice in the same file (lines 290–294 and 421–425), creating maintenance burden: a change to one list must be manually applied to the other, and the two can drift out of sync. Extract these five Field declarations into a shared helper function or constant, and call it from both the `Interface` definition (line 290 context) and the `nodeFields` function (line 421). This ensures a single source of truth for the Node interface fields.
- [x] `Sources/FoundationModelsKanban/GraphQL/Schema.swift:421` `duplication/duplication` — Identical Field declarations appear twice in the same file (lines 290–294 and 421–425), creating maintenance burden: a change to one list must be manually applied to the other, and the two can drift out of sync. Extract these five Field declarations into a shared helper function or constant, and call it from both the `Interface` definition (line 290 context) and the `nodeFields` function (line 421). This ensures a single source of truth for the Node interface fields.
