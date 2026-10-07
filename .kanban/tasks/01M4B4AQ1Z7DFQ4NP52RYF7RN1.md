---
comments:
- actor: wballard
  id: 01m4bn3yva4x96kwvqgrndea7j
  text: |-
    Research done.
    - `Comment.author` already returns a tombstoned actor (`Graph.author(ofCommentAt:)` in BrokenMergeDisplay, `CommentObject.author`). A test in NodeQueryTests will lock this.
    - `BoardView.taskOrder` holds only live tasks (`boardOrder` filters tombstones). `tasks(deleted: true)` needs the same board order for the tombstoned tasks. `Readiness.column(ofTaskAt:)` works for a tombstone too.
    - `RefResolver.storedRef(for:ofType:includingTombstones:)` resolves one expected type. `node(id:)` has no expected type for a short form. Plan: add a resolve of any type to RefResolver. A full URI gives its type. A short form tries the ULID types (task and comment together, so that a prefix of a task and a comment is AMBIGUOUS_ID and a canonical form wins over a prefix), then board key, column, actor, tag slugs, in this order. Tombstones are accepted (plan.md §3.3 rule 3).
    - `nodes(ids:)` is `[Node]!`: a throw in the list resolver drops `data`, so each unknown or ambiguous id gives `null` at its position. `node(id:)` gives `null` for an unknown id, and `null` plus AMBIGUOUS_ID for an ambiguous id.
  timestamp: 2026-10-07T17:03:31.178277+00:00
- actor: wballard
  id: 01m4bnembqt3x3bx963dt7hdp3
  text: |-
    BLOCKER: `nodes(ids:)` cannot return `null` at a list position with GraphQLSwift 4.3.0 (the latest tag).

    What happens: `{ nodes(ids: ["<unknown ULID>"]) { id } }` gives `{"errors":[{"message":"The operation couldn’t be completed. (GraphQL.MapError error 0.)","path":[]}]}` and no `data`. A list with only known ids works, and an empty list works.

    Cause, in `.build/checkouts/GraphQL/Sources/GraphQL`:
    - `Execution/Execute.swift` `completeListValue` keeps a `nil` item as `nil` (`results[result.0] = result.1`). Object fields use `?? Map.null`, so a null field works, but a null list item does not.
    - `Execution/Execute.swift` `execute` then calls `map(from:)` on the data. In `Map/Map.swift`, `map(from:)` casts the list to `[Any]`. Each `nil` item is an `Any` that holds `Optional.none`. No branch accepts it (`Map(any:)`, the dictionary branch, the `[Any]` branch, and the `Encodable` branch all fail), so it throws `MapError.incompatibleType`, and the `catch` replaces all `data` with one error.
    - There is no hook in Graphiti or GraphQLSwift to change this. A `Map.null` item from the resolver does not help: the item type `Node` is abstract, so type resolution fails and the item becomes `nil` again.

    What I tried: a `try?` per id in the resolver (the item is `nil` as the card asks; the library fails to serialize it); a probe with known ids only, an unknown id only, and an empty list (only the unknown id fails).

    A person must choose one of these. Each one is outside this card:
    1. Use a patched GraphQLSwift (fork or upstream PR): in `completeListValue`, write `results[result.0] = result.1 ?? Map.null`, the same as the object path.
    2. Change plan.md §4.1 so that `nodes(ids:)` is `[Node!]!` and drops unknown ids (this changes the documented contract).
    3. Another schema shape that the person decides.

    State of the work: all other parts of the card are done. `swift test`: 462 tests in 30 suites, 1 failure, which is "nodes(ids:) returns null at the position of an unknown id" in NodeQueryTests. That test stays, because it holds the card requirement.
  timestamp: 2026-10-07T17:09:20.887373+00:00
- actor: wballard
  id: 01m4bnerzwj6tfvg2m0em2qq3y
  text: |-
    ### implement — stuck
    - evidence: `swift test` — 462 tests in 30 suites, 1 failure ("nodes(ids:) returns null at the position of an unknown id", NodeQueryTests). `swift test --filter NodeQueryTests` — 10 of 11 pass. Files: Sources/FoundationModelsKanban/Identity/RefResolver.swift, Sources/FoundationModelsKanban/GraphQL/QueryResolvers.swift, Sources/FoundationModelsKanban/GraphQL/Schema.swift, Tests/FoundationModelsKanbanTests/GraphQL/NodeQueryTests.swift (new).
    - done: `Query.node(id:)` (six types, full URI and short form, tombstones with `deleted`, AMBIGUOUS_ID for a prefix of a task and a comment), `Query.nodes(ids:)` for known ids, `Board.tasks(deleted:)`, `Comment.author` tombstone test. `TaskArguments` is now `NodeArguments` (shared by `Board.task` and `Query.node`).
    - blocker: GraphQLSwift 4.3.0 cannot serialize a `null` list item (see the BLOCKER comment).
    - next: a person picks a fix for the blocker; then run `/test` and `/review`.
  timestamp: 2026-10-07T17:09:25.628796+00:00
- actor: wballard
  id: 01m4bnfpr6pwkzpmfccnvsaw19
  text: |-
    ### finish iteration 1 — stuck
    - implement: stuck — 4 files (RefResolver.swift, QueryResolvers.swift, Schema.swift, NodeQueryTests.swift); swift test 461/462 pass; the failure is "nodes(ids:) returns null at the position of an unknown id"
    - cause: GraphQLSwift 4.3.0 `completeListValue` keeps a null list item as Swift nil; `map(from:)` then throws MapError.incompatibleType and the library drops all `data`. The item type `Node` is an interface, so returning Map.null from the resolver does not help. 4.3.0 is the newest tag.
    - blocker: plan.md §4.1 requires `nodes(ids:)` to give null for an unknown id. A person must choose: (1) a patched or forked GraphQLSwift, (2) change §4.1 to `[Node!]!` and drop unknown ids, or (3) a different schema shape.
    - test: not run (implement is stuck)
    - commit: none on main. The partial work is kept on the local branch `wip/ryf7rn1-nodes-null`, so that main stays green.
    - review: not run
  timestamp: 2026-10-07T17:09:56.102996+00:00
depends_on:
- 01M4B3YQSXZCGCB08FVP8QCSF3
position_column: doing
position_ordinal: '80'
title: 'Queries: node, nodes, and tombstones'
---
## What
Direct access by id, and the read rules for deleted nodes. The basis is plan.md §4.1 (`Query.node`, `Query.nodes`) and §3.3 rule 3.
- `Sources/FoundationModelsKanban/GraphQL/QueryResolvers.swift` (node part): `Query.node(id:)` and `Query.nodes(ids:)` accept any short form or full URI and return the `Node` interface (all six types).
- Tombstones: lists and edges ignore a tombstone; `node` and `nodes` return it with `deleted` set; `Board.tasks(deleted: true)` lists only deleted tasks.
- `Comment.author` returns a deleted author as the tombstone.

## Acceptance Criteria
- [x] `node(id:)` returns each of the six node types by full URI and by short form.
- [x] A deleted task is not in `tasks`, and `node(id:)` returns it with `deleted` set; `tasks(deleted: true)` lists it.
- [ ] `nodes(ids:)` returns `null` at the position of an unknown id. BLOCKED: GraphQLSwift 4.3.0 cannot serialize a `null` item in a list (see the comments).

## Tests
- [x] `Tests/FoundationModelsKanbanTests/GraphQL/NodeQueryTests.swift`.
- [ ] Run `swift test --filter NodeQueryTests`; expect all pass. 10 of 11 tests pass; the `nodes(ids:)` null test fails because of the blocker.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.