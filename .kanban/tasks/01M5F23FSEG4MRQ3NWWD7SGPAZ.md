---
assignees:
- claude-code
depends_on:
- 01M5F234JM2BZEQ1TDMJK3FC4G
position_column: todo
position_ordinal: '8180'
title: 'KANBAN-5: KanbanGraph conforms to GraphQLEndpoint and KanbanTool to GraphQLEndpointTool'
---
## What
KANBAN-5 (TestudoApp/features/packages/foundationmodels-kanban.md) under EXTRAS-9 rev 2, rules 1, 3, 4 and 5 (D115).

- `KanbanGraph` (Sources/FoundationModelsKanban/Tool/KanbanGraph.swift) conforms to the Extras `GraphQLEndpoint`: `name` = `"kanban"`, `version` = `"1"`, `scope` = `.sessionFolder`, `schema` = the printed SDL. `execute(query:variables:operationName:viewer:)` and `subscribe(...viewer:)` wrap the existing engine calls and give JSON text.
- `KanbanTool` (Tool/KanbanTool.swift) conforms to `GraphQLEndpointTool`. `graphQLEndpoints` = `[graph]`: the same instance and serial gate that the tool uses. The endpoint (and later its ChangeLog) is made once per port/folder, not once per tool copy, so a forked or copied KanbanTool must give the same graph. The tool keeps its one-document input, answers through `GraphQLTool.answer`, and calls the graph with `viewer: nil`.
- Viewer (EXTRAS-5; agreed in EXTRAS-9 rev 2): `nil` and `.userDevice` see and edit all boards. An `.external` viewer reaches only the board of the call's folder. Every other board is refused, for reads and writes: `board:` given as a path, key or URI, `boards`, `moveTask(board:)`, `copyTask`, `collectBoards`, and cross-board undo.
- Single item (rule 5): the singular noun takes `id:`; other keys are aliases. Check `task(...)`, `column`, `tag` and `actor` and add `id:` where it is missing.

## Acceptance Criteria
- [ ] `KanbanGraph: GraphQLEndpoint` with name `kanban`, version `"1"` and scope `.sessionFolder`
- [ ] `KanbanTool: GraphQLEndpointTool`, and `graphQLEndpoints` returns the tool's own graph (the same instance, not a copy), also for a copied or forked tool
- [ ] An `.external` viewer cannot read or write another board by any board ref form. The refusal is a coded error that does not reveal whether the board exists.
- [ ] `nil` and `.userDevice` viewers behave as today
- [ ] Single-item root fields take `id:`
- [ ] No ACP dependency is added

## Tests
- [ ] Tool gives endpoint: name, version and scope (EXTRAS-9 rule 11)
- [ ] Viewer: an external viewer works on its own board and is refused on a sibling board by path, key and URI, and through `boards`, `moveTask(board:)`, `copyTask` and `collectBoards`
- [ ] execute and subscribe through the protocol give the same JSON as the direct calls