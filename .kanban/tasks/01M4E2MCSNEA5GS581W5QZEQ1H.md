---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4e2v90c8mbh18p2hdy3e90g
  text: |-
    ### Decision from the user (2026-10-08)
    "so your 'query' notions seem to be duplicative and do not honor the filter -- the .tasks thing how about you just use the filter, right now you have mixed prop and expression mess". Thus every task list takes only the filter expression; the scoping arguments go away.
  timestamp: 2026-10-08T15:41:55.596876+00:00
- actor: claude-code
  id: 01m4e542fnh3mgjgm7vdcwdnqr
  text: |-
    Research done. Findings and design decisions:
    - One mechanism: `VirtualTag.hiddenUnlessNamed` becomes `[.deleted, .done]`. `TaskFilter` stays the only test. `TaskSelection` loses `excludesDone`, the scoping atoms, `init(for: TasksArguments)`, `init(searchFiltering:)` and `excludesDoneByDefault`. `FilterExpr.keepsDoneTasksByDefault` goes away.
    - Decision "names a column": it becomes part of the generic rule. `FilterExpr.names(.done)` is true for a `#DONE` atom (any case, also a tag URL with local id DONE) and for each column atom (`%x` or a column URL), at any depth, also under a NOT. `namesColumn` goes away (its only user was `keepsDoneTasksByDefault`). Its tests change to `names(.done)`.
    - Decision per tag: each hidden tag is revealed only by its own name. Thus `!#DELETED` gives the live tasks that are not done (before: also the done tasks, through `keepsDoneTasksByDefault`). The NodeQueryTests case `!#DELETED` changes its expected titles for this reason.
    - Decision DONE on a tombstone: `DONE` applies only to a live task in the terminal column, the same as READY/BLOCKED/BLOCKING apply only to live tasks. Thus `#DELETED` still lists a tombstone in the done column, with no coupling between the two hidden tags.
    - DONE vs READY/BLOCKED/BLOCKING: no change. READY and BLOCKING already need "not done". Note: the premise "a done task is never BLOCKED today" is not true. BLOCKED is `isLive && !isReady`; a done task with an open dependency is BLOCKED today, and the Rust `virtual_tags.rs` BLOCKED strategy also does not test the own column of the task. I keep that behavior (no change), so DONE and BLOCKED can both show on such a task.
    - Holders: `Column.tasks`, `Actor.tasks`, `Tag.tasks` get the same defaults. The holder becomes one scope atom (`%`, `@` or `#` with the URL of the node) ANDed with the filter, so `Column.tasks(filter: f)` is the same as `Board.tasks(filter: "%<column> && (f)")`. Thus the done column still lists its tasks (the column atom names DONE), and `Actor.tasks`/`Tag.tasks` now leave out done tasks unless the filter names `#DONE`. `isHolder(of:)` goes away.
    - nextTask keeps its `READY` virtual-tag test (a scope atom `#READY` would also match a real tag `ready`).
    - ChangeFilter (history and changes) uses `TaskFilter`, so a task filter now also leaves out the updates of a task that is done now, unless the filter names `#DONE` or a column.
    - BoardSummary does not use a task selection (counts only); no change.
    - KanbanTool description, CLI help (`Sources/kanban/KanbanMain.swift`) and README have no example with the removed arguments; no text change is needed there.
    - No separate corpus file exists; `FilterCompatibilityTests` is the corpus. `#DONE` cases go into a new section there.
  timestamp: 2026-10-08T16:21:40.981077+00:00
