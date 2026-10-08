---
comments:
- actor: claude-code
  id: 01m4e2sktdfpbw73gkyz0674ky
  text: |-
    Research done. Findings:
    - `#DELETED` needs no parser change: it parses as `.atom(.tag, .name("DELETED"))`, and `FilterCompiler.tagTest` matches a virtual tag by name. Only `VirtualTag` and `Readiness.applies` change.
    - Plan (from the coordinator guidance "one generic mechanism"): `VirtualTag.hiddenUnlessNamed = [.deleted]`. One shared walk `FilterExpr.containsAtom(where:)` gives `namesColumn` and `names(_ virtualTag:)`. One new struct in Filter/ applies the rule "a task with a hidden-unless-named virtual tag matches only when the filter names that tag". `TaskSelection` and `ChangeFilter` both use it.
    - `BoardView.taskOrder` becomes all tasks (live and tombstoned) in board order; `orderedTasks` keeps the live tasks. `deletedTasks`, `boardOrder(deleted:)`, `TasksArguments.deleted`, `listsDeleted`, `listsDeletedByDefault` go away.
    - The search index (`TaskSearch.update`) holds only live tasks today, so `searchTasks(filter: "#DELETED")` could never find a tombstone. The index must hold the tombstones too; the selection then removes them unless the filter names `#DELETED`.
    - `nextTask` uses `where: \.ready`; `isReady` is true for a tombstone with no dependency, so nextTask must test the READY virtual tag (which now excludes tombstones).
    - `ChangeFilter` is also used by `history(filter:)`, so history follows the same rule.
  timestamp: 2026-10-08T15:41:01.133059+00:00
- actor: claude-code
  id: 01m4e3e9tx36bzmxf8fdvkjqke
  text: |-
    ### implement — changed
    - design: one generic mechanism keyed by the virtual tag (coordinator guidance). `VirtualTag.hiddenUnlessNamed = [.deleted]`. `FilterExpr.names(_ virtualTag:)` and `namesColumn` share one private walk `containsAtom(where:)`. New `Filter/TaskFilter.swift` applies "a task in a hidden state passes only when the filter names its tag, then the filter decides"; `TaskSelection` and `ChangeFilter` both use it. `FilterExpr.keepsDoneTasksByDefault` = names a column OR names a hidden-unless-named tag. A later `#DONE` task can add `.done` to the set.
    - removed: `TasksArguments.deleted`, `listsDeleted`, `listsDeletedByDefault`, `BoardView.deletedTasks`, `boardOrder(deleted:)`. `BoardView.taskOrder` is now private and holds live + tombstoned tasks; new `allTasks`; `orderedTasks` stays live-only.
    - nextTask: selects with the `READY` virtual tag (live, not done, ready), so `#DELETED` never gives a tombstone.
    - search: the index now holds tombstones too (`TaskSearch.update` uses `allTasks`); the selection removes them unless the filter names `#DELETED`.
    - interpretations: (1) no FilterParser change: `#DELETED` parses as a normal tag atom; no `namesDeleted`, a generic `names(.deleted)` instead. (2) `names` counts a tag URL of any board whose local id is DELETED, the same as `namesColumn` counts any column URL. (3) `history(filter:)` uses the same `ChangeFilter`, so a tag filter now also leaves out the updates of a task that is deleted now. (4) the `after` cursor of `tasks` resolves with tombstones; a task that the list does not hold still gives NOT_FOUND.
    - TDD: each new test failed on an assertion first (nextTask test after the list change). The registry test in VirtualTagsTests was changed after the enum case was added.
    - evidence: `swift build --build-tests` clean (only the accepted "missing creator" warning); `swift test --skip-build` 3 runs: 973/973 pass each; periphery: "No unused code detected".
    - next: /review
  timestamp: 2026-10-08T15:52:19.037848+00:00
position_column: doing
position_ordinal: '80'
title: 'Replace tasks(deleted:) with the #DELETED virtual tag'
---
## What
A person decided this on 2026-10-08. The filter language already selects tasks, so a separate `deleted` argument is not necessary. Remove the `deleted` argument from the task lists, and add a `#DELETED` virtual tag to the filter DSL.

Rules:
- `#DELETED` is a new `VirtualTag` case (`Sources/FoundationModelsKanban/Derived/VirtualTags.swift`). It is true for a tombstoned task (a task with `deleted` set). A tombstoned task shows `DELETED` in `virtualTags`. A tombstoned task is never `READY`, `BLOCKED` or `BLOCKING`.
- A task list (`Board.tasks`, the node `tasks(filter:)` fields, `nextTask`, `searchTasks`) selects from the live tasks by default. When the filter names `#DELETED` at any depth (also under a NOT, the same as `FilterExpr.namesColumn`), the list selects from the live tasks and the tombstoned tasks, and the filter decides. Thus `#DELETED` lists only the deleted tasks, `#DELETED || #bug` lists both, and `!#DELETED` lists the live tasks.
- `excludeDone` with no value is `false` when the filter names `#DELETED`, the same as when it names a column. Thus `#DELETED` shows a deleted task in the done column.
- `nextTask` never returns a tombstoned task.
- Remove `TasksArguments.deleted`, `listsDeleted`, `listsDeletedByDefault`, and `Board.deletedTasks` if nothing else uses it. Keep the `deleted` timestamp field on the node types.

Files: `Derived/VirtualTags.swift`, `Filter/FilterParser.swift` and `FilterEvaluator.swift` (the new atom and a `namesDeleted` check), `GraphQL/TaskSelection.swift`, `GraphQL/Schema.swift`, `GraphQL/QueryResolvers.swift`, the filter compatibility corpus if it lists virtual tags, and the tests that use `tasks(deleted: true)`. Update plan.md §3.3 rule 3, §4.1 and §6.3 and the virtual tag list.

## Acceptance Criteria
- [x] `tasks(filter: "#DELETED")` lists only the deleted tasks, also one in the done column; the schema has no `deleted` argument on a task list.
- [x] `tasks` with no filter, `!#DELETED`, and `nextTask` never give a tombstoned task.
- [x] A tombstoned task shows `DELETED` in `virtualTags`, and none of `READY`, `BLOCKED`, `BLOCKING`.

## Tests
- [x] Change the test "tasks(deleted: true) lists only the deleted tasks" to the `#DELETED` filter, and add tests for `#DELETED || #x`, `!#DELETED`, `nextTask`, and `virtualTags` of a tombstone.
- [x] Run the full `swift test`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.