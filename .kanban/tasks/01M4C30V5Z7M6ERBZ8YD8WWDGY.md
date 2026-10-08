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
- actor: claude-code
  id: 01m4e3tbr4tx6e1vjxd7wyh9zh
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (46c3c41) — 1 finding (1 confirmed, 2 refuted): Tests/FoundationModelsKanbanTests/Search/TaskSearchTests.swift:263 completeness/inverse-operation-coverage
    - next: Add an undelete step to the #DELETED search test, or a sibling test. Assert that the #DELETED search does not return the task after undelete, and that the plain title search returns it again. Then run /review again.
  timestamp: 2026-10-08T15:58:54.212408+00:00
- actor: claude-code
  id: 01m4e3tmk063qs2t6g72f6a306
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 9 source files (new Filter/TaskFilter.swift), 7 test files, plan.md; removed the public `deleted` argument of Board.tasks
    - test: green — root swift test 3 runs, 973 passed each (7.5 s, 7.4 s, 7.4 s); IntegrationTests 2 passed; build warnings only the 2 accepted kinds
    - commit: 46c3c41
    - review: findings — Tests/FoundationModelsKanbanTests/Search/TaskSearchTests.swift:263
  timestamp: 2026-10-08T15:59:03.264052+00:00
- actor: claude-code
  id: 01m4e45q6r5b5dp3yg9d83zjhb
  text: |-
    Fix of the finding `completeness/inverse-operation-coverage` (TaskSearchTests). Cause: the #DELETED tests of the last commit checked only the delete direction. I added the undelete direction to each #DELETED area:
    - TaskSearchTests `deletedTaskIsHitOnlyForDeletedFilter`: after an undelete (same index), the plain title search ranks the task first again, and the #DELETED search gives no hit.
    - NodeQueryTests: new `QueryFixture.undelete(nodeAt:)`. `delete` and `undelete` share one private `setDeleted(_:ofNodeAt:)`, so no helper is copied. New parameterized test `undeletedTaskLosesDeletedVirtualTag`: after delete + undelete, virtualTags is ["READY","BLOCKING"] (first task) and ["BLOCKED"] (second task). New helpers `virtualTags(of:in:)` and `virtualTagsResponse(_:)`; the old DELETED virtualTags test uses them too.
    - TaskOperationTests `undeleteTaskRestoresTask`: the #DELETED list is empty after undeleteTask (the default list check was already there).
    - HistoryTests: new `historyAfterUndeleteFollowsLiveTask` (tag, delete, undelete): history(filter: "#DELETED") is empty, and history(filter: "#bug") starts with "TASK RESTORED". New constants `bugFilterArguments` and `deletedFilterArguments` replace the repeated filter literals in the file.
    - SubscriptionTests: new `deletedFilterLeavesOutUndelete`: a #DELETED subscription gets delete, (no undelete), delete. `update(ofTask:from:)` gets a defaulted `kind:` parameter; new helper `deleteTask(_:on:)`.
    - VirtualTagsTests: the last commit changed only the registry test there; it has no delete-direction test, so it needs no inverse. The undelete virtualTags check is in NodeQueryTests.
    Proof that each new assertion can fail: I made undelete a no-op for one run (production `undeleteTask` wrote `delete: true`; `QueryFixture.undelete` kept the time). All 5 new or changed tests failed on the new assertions (12 issues). Then I restored both edits; `git diff -- Sources` is empty.
    Note: on this repo, `files` `edit file` with `replace_all: true` replaced only the first match. Do one edit for each match.
  timestamp: 2026-10-08T16:05:06.392858+00:00
- actor: claude-code
  id: 01m4e45sfta5xwtyf3ddwg6r47
  text: |-
    ### implement — changed
    - evidence: 5 test files — Tests/FoundationModelsKanbanTests/Search/TaskSearchTests.swift, GraphQL/NodeQueryTests.swift, Mutations/TaskOperationTests.swift, Undo/HistoryTests.swift, Observe/SubscriptionTests.swift. `swift build --build-tests` clean (only the accepted "missing creator" warning). `timeout 120 swift test --skip-build` 3 runs: 976/976 pass each (7.53 s, 7.57 s, 7.50 s). Finding `TaskSearchTests.swift:263` is checked.
    - next: /review
  timestamp: 2026-10-08T16:05:08.730838+00:00