- actor: claude-code
  id: 01m4e63kqyvqh5xssybhmmz4s7
  text: |-
    ## Decisions

    1. **"Names a column" is not a separate trigger.** A `%` atom or a column URL names `DONE` in `FilterExpr.names(_:)`. Thus one path (`VirtualTag.hiddenUnlessNamed = [.deleted, .done]`) decides the default for `DELETED` and `DONE`. `namesColumn` and `keepsDoneTasksByDefault` are removed.
    2. **Each hidden tag is revealed only by its own name.** `!#DELETED` no longer shows the done tasks. `#DONE || !#DONE` lists all live tasks.
    3. **`DONE` is live-only** (`isLive && isDone`). A tombstone in the done column has `DELETED`, not `DONE`. Thus `#DELETED` lists it and `#DONE` does not.
    4. **`DONE` does not change `READY`, `BLOCKED`, or `BLOCKING`.** The premise "a done task is never BLOCKED" is false in the current code: `BLOCKED` is `isLive && !isReady`, the same as the Rust strategy. A done task with an open dependency has `[BLOCKED, DONE]`. I kept this behavior and tested it (`doneTaskWithOpenDependencyIsBlocked`).
    5. **Holder fields.** `Column/Actor/Tag.tasks(filter)` is `Board.tasks` with `<atom of the node URL> && (<filter>)`. A column atom names `DONE`, so the done column lists its tasks. An actor or a tag lists a done task only when the filter names `#DONE`. This changes the old behavior, where an actor or a tag listed done tasks.
    6. **`nextTask`** keeps the `READY` predicate, so it never gives a done task or a tombstone.
    7. **`history` / `changes`** use the same `TaskFilter`: a tag filter leaves out the updates of a done task; `#DONE` keeps them.
    8. **Text.** The KanbanTool description, the CLI help and the README had no example with the removed arguments, so they did not change. No corpus lists the virtual tags.

    ## Other schema arguments that select by a state the filter can express (not removed)
    - `history` and `changes`: `type`, `node`, `actor`, `derived`. `node` can partly be a `^id` filter, but `type`, `actor` (the actor of the transaction, not the assignee) and `derived` select changes, not tasks, so the task filter cannot express them fully. ^sey06m9 covers these.
    - `boards(enabled:)` selects boards, not tasks. It is not a task list.
    - `searchTasks(query:)` is a ranking input, not a state.

    ## Rules that I interpreted
    - "No dead code": the `slot` stored field of `ColumnObject`, `ActorObject`, `TagObject` became assign-only after `isHolder` was removed. I removed the field and gave each type an init that ignores the slot argument of `SlotNodeObject.init`. I removed `BoardView.orderedTasks(where:)`.
    - The removed-argument test checks the text `does not have argument`, because GraphQL validation (not a KanbanError) rejects the argument.
  timestamp: 2026-10-08T16:38:54.462032+00:00
- actor: claude-code
  id: 01m4e63rq36s8ayrptdm9ywf90
  text: |-
    ## Step record: implement

    **TDD notes**
    - The new DONE tests (VirtualTagsTests, FilterEvaluatorTests `namesDone`/`doneTag`, FilterCompatibilityTests DONE section, NodeQueryTests `doneTaskHasDoneVirtualTag` and `taskListsTakeOnlyTheFilter`, TaskOperationTests `moveTaskIntoAndOutOfDone`) failed on an assertion first.
    - The registry-order test passed on its first run, because the `done` enum case stub already existed for the build.
    - The two new HistoryTests (`historyDoneFilterKeepsDoneTask`, `historyAfterMoveOutOfDoneFollowsOpenTask`) were written after the implementation. I made the forward test fail by a temporary change (`hiddenUnlessNamed = [.deleted]`), then restored the code.
    - The converted tests (`excludeDone: false` to `#DONE || !#DONE`) keep their results; their RED was the removal of the arguments.

    **Evidence**
    - `swift build --build-tests`: only the accepted mlx "missing creator" warning.
    - `timeout 120 swift test --skip-build` 3 times: 984 tests in 68 suites passed each time.
    - IntegrationTests `swift build --build-tests && swift test`: 2 tests passed; only the accepted warning.
    - `periphery scan ...`: "No unused code detected."
    - `.build/debug/kanban --schema`: `tasks(filter: String, first: Int = 10, after: String): TaskConnection` and 3 x `tasks(filter: String): [Task!]`. No `column`, `tag`, `assignee`, `excludeDone` or `deleted` on a task list.
    - plan.md: §3.3 rule 3, §4.1 SDL (`tasks`, `virtualTags`), §6 table (virtual tags, `nextTask`), §6.3 (`#tag` row, `%` note, "Scoping arguments" replaced by "Only the filter selects" and "Default selection"), §6.7 filters, §11 test lists, §12 item 22.

    The task stays in doing. Nothing is committed.
  timestamp: 2026-10-08T16:38:59.555300+00:00
- actor: claude-code
  id: 01m4e6hpkkzdewebqzw0xg0063
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (bdb14ec); 1 finding (1 confirmed, 1 refuted) — Tests/FoundationModelsKanbanTests/Undo/HistoryTests.swift:91 `reuse/reuse`
    - next: implement the open finding in the "Review Findings (2026-10-08 11:43)" section, then review again. The task stays in review.
  timestamp: 2026-10-08T16:46:36.147474+00:00
- actor: claude-code
  id: 01m4e6hzz0j8j386c6kb2n4md8
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 8 source files, tests (Derived, Filter, GraphQL, Mutations, Tool, Design, Undo), plan.md; removed the public column, tag, assignee and excludeDone arguments; added DONE
    - test: green — root swift test 3 runs, 984 passed each (8.2 s, 7.6 s, 7.5 s); IntegrationTests 2 passed; schema checked; build warnings only the 2 accepted kinds
    - commit: bdb14ec (footer amended to give the exact excludeDone replacement)
    - review: findings — Tests/FoundationModelsKanbanTests/Undo/HistoryTests.swift:91
  timestamp: 2026-10-08T16:46:45.728772+00:00
