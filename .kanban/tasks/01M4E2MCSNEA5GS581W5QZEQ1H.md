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
depends_on:
- 01M4C30V5Z7M6ERBZ8YD8WWDGY
position_column: todo
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
- [ ] The schema of every task list has only `filter` (and paging where it had paging); `kanban --schema` shows no `column`, `tag`, `assignee`, `excludeDone` or `deleted` argument on a task list.
- [ ] `#DONE` lists the done tasks; `%done` still lists them; a list with no filter leaves out done and deleted tasks.
- [ ] One mechanism decides the default for `#DONE` and `#DELETED`.

## Tests
- [ ] Change every test that uses the removed arguments to filter expressions, with the same expected results; add tests for `#DONE`, `#DONE || #x`, `!#DONE`, and a list with no filter.
- [ ] Run the full `swift test`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.