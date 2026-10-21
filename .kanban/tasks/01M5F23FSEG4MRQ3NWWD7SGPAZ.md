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
- actor: claude-code
  id: 01m5f8tz7pt0fgsdnajraewxcq
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (84aba9f): engine 3 findings (3 confirmed, 0 refuted) — Sources/FoundationModelsKanban/GraphQL/Schema.swift:1006, Sources/FoundationModelsKanban/GraphQL/Schema.swift:1010, Tests/FoundationModelsKanbanTests/Tool/KanbanEndpointTests.swift:85. Spec check against EXTRAS-9 rev 2 rule 5: 3 findings — Sources/FoundationModelsKanban/GraphQL/QueryResolvers.swift:356 (also :371, :386, :341), Sources/FoundationModelsKanban/GraphQL/SchemaDescription.swift:145, Tests/FoundationModelsKanbanTests/GraphQL/SingleItemFieldTests.swift:95.
    - checked with no finding: viewer reach (an external viewer is refused with UNREACHABLE_BOARD before any board lookup, for path, key, URI, node URI, boards, moveTask(board:), copyTask, collectBoards, repairLinks(reach: true), checkLinks and cross-board undo; related boards are not loaded, so the refusal is the same for an existing and a missing board); graphQLEndpoints returns the stored KanbanGraph actor reference, so the tool and each copy give the same instance (KanbanEndpointTests.endpointIsEngineOfTool checks `===`).
    - next: implement the 6 open items in the 2026-10-21 07:48 Review Findings section, then /review again.
  timestamp: 2026-10-21T13:01:33.302983+00:00
- actor: claude-code
  id: 01m5f8vj4bj38sn6ft3mxsyxea
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — endpoint conformance, BoardReach, single-item fields, 4 new test files
    - test: green — swift test 1722 / 143; IntegrationTests build ok
    - commit: 84aba9f
    - review: findings — Schema.swift:1006, Schema.swift:1010, KanbanEndpointTests.swift:85, QueryResolvers.swift:356, SchemaDescription.swift:145, SingleItemFieldTests.swift:95
  timestamp: 2026-10-21T13:01:52.651906+00:00
- actor: claude-code
  id: 01m5f9b43csmrer72gsyg0pxmj
  text: |-
    Review findings (2026-10-21 07:48) worked, all 6 flipped to [x]:
    - Schema.swift: new `SchemaBuilder.singleItemField(_:at:description:)` builds every single-item field of the board. task, column, actor and tag all use it, and Board.task gets a description too (SchemaDescription.boardTask).
    - QueryResolvers.swift: new `BoardView.matchingObject(for:ofType:)` returns nil when the lookup throws `.notFound`, and rethrows every other error (AMBIGUOUS_ID, UNREACHABLE_BOARD). Board.task/column/actor/tag use it, so no match gives null with no error. This also covers the root forms, which are rewritten into `board`. `BoardView.task(for:)` and `object(for:ofType:includingTombstones:)` still throw NOT_FOUND for mutations and the `tasks(after:)` cursor.
    - SchemaDescription.swift: the description now reads "Null, with no error, when no live <noun> has the id."
    - SingleItemFieldTests: itemCases now includes task. `unknownIDGivesNotFound` is replaced by `unknownIDGivesNull` (board form, exact `{"data":{"board":{"<f>":null}}}`) and `unknownIDAtRootGivesNull` (root form). New `ambiguousTaskIDGivesAnError` checks that AMBIGUOUS_ID stays an error. New helper `expectNullWithoutErrors(at:in:)`.
    - KanbanEndpointTests: `subscribeMatchesDirectCall` and `failingSubscribeMatchesDirectCall` now take `userViewers` [nil, .userDevice], the same as `executeMatchesDirectCall`.
    - Tests that pinned NOT_FOUND from task(id:) as a query were updated: QueryResolverTests.unknownTaskReturnsNull and AliasExecutionTests.taskNamesTheTask. The private `expectError` helper in AliasExecutionTests had no callers left and was removed.
    - plan.md Board sketch: task(id:) documents null with no error and AMBIGUOUS_ID; column/actor/tag(id:) lines added. README had no matching text.
    - Discovery: a root single-item field response carries `extensions.rewrites` (root -> board.<field>), and a `task:` alias carries a rewrite entry. So the null tests check `data` and the absence of `errors` rather than the exact text.
  timestamp: 2026-10-21T13:10:22.572975+00:00
- actor: claude-code
  id: 01m5f9b6g5a30ywgmfcaw4bz8f
  text: |-
    ### implement — changed
    - evidence: full `swift test` — 1724 tests in 143 suites passed, 0 failed. The only build warning is the third-party mlx-swift_Cmlx.bundle "missing creator for mutated node", with no package-code warnings. 9 files: Sources/FoundationModelsKanban/GraphQL/{QueryResolvers.swift, Schema.swift, SchemaDescription.swift}; Tests/FoundationModelsKanbanTests/{GraphQL/SingleItemFieldTests.swift, GraphQL/QueryResolverTests.swift, GraphQL/AliasExecutionTests.swift, Tool/KanbanEndpointTests.swift}; plan.md; task card
    - next: /review
  timestamp: 2026-10-21T13:10:25.029168+00:00
- actor: claude-code
  id: 01m5fb6qgnvm9nhsmcejym2ahf
  text: |-
    ### test — green
    - evidence: `swift test` — 1724 tests in 143 suites passed, 0 failed, 0 skipped; `swift build --build-tests` after touching the changed GraphQL sources and tests — no package-code warnings (only third-party `missing creator for mutated node ... mlx-swift_Cmlx.bundle`); `swift build --build-tests` in IntegrationTests/ — Build complete, exit 0.
    - note: the first `swift test` was started in parallel with the IntegrationTests build and hung for 1800s at 0% CPU. I killed it and reran the suite alone, which passed in 31s.
    - next: review
  timestamp: 2026-10-21T13:42:55.765561+00:00
