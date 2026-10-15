---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4zv8wgk7rt9rxb66y6y6ef1
  text: |-
    Research:
    - addActor ensure path is in S/GraphQL/ColumnActorMutations.swift (`if input?.ensure == true, work.graph.hasNode(ref) { return ref }`). WorkingCopy.apply drops a patch that changes nothing, so an update with the same values and a `delete: false` on a live node write no event.
    - Existing test ColumnActorTests.addActorEnsureExisting asserts the old rule (different name, writes nothing). It must change to "same values write nothing".
    - moveTask neighbor resolve is in Graph.ordinal(placing:inColumn:moving:resolvingWith:) in S/GraphQL/TaskOperationMutations.swift. copyTask (TaskTransferMutations.addCopy) uses the same function, so it gets the same rule.
    - The resolver closure is synchronous. ResolverWarnings.current (task local) is the sync way to add a warning to extensions.warnings (RefResolver uses it for the shared short id warning).
    - Existing test TaskOperationTests.moveTaskUnknownNeighbor asserts NOT_FOUND. It must change. The suite doc comment also names the old rule.
    - Empty tag list test exists: TaskOperationTests.emptyTagListWritesNothing. Keep it.
  timestamp: 2026-10-15T13:15:52.723872+00:00
- actor: claude-code
  id: 01m4zvm6w2cfszny7y9gfbbzn3
  text: |-
    Implementation landed (TDD: new tests failed first for the expected reason, then passed).
    - Rule 1: new `WorkingCopy.ensureActor(_:matching:at:)` in S/GraphQL/ColumnActorMutations.swift. It writes `delete: false`, then an update of each given name, color, and avatar. WorkingCopy.apply drops a patch that changes nothing, so the same values write no event. A field the input does not give does not change. The body is not touched by ensure.
    - Rule 2: kept `emptyTagListWritesNothing` as is; it passes.
    - Rule 3: `Graph.ordinal(besideRef:on:inColumn:moving:resolvingWith:)` in S/GraphQL/TaskOperationMutations.swift catches only `.notFound` from the neighbor resolve, adds a `NEIGHBOR_NOT_FOUND` warning through `ResolverWarnings.current` (the closure is sync), and returns the end ordinal. Other errors (for example AMBIGUOUS_ID) still throw. copyTask shares this function, so an unknown before/after on copyTask also goes to the end with the warning.
    - Tests: ColumnActorTests (same values write nothing; name/color/avatar update, parameterized; undelete), TaskOperationTests.moveTaskUnknownNeighborAppends (before and after). The old NOT_FOUND neighbor test was replaced. Suite doc comments updated.
    - plan.md not changed (frozen).
  timestamp: 2026-10-15T13:22:03.778608+00:00
- actor: claude-code
  id: 01m4zvm96jw1j1zh9qn00qxvky
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/GraphQL/ColumnActorMutations.swift, Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift, Tests/FoundationModelsKanbanTests/Mutations/ColumnActorTests.swift, Tests/FoundationModelsKanbanTests/Mutations/TaskOperationTests.swift. `swift test`: 1445 tests in 111 suites passed, 0 failures; only the accepted SwiftPM "missing creator" warning.
    - next: /review
  timestamp: 2026-10-15T13:22:06.162968+00:00
depends_on:
- 01M4X6X6PS5P524DW45RBSSWN2
- 01M4X764NWFQQH1Y10RFXKM3BC
position_column: doing
position_ordinal: '80'
title: Keep the Rust behavior for addActor ensure, empty tag lists, and unknown before/after refs
---
## What
divergence.md Q16 with its third rule replaced by P1 (DECIDED), O1, O2, O3, and §11 "Q16". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Decided behavior (three rules):
1. `addActor(ensure: true)` updates the name, the color, and the `avatar` when they are different, and makes a deleted (tombstoned) actor live again. Now Swift writes nothing (S/GraphQL/ColumnActorMutations.swift:242-244) and returns a tombstoned actor as it is. The `avatar` field comes from the Q19 task.
2. `tagTask` and `untagTask` with an empty list write nothing and return the task. There is no error. (This is the current Swift behavior; keep it and keep its test.)
3. (P1, replaces the first Q16 rule) An unknown `before` or `after` ref on `moveTask` (a ref that names no task) puts the task at the end of the column. The response gets a warning in `extensions.warnings` that names the ref. Now Swift gives `NOT_FOUND`.

## Acceptance Criteria
- [ ] `addActor(input: {id: "a", name: "New"}, ensure: true)` on an existing actor `a` with a different name updates the name.
- [ ] The same for `color` and `avatar`.
- [ ] `addActor(ensure: true)` on a deleted actor makes it live again.
- [ ] `addActor(ensure: true)` with the same values writes no event.
- [ ] `tagTask(tags: [])` and `untagTask(tags: [])` write nothing and return the task.
- [ ] `moveTask(id: ..., before: "zzzzzzz")` puts the task at the end of the column and gives a warning that names `zzzzzzz`.

## Tests
- [ ] Tests for each part of rule 1 (name, color, avatar, undelete, no change).
- [ ] The existing empty-list test for rule 2.
- [ ] A test for rule 3 with `before` and with `after`.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.