- actor: claude-code
  id: 01m4e6qq9fz2y4t3wbcb42r9zb
  text: |-
    Finding `HistoryTests.swift:91` `reuse/reuse` is fixed.
    - New helper `HistoryTests.session(inRepoAt:running:)` is the one place that runs `ChangeBuilderTests.baseSession`, computes `ChangeBuilderTests.refs` of the fixture task, and runs the fields from a closure `(CaseRefs) -> [String]`.
    - `completedSession(inRepoAt:)` and `taggedSession(inRepoAt:running:)` keep their names. Each one now only calls `session`. `taggedSession` puts the tag field in front of the fields. Its closure now gets the `CaseRefs` (not the ULID), so a caller can make `deleteTaskField(refs)` and `addCommentField(refs)`.
    - The same flow (base session, refs, run fields) was also open-coded in 5 other tests of the file: `historyFilterKeepsMatchingTasksAndComments`, `historyDeletedFilterKeepsDeletedUpdate`, `historyTagFilterLeavesOutDeletedTask`, `historyAfterUndeleteFollowsLiveTask`, `historyWithoutDerivedLeavesOutDerivedUpdates`. They now use `session` or `taggedSession`. The order of the fields and the point where the refs are computed (after the base setup, before the first field) did not change.
    - The other test files that the last commit changed do not have this flow. `baseSession` plus `HistoryTests.run` also shows in UndoTests, MergeTests and ReplayPropertyTests, but the last commit did not change them, so they stay as they are.
    - No `#expect` or `#require` line changed (checked with `git diff -U0 -- Tests`).
  timestamp: 2026-10-08T16:49:53.455591+00:00
- actor: claude-code
  id: 01m4e6qthzv56fk669r798cwmk
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/Undo/HistoryTests.swift (52+/53-). `swift build --build-tests`: only the accepted mlx "missing creator" warning. `timeout 120 swift test --skip-build` 3 times: 984 tests in 68 suites passed each time (7.58 s, 7.62 s, 7.59 s). No line is longer than 120 characters. No assertion changed.
    - next: review. The finding of "Review Findings (2026-10-08 11:43)" is marked [x]. The task stays in doing. Nothing is committed.
  timestamp: 2026-10-08T16:49:56.799296+00:00
depends_on:
- 01M4C30V5Z7M6ERBZ8YD8WWDGY
position_column: doing
position_ordinal: '80'
title: 'Task lists take only the filter: remove column, tag, assignee, excludeDone; add #DONE'
---
## What
A person decided on 2026-10-08: "the .tasks thing how about you just use the filter, right now you have mixed prop and expression mess". A task list selects its tasks only through the filter expression and the derived tags. ^d8wwdgy removes `deleted` and adds `#DELETED`, with a generic rule: a list leaves out a state by default, unless the filter names the tag of that state. This task finishes the job.

- `Board.tasks` becomes `tasks(filter: String, first: Int = 10, after: String): TaskConnection`. Remove the `column`, `tag`, `assignee` and `excludeDone` arguments. Remove `TaskSelection`'s scoping-atom code and the argument plumbing in `Schema.swift` (`TasksArguments`) and `QueryResolvers.swift`. The filter already has `%column`, `#tag` and `@actor`.
- Add a `#DONE` derived tag: true for a task in the terminal column (the same test that readiness uses for "done"). A list leaves out the done tasks by default. When the filter names `#DONE` or a column (as now), the list includes them and the filter decides. Use the one generic mechanism from ^d8wwdgy for both `#DONE` and `#DELETED`.
- `nextTask(filter)`, `searchTasks(query, filter, first)`, and the `tasks(filter)` fields of `Column`, `Actor` and `Tag` use the same selection and the same defaults.
- `KanbanTool` description, the CLI help, and any example query that uses the removed arguments must change to filter expressions.
- Update plan.md §4.1 and §6.3 (remove "Scoping arguments"; state the default rule and the derived-tag list).

## Acceptance Criteria
- [x] The schema of every task list has only `filter` (and paging where it had paging); `kanban --schema` shows no `column`, `tag`, `assignee`, `excludeDone` or `deleted` argument on a task list.
- [x] `#DONE` lists the done tasks; `%done` still lists them; a list with no filter leaves out done and deleted tasks.
- [x] One mechanism decides the default for `#DONE` and `#DELETED`.

## Tests
- [x] Change every test that uses the removed arguments to filter expressions, with the same expected results; add tests for `#DONE`, `#DONE || #x`, `!#DONE`, and a list with no filter.
- [x] Run the full `swift test`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-08 11:43)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 22 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `Tests/FoundationModelsKanbanTests/Undo/HistoryTests.swift:91` `reuse/reuse` — New helper taggedSession repeats the shape of the existing completedSession helper: run baseSession, then run a list of mutation fields in one session. The only difference is the extra tag field. Writing a parallel helper leaves two copies of the setup-and-run logic that can drift apart. It is a near-match that should have been generalized. Generalize `completedSession` so it takes the fields as a closure, with an option to tag the fixture first, and derive both cases from that one helper. Or make `completedSession` call `taggedSession` with a tag-free flag. Keep one place that builds the base session and runs fields.
