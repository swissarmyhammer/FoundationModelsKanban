---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f71jr215znxqkn877fv2ja
  text: |-
    Research (implement):
    - KanbanGraph is the session view (one per working directory); its board is the "endpoint's own folder". KanbanTool is a struct holding the actor, so copies share the same instance.
    - KanbanGraph has `private let schema: PublicSchema`, which clashes with the protocol's `schema: String`; it gets renamed to `publicSchema`. SDL comes from the toolkit's non-throwing `API.sdl`.
    - All explicit board refs go through BoardStore: `resolution(ofBoardNamed:)` (board(id:), node(id: URI), target(of:) for every mutation board field / moveTask / copyTask / undo board+boards / txn copies), `listedViews` (boards), `reachableTargets` (repairLinks reach), `loadedTargets(withKey:)` (cross-board undo), and collectBoards reads source folders by path directly.
    - Implicit cross-board reads (dependsOn, remote assignees, link checks, subscription events) come from RelatedBoards. `.unavailable` answers every request (not found / empty), so the run loop ends with no load.
    - Plan: a `BoardReach` value made from the GraphQLViewer (nil/userDevice -> all boards, external -> own board). For own-board reach, KanbanGraph gives the run a loader that returns `.unavailable` (no other board is loaded or read), BoardStore refuses every ref that does not name the current board (storedRef .board covers key, board IDs, old names; plus a path to the board folder) with a new KanbanError `UNREACHABLE_BOARD` whose message is the same whether the board exists, and refuses `boards`, `collectBoards` and `repairLinks(reach:)`. Subscription events keep `.unavailable` for own-board reach in `replace(with:)`.
    - Single item: Board.task(id:) exists (root `task` moves into board via the root container). There is no singular column/actor/tag field; adding Board.column(id:), Board.actor(id:), Board.tag(id:) with ref aliases.
  timestamp: 2026-10-21T12:30:12.738320+00:00
- actor: claude-code
  id: 01m5f7z6rq0r7j600dcpeqaqat
  text: |-
    Implementation landed (not committed):
    - KanbanGraph: GraphQLEndpoint (nonisolated name "kanban", version "1", scope .sessionFolder, schema = publicSchema.sdl; the private `schema` property is now `publicSchema`). New public execute/subscribe(..., viewer:); the old no-viewer forms delegate with viewer nil. Viewer -> BoardReach (new GraphQL/BoardReach.swift), threaded through respond/startSubscription -> SchemaRun -> runCall -> CommitSession.run(reaching:) -> BoardStore(reaching:).
    - Own-board reach: the run's related-board loader returns `.unavailable` (no other board is loaded or read, so dependsOn/assignees/links of other boards read as unresolved); BoardStore.resolution(ofBoardNamed:) accepts the board's own names (storedRef .board) and a path to its folder, else throws UNREACHABLE_BOARD before any lookup; `boards`, `repairLinks(reach: true)` and `collectBoards` (checked before it reads any source path) throw UNREACHABLE_BOARD; subscription events keep `.unavailable` in replace(with:). Cross-board undo is refused through target(of:) of the other key.
    - New KanbanError cases unreachableBoard(reference:) / unreachableBoards(field:), code UNREACHABLE_BOARD; the message has no word on whether the board exists (tests compare the sibling response with a missing-board response).
    - KanbanTool: GraphQLEndpointTool, graphQLEndpoints = [graph], calls execute(viewer: nil).
    - Rule 5: Board.column(id:), Board.actor(id:), Board.tag(id:) added (root forms move into board), aliases = ref aliases + slug + name; BoardView.object(for:ofType:) generalizes task(for:).
    - Behavior note: adding Board.column makes the root typo `columnz` a tie between column/columns (rewrite leaves it, validation then reports it). NameRewriteTests row changed to the unambiguous typo `colunns`.
    - Docs: README section 3 and plan.md §4.4 name the endpoint and UNREACHABLE_BOARD.
  timestamp: 2026-10-21T12:46:23.511066+00:00