- actor: claude-code
  id: 01m5fbeayccxde22rs4j364dqc
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` (0595b1f): 0 findings, 0 confirmed, 1 refuted; 7 files reviewed, 3 not reviewed (.kanban/ by .reviewignore, plan.md has no validator). All 6 findings of the 2026-10-21 07:48 pass are checked and checked against the code: Schema.swift uses `singleItemField` for task/column/actor/tag (2 duplication findings); KanbanEndpointTests.swift parameterizes subscribeMatchesDirectCall and failingSubscribeMatchesDirectCall over `userViewers` (nil, userDevice); QueryResolvers.swift resolves Board.task/column/actor/tag through `BoardView.matchingObject`, which gives nil for notFound and keeps AMBIGUOUS_ID, and `object(for:ofType:)` stays throwing for mutations; SchemaDescription.swift `singleItem` says "Null, with no error"; SingleItemFieldTests.swift `unknownIDGivesNull` asserts null with no errors for each field, and the file adds a root-field case and an AMBIGUOUS_ID case.
    - next: none. The task is in done.
  timestamp: 2026-10-21T13:47:05.036289+00:00
- actor: claude-code
  id: 01m5fbes9n74nhpegg76vf0kjr
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 8 files, 6/6 findings fixed (singleItemField helper, null for unknown id, viewer coverage)
    - test: green — swift test 1724 / 143; IntegrationTests build ok
    - commit: 0595b1f
    - review: clean — 0 findings
  timestamp: 2026-10-21T13:47:19.733352+00:00
depends_on:
- 01M5F234JM2BZEQ1TDMJK3FC4G
position_column: done
position_ordinal: ffaa80
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

## Review Findings (2026-10-21 07:48)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 17 file(s) reviewed, 6 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 2 file(s) not reviewed — no validator matched:
> - `README.md` — no validator matches this file
> - `plan.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/GraphQL/Schema.swift:1006` `duplication/duplication` — Near-duplicate field definition. The 'actor' field definition (lines 1006–1009) repeats the identical structure of the 'column' field (lines 1002–1005), differing only by field name and description reference. A third identical copy appears for 'tag' at lines 1010–1013. Extract a parameterized helper function to eliminate the repetition. Create a helper function in SchemaBuilder (e.g., `singleItemField(name:at:description:)`) that takes the field name, function pointer, and description reference, then call it three times instead of repeating the Field/Argument/description block.
- [x] `Sources/FoundationModelsKanban/GraphQL/Schema.swift:1010` `duplication/duplication` — Near-duplicate field definition. The 'tag' field definition (lines 1010–1013) repeats the identical structure of the 'column' (lines 1002–1005) and 'actor' (lines 1006–1009) fields, differing only by field name and description reference. Extract a parameterized helper function to eliminate the repetition. Create a helper function in SchemaBuilder (e.g., `singleItemField(name:at:description:)`) that takes the field name, function pointer, and description reference, then call it three times instead of repeating the Field/Argument/description block.
- [x] `Tests/FoundationModelsKanbanTests/Tool/KanbanEndpointTests.swift:85` `completeness/invariant-propagation` — executeMatchesDirectCall tests both nil and userDevice viewers to validate that the endpoint correctly handles different viewer contexts (line 66), but subscribeMatchesDirectCall only tests with nil viewer (line 92). Since the change restricts external viewers to their own board, subscription behavior should be tested with the same viewer variations to ensure the protocol conformance is complete across all viewer contexts. Parameterize subscribeMatchesDirectCall to test both nil and userDevice viewers, matching the pattern of executeMatchesDirectCall, to ensure subscription correctly applies viewer-based access control.

> Spec check against EXTRAS-9 rev 2 (TestudoApp/features/packages/foundationmodels-extras.md), requested with this review:

- [x] `Sources/FoundationModelsKanban/GraphQL/QueryResolvers.swift:356` `spec/EXTRAS-9-rule-5` — The new single-item fields `Board.column(id:)`, `Board.actor(id:)` and `Board.tag(id:)` (QueryResolvers.swift:356, :371, :386) throw `NOT_FOUND` when no live node has the id, so the response holds `null` plus an error. EXTRAS-9 rule 5 says: "One item that does not exist is `null`, not an error." Return `null` with no error for an id that names no node of the type (keep `AMBIGUOUS_ID` for an ambiguous ULID prefix, which is not a missing item). Remove the same cause from `Board.task(id:)` (QueryResolvers.swift:341), which this change moved onto the shared `BoardView.object(for:ofType:)` path: rule 5 says an endpoint that is already done changes to these rules. Keep `BoardView.task(for:)` throwing for the mutation callers that need the error, and give the query fields a non-throwing lookup.
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription.swift:145` `spec/EXTRAS-9-rule-5` — The schema description of the single-item fields says "Null, with the error NOT_FOUND, when no live <noun> has the id." This documents the behavior that EXTRAS-9 rule 5 forbids. Change it to state that an id that names no live node gives `null`.
- [x] `Tests/FoundationModelsKanbanTests/GraphQL/SingleItemFieldTests.swift:95` `spec/EXTRAS-9-rule-5` — `unknownIDGivesNotFound` asserts "null and NOT_FOUND" for an unknown id, which pins the behavior that EXTRAS-9 rule 5 forbids. Change it to assert `null` and no `errors` entry for each single-item field.
