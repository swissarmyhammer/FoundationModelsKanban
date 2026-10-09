---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gt0pdkfskszvhv3m8ftphh
  text: |-
    Research done.
    - Each mutation that makes a tag goes through `WorkingCopy.addNode`, which calls `LocalRef.checkSlugIsNotReserved()` (Tags/TagSlug.swift). This covers addTag, renameTag (new target), the tags of addTask/updateTask/tagTask (`tagRefs` -> `addTag` -> `ensureLiveTag`), and `#markers` (`addMarkerTags`). Plan: extend this one check for a tag slug that is the same as a `VirtualTag` raw value (ignore case). New error `KanbanError.virtualTagName(tag:)` with the code INVALID_TAG_NAME and a message that names the virtual tag.
    - `ensureLiveTag` only calls `addNode` for an unknown tag. Thus a tag node that an old log already has is not refused (the same rule as the slug `board`).
    - `addMarkerTags` (GraphQL/TaskMutations.swift): skip a marker whose slug names a virtual tag, so that the marker stays a filter word only.
    - Filter: `FilterCompiler.tagTest(named:)` ORs the virtual tag and the real tag. Change: when the name is a virtual tag name, the test reads only the virtual tag. `#kanban://k/tag/<slug>` gives the same local name (plan §6.3: "the same as #slug"), so `Tag(done).tasks` of an old real tag `done` also gives the virtual tag tasks.
    - updateTag does not change a slug, so it is not refused (instruction from the dispatcher and plan §3.2 rule for `Board`).
    - Test fixture: `KanbanGraphTests.writeFixture` has one column `todo` (it is the terminal column). The old-log test adds a column `done` with a larger order, so that the fixture task in `todo` is open.
  timestamp: 2026-10-09T17:05:19.283939+00:00
- actor: claude-code
  id: 01m4gw7kgyh450ghmhy4y8w1be
  text: |-
    Implementation landed (TDD: RED was a compile failure for the missing error case, then 28 failing expectations; GREEN after the change).
    - `KanbanError.virtualTagName(tag:)` (INVALID_TAG_NAME). The message names the virtual tag, for example: The slug "deleted" is the name of the virtual tag DELETED, and the filter #DELETED matches only the virtual tag, so a tag cannot have it. Use a tag name that gives a different slug.
    - `LocalRef.checkSlugIsNotReserved()` also refuses a tag slug that is a virtual tag name. No second check path: addNode calls it, so addTag (name or id), the renameTag target, and the tags of addTask/updateTask/tagTask are refused. Column and actor slugs such as `done` are still accepted.
    - `addMarkerTags` skips a marker that names a virtual tag, so `#BLOCKED` makes no tag and no tag patch.
    - `FilterCompiler.tagTest(named:)`: a virtual tag name (and the tag URL with that slug) matches only the virtual tag. The dead helper `isTagged(taskAt:with:)` is removed.
    - Choices: updateTag is not refused (display name only, the dispatcher rule and plan §3.2). A tag node that the graph already has (old log) is not refused by addTag/tagTask, the same as the slug `board`. `Tag(done).tasks` of an old real tag `done` gives the virtual tag tasks (plan §6.3: `#kanban://k/tag/<slug>` is the same as `#slug`).
    - Changed an existing test: FilterEvaluatorTests "A tag atom ignores the case of a real tag" used a real tag `ready` and expected `#READY` to match it. That is the old rule. It now uses `bug`/`#BUG`, and a new unit test checks that `#READY` matches only the virtual tag.
    - Test reuse: `ReservedSlugTests.Refusal.field(on:naming:id:)` takes the name and the id, so `VirtualTagNameTests` reuses the same fields.
    - plan.md §6 (Virtual tags row), §6.1, and the §6.3 `#tag` row have the rule.
  timestamp: 2026-10-09T17:44:02.846187+00:00
- actor: claude-code
  id: 01m4gw7pkjy55vn5hqdatjcd3p
  text: |-
    ### implement — changed
    - evidence: 14 files — Sources/FoundationModelsKanban/{Tags/TagSlug.swift, GraphQL/Errors.swift, GraphQL/TaskMutations.swift, GraphQL/TagMutations.swift, GraphQL/TaskOperationMutations.swift, GraphQL/ColumnActorMutations.swift, Filter/FilterEvaluator.swift}, Tests/FoundationModelsKanbanTests/{Tags/VirtualTagSlugTests.swift (new), Mutations/VirtualTagNameTests.swift (new), Mutations/ReservedSlugTests.swift, GraphQL/KanbanErrorTests.swift, Filter/FilterEvaluatorTests.swift}, plan.md. `swift build --build-tests`: only the accepted SwiftPM "missing creator" warning. `swift test`: 1089 tests in 78 suites passed, 0 issues.
    - next: /review
  timestamp: 2026-10-09T17:44:06.002788+00:00
position_column: doing
position_ordinal: '80'
title: Refuse tag names that are the same as a virtual tag
---
## What
A real tag whose slug is the same as a virtual tag (`deleted`, `blocked`, `ready`, `done`, `conflict`, `high`, `medium`, `low`, and the others in `Sources/FoundationModelsKanban/Derived/VirtualTags.swift`) gives wrong results. `#kanban://k/tag/<slug>` also matches the virtual tag (`Filter/FilterEvaluator.swift:172-175`, `:431-432`), and `Tag.tasks` uses that atom (`GraphQL/QueryResolvers.swift:408-409`). Thus `addTag("Deleted")` then `Tag(deleted).tasks` gives every tombstone.

- `addTag`, `renameTag`, `updateTag` (name change), and the tags that `addTask`/`updateTask`/`tagTask` and `#markers` make: refuse a name whose slug is the same as a virtual tag name (ignore case). Give `INVALID_TAG_NAME` with a message that names the virtual tag.
- A `#marker` in a body that names a virtual tag does not make a real tag (it stays a filter word only).
- Replay never refuses a log. An old log that holds a real tag `done`, `high` or `low` still loads. That tag node stays and is listed in `tags`. The filter atom `#done` matches the virtual tag only, not the real tag.
- Update plan.md §6 (virtual tags) and §6.1 with this rule.

## Acceptance Criteria
- [x] `addTag(name:"Deleted")` and `addTag(name:"blocked")` give `INVALID_TAG_NAME`.
- [x] `addTask(tags:["done"])` gives `INVALID_TAG_NAME` and writes no patch.
- [x] A body with `#BLOCKED` makes no tag.
- [x] A board whose log holds a real tag `done` loads with no error. `tags` lists the tag `done`. `tasks(filter:"#done")` gives only the tasks in the done column, not the tasks that have the real tag `done`.

## Tests
- [x] Tests in `Tests/FoundationModelsKanbanTests/Tags/` and `Tests/FoundationModelsKanbanTests/Mutations/`.
- [x] A test that writes a log with a real tag `done` (and a task with that tag that is not in the done column) to a temporary board, opens the board, and checks the last acceptance criterion.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.