- actor: claude-code
  id: 01m5f7zbpqkpvpm8qzcndxfr7e
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` clean (only the known mlx "missing creator" note); full `swift test`: 1722 tests in 143 suites passed. 22 files: Sources/FoundationModelsKanban/{GraphQL/BoardReach.swift (new), GraphQL/Errors.swift, GraphQL/Schema.swift, GraphQL/QueryResolvers.swift, GraphQL/FieldAliases.swift, GraphQL/SchemaDescription.swift, GraphQL/CollectBoardsField.swift, GraphQL/RepairLinksField.swift, Tool/KanbanGraph.swift, Tool/KanbanTool.swift, Tool/Commit.swift}; Tests/FoundationModelsKanbanTests/{Tool/KanbanEndpointTests.swift (new), CrossRepo/ViewerReachTests.swift (new), GraphQL/SingleItemFieldTests.swift (new), GraphQL/KanbanErrorTests.swift, GraphQL/NameRewriteTests.swift, Tool/CommitSessionTestRun.swift}; README.md; plan.md
    - next: /review
  timestamp: 2026-10-21T12:46:28.567536+00:00
- actor: claude-code
  id: 01m5f82zyc7m1xyxmycd2bsj17
  text: |-
    ### test — green
    - evidence: `swift test` — 1722 tests in 143 suites passed, 0 failed, 0 skipped; `swift build --build-tests` in IntegrationTests/ — Build complete, 0 errors. Only warning is third-party (mlx-swift_Cmlx.bundle "missing creator for mutated node"), out of scope; no package-code warnings.
    - next: review
  timestamp: 2026-10-21T12:48:27.596283+00:00
depends_on:
- 01M5F234JM2BZEQ1TDMJK3FC4G
position_column: doing
position_ordinal: '80'
title: 'KANBAN-5: KanbanGraph conforms to GraphQLEndpoint and KanbanTool to GraphQLEndpointTool'
---
## What
KANBAN-5 (TestudoApp/features/packages/foundationmodels-kanban.md) under EXTRAS-9 rev 2, rules 1, 3, 4 and 5 (D115).

- `KanbanGraph` (Sources/FoundationModelsKanban/Tool/KanbanGraph.swift) conforms to the Extras `GraphQLEndpoint`: `name` = `"kanban"`, `version` = `"1"`, `scope` = `.sessionFolder`, `schema` = the printed SDL. `execute(query:variables:operationName:viewer:)` and `subscribe(...viewer:)` wrap the existing engine calls and give JSON text.
- `KanbanTool` (Tool/KanbanTool.swift) conforms to `GraphQLEndpointTool`. `graphQLEndpoints` = `[graph]`: the same instance and serial gate that the tool uses. The endpoint (and later its ChangeLog) is made once per port/folder, not once per tool copy, so a forked or copied KanbanTool must give the same graph. The tool keeps its one-document input, answers through `GraphQLTool.answer`, and calls the graph with `viewer: nil`.
- Viewer (EXTRAS-5; agreed in EXTRAS-9 rev 2): `nil` and `.userDevice` see and edit all boards. An `.external` viewer reaches only the board of the call's folder. Every other board is refused, for reads and writes: `board:` given as a path, key or URI, `boards`, `moveTask(board:)`, `copyTask`, `collectBoards`, and cross-board undo.
- Single item (rule 5): the singular noun takes `id:`; other keys are aliases. Check `task(...)`, `column`, `tag` and `actor` and add `id:` where it is missing.

## Acceptance Criteria
- [x] `KanbanGraph: GraphQLEndpoint` with name `kanban`, version `"1"` and scope `.sessionFolder`
- [x] `KanbanTool: GraphQLEndpointTool`, and `graphQLEndpoints` returns the tool's own graph (the same instance, not a copy), also for a copied or forked tool
- [x] An `.external` viewer cannot read or write another board by any board ref form. The refusal is a coded error that does not reveal whether the board exists.
- [x] `nil` and `.userDevice` viewers behave as today
- [x] Single-item root fields take `id:`
- [x] No ACP dependency is added

## Tests
- [x] Tool gives endpoint: name, version and scope (EXTRAS-9 rule 11)
- [x] Viewer: an external viewer works on its own board and is refused on a sibling board by path, key and URI, and through `boards`, `moveTask(board:)`, `copyTask` and `collectBoards`
- [x] execute and subscribe through the protocol give the same JSON as the direct calls