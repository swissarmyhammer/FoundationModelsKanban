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
- actor: wballard
  id: 01m4c2psz4m7zh9999vzqdj6cm
  text: |-
    ### decision (person) — blocker resolved
    - The user decided: `nodes(ids:)` returns an empty list, not null. An unknown id is dropped from the result, so a call where no id matches gives `[]`.
    - Schema: `nodes(ids: [ID!]!): [Node!]`. The list has no null items. The field itself is nullable only so that an error (for example `AMBIGUOUS_ID`, the same rule as `node(id:)`) gives `null` for this field plus an item in `errors`, and does not drop all `data`.
    - plan.md §4.1 must change to match.
    - Next: start from the parked branch `wip/ryf7rn1-nodes-null` (commit 1b4a52c), apply this decision, and run the finish loop again.
  timestamp: 2026-10-07T21:01:00.260669+00:00
- actor: wballard
  id: 01m4c312bdpxf90g5pjvxmahx7
  text: |-
    Picked up again after the decision. Work done:
    - `git cherry-pick --no-commit 1b4a52c` onto `main`. RefResolver.swift and NodeQueryTests.swift merged clean. QueryResolvers.swift and Schema.swift had conflicts; I resolved them by hand. No commit was made (HEAD is still fec7aa0). The branch `wip/ryf7rn1-nodes-null` stays as it is.
    - Conflict resolution: `main` moved `updateBoard` to MutationResolvers.swift, so the WIP copy of `updateBoard` in Schema.swift is dropped. `TasksArguments` keeps all the `main` arguments (`filter`, `column`, `tag`, `assignee`, `excludeDone`) and adds `deleted`. `TaskSelection` now selects from `BoardView.deletedTasks` when `deleted: true`, so the filter and the scoping arguments also apply to the deleted list.
    - Discovery: with the plan rule "excludeDone with no value is true", `tasks(deleted: true)` hides a deleted task in the done column. The fixture's third task is in `done`, so the test "tasks(deleted: true) lists only the deleted tasks" failed (RED). I made `excludeDone` with no value `false` for `deleted: true`, so that the list shows each deleted task. plan.md does not state this rule yet; I added task ^d8wwdgy for it (I changed only §4.1 `nodes` in plan.md, as the order says).
    - `nodes(ids:)`: the resolver is now `async throws(KanbanError) -> [any NodeObject]?`. SDL: `nodes(ids: [ID!]!): [Node!]`. `compactMap` does not support typed throws, so the code uses `map { id throws(KanbanError) in ... }.compactMap(\.self)`.
    - TDD: the 4 new nodes tests and the deleted-list test failed on assertions first (the old GraphQLSwift MapError, and the excludeDone default). After the change they pass. The SDL test "The schema gives nodes(ids:) a nullable list with no null item" was added after the code and passed at its first run; it locks the schema contract.
    - plan.md §4.1 now shows `nodes(ids: [ID!]!): [Node!]` and the drop rule.
  timestamp: 2026-10-07T21:06:36.525326+00:00
- actor: wballard
  id: 01m4c3157d47eeptp6anc78b38
  text: |-
    ### implement — changed
    - evidence: `swift test` — 712 tests in 42 suites pass, 0 failures, 0 compiler warnings. `swift test --filter NodeQueryTests` — 15 of 15 pass. Files: Sources/FoundationModelsKanban/GraphQL/Schema.swift, Sources/FoundationModelsKanban/GraphQL/QueryResolvers.swift, Sources/FoundationModelsKanban/GraphQL/TaskSelection.swift, Sources/FoundationModelsKanban/Identity/RefResolver.swift, Tests/FoundationModelsKanbanTests/GraphQL/NodeQueryTests.swift, plan.md.
    - blocker: resolved by the decision; the card no longer shows it.
    - next: `/review`. Not committed. Task ^d8wwdgy holds the plan.md text for the excludeDone default of `tasks(deleted: true)`.
  timestamp: 2026-10-07T21:06:39.469801+00:00
- actor: wballard
  id: 01m4c36er6djh2zpmzd38m5v2m
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (a897866). 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. 5 files reviewed. Not reviewed: 8 files in .kanban/ (ignore rule) and plan.md (no validator matches this file).
    - next: none. The task moved to done.
  timestamp: 2026-10-07T21:09:33.062975+00:00
- actor: wballard
  id: 01m4c36pa0e3q9gjgaptvqgmkm
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 6 files (Schema.swift, QueryResolvers.swift, TaskSelection.swift, RefResolver.swift, NodeQueryTests.swift, plan.md); cherry-picked 1b4a52c, applied the person's decision (unknown ids dropped)
    - test: green — swift test, 712 passed, 0 warnings
    - commit: a897866
    - review: clean — 0 findings
  timestamp: 2026-10-07T21:09:40.800733+00:00
depends_on:
- 01M4B3YQSXZCGCB08FVP8QCSF3
position_column: done
position_ordinal: a180
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
- [x] `nodes(ids:)` drops an unknown id. The list has no `null` item, and a call where no id matches gives `[]`. The known ids keep the input order. An ambiguous id gives `AMBIGUOUS_ID` and `null` for the field only; the other fields keep their data. The schema is `nodes(ids: [ID!]!): [Node!]` (plan.md §4.1). The earlier blocker (GraphQLSwift 4.3.0 cannot serialize a `null` list item) is resolved: a person decided on this contract (see the comments).

## Tests
- [x] `Tests/FoundationModelsKanbanTests/GraphQL/NodeQueryTests.swift`.
- [x] Run `swift test --filter NodeQueryTests`; expect all pass. 15 of 15 tests pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.