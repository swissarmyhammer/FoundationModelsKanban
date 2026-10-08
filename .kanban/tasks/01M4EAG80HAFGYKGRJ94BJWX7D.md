---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: 'Send the ACP agent plan through ToolContext when a task changes; add #HIGH, #MEDIUM, #LOW derived tags'
---
## What
A person asked for this on 2026-10-08. The kanban tool must comply with the ACP agent plan (https://agentclientprotocol.com/protocol/v2/agent-plan). FoundationModelsExtras already has the API: `PlanSnapshot` (`id`, `entries`; `Entry(content:priority:status:)`; `Priority` high/medium/low; `Status` pending/in_progress/completed/cancelled) and `ToolContext.progress(_ detail: String, plan: PlanSnapshot?)` (commit ee4a798; the current pin 5c1c638 includes it, so no pin change). `ToolContext.current` is a task-local that is set while a host runs a tool call. The model never gets the plan; it goes to the client.

Rules:
- **When:** after a tool call (`KanbanTool.call`, and any other tool entry point) commits a transaction that changes at least one task (add, update, move, complete, assign, tag, delete, undelete, undo, redo), and `ToolContext.current` is not nil, post one `progress` event with the plan of each board that the transaction changed. A query, or a mutation that changes no task, sends nothing. With no `ToolContext.current` (for example the CLI or a direct `execute`), send nothing and do no extra work.
- **Plan id:** the board key, so that each board is one plan and an update replaces it.
- **Entries:** the full list, never a partial list: the live tasks of the board in board order (column order, then ordinal). `content` is the task title.
- **Status:** a task with `DONE` → `completed`; a task in the first column → `pending`; any other live task → `in_progress`. Deleted tasks are not in the plan.
- **Priority:** add three derived tags, `HIGH`, `MEDIUM`, `LOW`, from the place of a task in board order among the open (not `DONE`) live tasks: the first third is `HIGH`, the second third `MEDIUM`, the rest `LOW` (round so that a board with 1 or 2 open tasks gives `HIGH` first). A done task gets `LOW` in the plan and no priority tag. Use the same derived-tag code as `READY`, `BLOCKED`, `DONE` (`Derived/VirtualTags.swift`), so `#HIGH` etc. work in filters and show in `virtualTags`. They are not "hidden unless named" tags.
- **Detail:** a short text line for the model, for example "3 of 7 tasks done", from `BoardSummary`.

Files: `Sources/FoundationModelsKanban/Derived/VirtualTags.swift`, `Tool/KanbanTool.swift` (and where the commit result is known, for example `Tool/KanbanGraph.swift`), a new file for the plan builder (for example `Tool/AgentPlan.swift`), plan.md (a new section on the agent plan, and the derived-tag list).

## Acceptance Criteria
- [ ] A tool call that adds or moves a task under a bound `ToolContext` posts one `.progress` event whose `plan` has the board key as id and one entry for each live task in board order, with the title as `content` and the status and priority of the rules.
- [ ] A query, a mutation that changes no task, and a call with no `ToolContext.current` post nothing.
- [ ] `#HIGH`, `#MEDIUM`, `#LOW` appear in `virtualTags` and select the right tasks in a filter; they change when a task moves.

## Tests
- [ ] Unit tests for the plan builder (status and priority mapping, ordering, rounding for 1, 2, 3, and 7 open tasks).
- [ ] Tool tests that bind a `ToolContext` with a recording sink (see how FoundationModelsExtras tests do it, for example `ToolContextTests`) and check the posted events.
- [ ] Derived-tag tests for `HIGH`, `MEDIUM`, `LOW`, including the inverse (a task that moves changes tier).
- [ ] Run the full `swift test`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.