---
comments:
- actor: wballard
  id: 01m4bhdyfm8f7ymwen3cb1sk16
  text: |-
    Research done.
    - Plan: §3.3 rules 3, 4, 7; §5.3 step 4 and step 5; §6 table (Terminal column, `ready`, Virtual tags); §5.5 (CONFLICT); §12 items 7, 19.
    - Inputs: `Graph.dependencies(of:inBoard:)` gives edges ∪ markers. It keeps a `.slot` to a tombstoned task, so readiness must drop such a target (rule 3: the projection ignores an edge to a tombstone). An unresolved local or remote target counts as not done (rule 4).
    - Terminal column: the live column with the maximum `order`. On a tie, the sort is by slug (§5.3 step 5), so the terminal column is the last slug.
    - Cycle rule: a dependency counts as blocking when it is not done, or when a walk from it over `dependsOn` reaches the task again (the same cycle). The walk keeps a visited set and stops at a visited task. Thus each task on a cycle is blocked, also when the other tasks of the cycle are done.
    - Rust sources: `virtual_tags.rs` (READY, BLOCKED, BLOCKING strategies and the registry) and `task_helpers.rs` (`task_is_ready`, `task_blocked_by`, `task_blocks`, `find_dependent_task_ids` and their tests).
    - The Rust registry tests with mock strategies (ACTIVE, ALWAYS, NEVER), colors, descriptions, context-menu commands, and JSON metadata test a GUI registry. plan.md §4.1 gives `virtualTags: [String!]!` only, with no metadata. These tests have no counterpart here. The registry tests that do map (default registry has READY and BLOCKED, the order of the tags, a case-sensitive slug) are ported to the `VirtualTag` enum.
    - Out of scope (task ^w5xqjkr): the display rule "a task with no column or a tombstoned column shows in the first column". Here, such a task is not done, because its column is not the terminal column.
  timestamp: 2026-10-07T15:59:04.180474+00:00
- actor: wballard
  id: 01m4bhpbz879pzevwc0y1dca1b
  text: |-
    Implementation landed (TDD: the new tests did not compile before `Readiness` existed, then all passed).
    - `Derived/Readiness.swift`: `struct Readiness(of:inBoard:)` calculates the dependencies of all tasks one time. API: `isDone(taskAt:)`, `isReady(taskAt:)`, `blockers(ofTaskAt:)` (`blockedBy`, as `[EdgeTarget]`, so an unresolved target stays in the list), `dependents(ofTaskAt:)` (`blocks`, live tasks only, in slot order). `Graph.terminalColumnSlot`: the live column with the maximum `(order, slug)`.
    - Cycle rule: a done dependency still blocks when a walk from it over `dependsOn` comes back to the task. The walk keeps a visited set.
    - `Derived/VirtualTags.swift`: `enum VirtualTag: String, CaseIterable` (READY, BLOCKED, BLOCKING, CONFLICT, in the Rust registry order) and `Readiness.virtualTags(ofTaskAt:)`. A node that is not a task gets no virtual tags.
    - `Model/Node.swift`: new `EdgeTarget.resolvedSlot`, so that the new code does not repeat the `guard case .slot` block.
    - Tests: `ReadinessFixture.swift` (a shared board fixture; it uses the ULID, URL, URI, time, and board key helpers of `DependencyMarkersTests`, so that these helpers are not copied), `ReadinessTests.swift` (21 tests), `VirtualTagsTests.swift` (16 tests).
    - Not ported: Rust `test_find_dependent_task_ids_works_when_target_entity_is_absent`. Dependents here are keyed by slot, and a task that the graph does not have has no slot. The Rust registry tests for mock strategies, colors, commands, and JSON metadata have no counterpart (see the research comment).
    - Checks: swiftlint (no_magic_numbers, line_length 120, function_body_length, force_unwrapping, force_try) reports nothing on the changed files. periphery (`--retain-public`, `-- --build-tests --build-system native`) reports only the 4 assign-only findings in `GraphQL/Errors.swift` that were there before this change.
  timestamp: 2026-10-07T16:03:40.136205+00:00
- actor: wballard
  id: 01m4bhpeaadvrypvpf2ndb1332
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsKanban/Derived/Readiness.swift (new), Sources/FoundationModelsKanban/Derived/VirtualTags.swift (new), Sources/FoundationModelsKanban/Model/Node.swift, Tests/FoundationModelsKanbanTests/Derived/ReadinessFixture.swift (new), Tests/FoundationModelsKanbanTests/Derived/ReadinessTests.swift (new), Tests/FoundationModelsKanbanTests/Derived/VirtualTagsTests.swift (new). `swift test --filter 'ReadinessTests|VirtualTagsTests'`: 37 tests in 2 suites passed. `swift test`: 373 tests in 23 suites passed, 0 build warnings.
    - next: /review
  timestamp: 2026-10-07T16:03:42.538635+00:00
depends_on:
- 01M4B3XTMZSS5T07B8HEZXK9ZH
- 01M4B3XZ1QTBXDAFR0ZPWAFXGZ
position_column: doing
position_ordinal: '80'
title: 'Derived fields: readiness and virtual tags'
---
## What
Readiness and virtual tags at read time. The basis is plan.md §5.3 step 4 and §6 (Terminal column, `ready`, Virtual tags). Progress, times, summary, and the broken-merge display rules are in a separate task.
- `Sources/FoundationModelsKanban/Derived/Readiness.swift`: terminal column (max `order`), done, `ready` (all `dependsOn` targets done; an unknown or unresolved target counts as not done), `blockedBy`, `blocks`. A cycle from a merge: each task in the cycle is blocked, and the walk stops at a visited task.
- `Derived/VirtualTags.swift`: `READY` (not done, all dependencies done), `BLOCKED` (at least one dependency not done), `BLOCKING` (not done, some task depends on it) — port `../swissarmyhammer/crates/swissarmyhammer-kanban/src/virtual_tags.rs` — and `CONFLICT` (the body has a conflict block).

## Acceptance Criteria
- [x] A task that depends on an unknown task is blocked.
- [x] A dependency cycle from a merge gives blocked tasks, and the walk ends.
- [x] The ported `virtual_tags.rs` tests pass, and a task with a conflict block has `CONFLICT`.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Derived/ReadinessTests.swift` and `VirtualTagsTests.swift`.
- [x] Run `swift test --filter ReadinessTests` and `--filter VirtualTagsTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.