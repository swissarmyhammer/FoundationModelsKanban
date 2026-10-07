---
comments:
- actor: wballard
  id: 01m4c1hmyfjvwq4jt9zsqay5wt
  text: |-
    Research done. Findings:
    - Read side is complete: `RefResolver` follows the rename redirect for a tag slug, name, or URI; `Graph.tagSlots(of:)`, `boardTagSlots`, and the filter `#x` follow it too. `TagObject.color` gives the auto color when no color is stored.
    - `addTask(tags:)` already follows the redirect through the private `WorkingCopy.addTag(_:at:)` in TaskMutations.swift. The tag mutations reuse that logic, so I move it to the new TagMutations.swift and give it a `set` part and a body.
    - delete/undelete reuse `changeDeleted(to:ofType:as:context:_:)` with `.tag`; the resolver gives the end of the rename chain, so `deleteTag(bug)` after `bug -> defect` deletes `defect`.
    - `renameTag(to:)` is taken as the literal slug (plan §6.2: `set renamedTo = tag/<to>`). If `to` were resolved through its redirect, no cycle could be made and `TAG_RENAME_CYCLE` would be unreachable. `from` follows the redirect.
    - Rust semantics that changed: Rust rename and delete rewrote task bodies; the new design changes no task (plan §6.1, §6.2). Rust rename to an existing name failed; here it is a merge. The ported tests assert the new semantics.
    - No `board` input field: the column and actor mutations do not have it either; cross-repo is a separate task.
  timestamp: 2026-10-07T20:40:42.703403+00:00
- actor: wballard
  id: 01m4c24phfn197cskwnc8phc4g
  text: |-
    Implementation landed (TDD: 27 tests failed on assertions first, then passed).
    - New `GraphQL/TagMutations.swift`: `addTag`, `updateTag`, `deleteTag`, `undeleteTag`, `renameTag`, registered in `PublicSchema`.
    - `addTag` writes `set name, color` (auto color of the slug when no color is given) and the body diff. On a slug that the board has, it follows the redirect and writes nothing; a tombstone at the end of the chain gets `delete: false`.
    - The tag-live logic moved from the private `addTag(_:at:)` of TaskMutations.swift to the shared `WorkingCopy.ensureLiveTag(_:setting:body:at:)`. `addTask` tags use it with the name only, so their patches do not change.
    - `renameTag`: `from` follows the redirect; `to` is the literal slug. A new target gets `set name` (the new name), `color` (the shown color of the old tag), and the body of the old tag. The cycle check walks `renamedTo` after the write and gives the slug path, for example `defect -> bug -> defect`. A rename to the same slug writes nothing.
    - `TagNode.resolvedColor` (AutoColor.swift) is now the one source of the shown tag color; `TagObject.color` uses it.
    - Test reuse: made `CommentTests.nodeField` (was `commentField`), `run`, `failure(of:in:)`, the new `respond(toQueryOf:selecting:on:)`, `AddUpdateTaskTests.bodyMutation/addTask(with:)/firstTask/idSelection`, and `ColumnActorTests.body/bodyJSON/bodyVariables/emptySlugName/red/green/bodyPatch/setting(name:color:)` internal.
    - Gotcha: the fixture column `todo` is the terminal column, so a `tasks(filter:)` query needs `excludeDone: false` to see the fixture tasks.
  timestamp: 2026-10-07T20:51:06.927618+00:00
- actor: wballard
  id: 01m4c24s3b1xvbgj1rnknwaf29
  text: |-
    ### implement — changed
    - evidence: `swift test --filter TagMutationTests` 27/27 pass; `swift test` 697 tests in 41 suites pass, no compiler warnings; periphery 3.8.0 (native build, --retain-public, tests excluded from report): no unused code. Files: Sources/FoundationModelsKanban/GraphQL/TagMutations.swift (new), GraphQL/ColumnActorMutations.swift, GraphQL/QueryResolvers.swift, GraphQL/Schema.swift, GraphQL/TaskMutations.swift, Tags/AutoColor.swift, Tests/FoundationModelsKanbanTests/Mutations/TagMutationTests.swift (new), Mutations/AddUpdateTaskTests.swift, Mutations/ColumnActorTests.swift, Mutations/CommentTests.swift.
    - next: /review
  timestamp: 2026-10-07T20:51:09.547595+00:00
- actor: wballard
  id: 01m4c2dk8hsby0wr1z3bwwjqqp
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (fec7aa0). 0 findings, 0 confirmed, 2 refuted. The engine examined 10 files. A .reviewignore rule excluded 4 .kanban/ files.
    - next: none. The task is in done.
  timestamp: 2026-10-07T20:55:58.481368+00:00
- actor: wballard
  id: 01m4c2dsefxnka6nrbjfgdxchf
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 10 files (GraphQL/TagMutations.swift, ColumnActorMutations, QueryResolvers, Schema, TaskMutations, Tags/AutoColor, TagMutationTests, AddUpdateTaskTests, ColumnActorTests, CommentTests)
    - test: green — swift test, 697 passed, 0 warnings
    - commit: fec7aa0 (message amended from 91b4004 for accuracy; content unchanged)
    - review: clean — 0 findings
  timestamp: 2026-10-07T20:56:04.815671+00:00
depends_on:
- 01M4B4002GZV6E43G5CQ74BJNZ
position_column: done
position_ordinal: a080
title: 'Mutations: tags and tag rename'
---
## What
Tag mutations. The basis is plan.md §4.2 and §6.2. Comment mutations are in a separate task.
- `addTag`/`updateTag`/`deleteTag`/`undeleteTag(id, name, color, body)`: `addTag` is idempotent on slug; `updateTag` does not change the slug; auto color when no color is given; tag name rule (`INVALID_TAG_NAME`).
- `renameTag(from!, to!)`: new tag `set` (copied values, only if `to` does not exist), and old tag `set renamedTo = tag/<to>`. A rename to an existing slug is a merge (only the redirect). A rename that makes a cycle gives `TAG_RENAME_CYCLE`.
- All refs to a redirected slug follow the redirect (`addTag` returns the target and writes nothing, `updateTag`, `deleteTag`, `renameTag`).

## Acceptance Criteria
- [x] After `renameTag(bug → defect)`, tasks with `bug` show `defect`, `#bug` and `#defect` both match, and `addTask(tags: ["bug"])` writes an edge to `defect`.
- [x] `deleteTag(id: "bug")` after the rename deletes `defect`; a rename cycle gives `TAG_RENAME_CYCLE`.
- [x] A rename to an existing tag writes only the redirect.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Mutations/TagMutationTests.swift`: rename, chain, merge rename, cycle refusal, undelete, plus the matching Rust dispatch tests.
- [x] Run `swift test --filter TagMutationTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.