- actor: claude-code
  id: 01m4e4da6rns7cx8n7v4jwmmxm
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (41a3bf5); 1 finding (1 confirmed, 0 refuted) — Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift:179 `reuse/reuse`
    - next: make the deleteTask and changeTitle helpers use one shared helper, then review again. The task stays in review.
  timestamp: 2026-10-08T16:09:15.224748+00:00
- actor: claude-code
  id: 01m4e4djq4yy4pmy8rb5ss0wfw
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 5 test files (undelete checks, QueryFixture.undelete(nodeAt:)); 1/1 prior findings checked
    - test: green — swift test 3 runs, 976 passed each (7.5 s, 7.4 s, 7.6 s); build warnings only the 2 accepted kinds
    - commit: 41a3bf5
    - review: findings — Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift:179
  timestamp: 2026-10-08T16:09:23.940486+00:00
- actor: claude-code
  id: 01m4e4hjeqvczbxmkfta1dhdnc
  text: |-
    Fix of the finding `reuse/reuse` (SubscriptionTests.swift:179). Cause: `changeTitle` and `deleteTask` each ran a mutation with `CommentTests.run`, read `latestTxn`, and built the event. Also `titleEvent` and `deleteTask` each built the same one-update patch event.
    - New private `runMutation(_:operation:of:kind:on:)`: runs the mutation field, reads `latestTxn`, and gives the event. `changeTitle` and `deleteTask` both call it. The names that the tests use did not change.
    - New private `patchEvent(of:kind:txn:operation:)`: builds an event with one patch update of a task. `titleEvent` and `runMutation` both use it.
    - Other flows in the file: the undeleteTask call in `deletedFilterLeavesOutUndelete` runs a mutation but builds no event, so it is not the same flow. The DERIVED event in `doneTaskOfRelatedBoardSendsDerivedUpdate` uses a URI and the `.derived` source, so it uses `event` directly. No test assertion changed.
    - Note: the `dump validators` rules file is 754 K characters; I used the rules that the coordinator listed.
  timestamp: 2026-10-08T16:11:34.743065+00:00
- actor: claude-code
  id: 01m4e4hktv1wq9r53b6nzfmq47
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift. `swift build --build-tests` clean (only the accepted "missing creator" warning). `timeout 120 swift test --skip-build` 3 runs: 976/976 pass each (7.42 s, 7.44 s, 7.49 s). Finding `SubscriptionTests.swift:179` is checked.
    - next: /review
  timestamp: 2026-10-08T16:11:36.155145+00:00
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

## Review Findings (2026-10-08 10:56)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 15 file(s) reviewed, 9 not reviewed.

> 8 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 8 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/Search/TaskSearchTests.swift:263` `completeness/inverse-operation-coverage` — The new test proves that a deleted task is a search hit only for the #DELETED filter. It never checks the inverse: after the task is undeleted, the #DELETED filter must no longer hit it. The one-way test leaves the restore direction of the new filter rule unproven. Add an undelete step to this test, or a sibling test, and assert that the #DELETED search no longer returns the task while the plain title search returns it again.

## Review Findings (2026-10-08 11:08)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 5 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift:179` `reuse/reuse` — The new deleteTask helper repeats the shape of the existing changeTitle helper: it runs a mutation call with CommentTests.run, reads latestTxn, and builds the event with event(...). The only differences are the operation, the update kind, and the mutation field. changeTitle was not extended to take those parameters, so there are now two parallel copies of the same flow that can drift apart. Generalize the existing helper instead of adding a parallel one. For example, give changeTitle (or a shared private helper) a parameter for the mutation field and the update kind, so changeTitle and deleteTask both call it. Keep the public names the tests use.
