---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5g4wext826wb5tpw8378gfx
  text: |-
    ### finish iteration 1 — stuck
    - Not started: both options in the task need a human decision. (a) New FoundationModelsExtras features (type-name aliases in variable definitions, argument-to-input move, empty-input default) — work in another repo. (b) Bump the endpoint version (EXTRAS-9 rule 1) and break callers with no alias. /finish will not pick either on its own.
    - next: a human chooses (a) or (b); then /finish ^gnn5vz8.
  timestamp: 2026-10-21T21:11:42.266343+00:00
- actor: claude-code
  id: 01m5g8hq0zgwq4w75q6xsycjwb
  text: |-
    Picked up with the user decision: bump the endpoint version to "2" and change the 21 mutations with no alias for the old forms.

    Research:
    - Extras `GraphQLConventions.expectedSignature(ofMutation:)` asks `name(input: NameInput!)` when the name matches `[a-z]+[A-Z][A-Za-z0-9]*`, and the generic form `verbNoun(input: VerbNounInput!)` otherwise, so a one-word name (`undo`, `redo`) can never pass. `GraphQLConventionException` is per rule only (no per-mutation scope), so a narrow exception for undo/redo is not possible. Decision: rename them `undoChange(input: UndoChangeInput!)` and `redoChange(input: RedoChangeInput!)` (they give a `Change`, the history type). EXTRAS-9 rule 7 (TestudoApp/features/packages/foundationmodels-extras.md) says "The alias tables accept the bare verb (`start`)", so `undo`/`redo` become name aliases of the Mutation fields; that is the rule's bare-verb alias, not the old form (the old optional input and `UndoInput` type are gone).
    - Graphiti keys an input type by its Swift type (`graphQLNameMap[AnyType]`), so one Swift struct cannot be two GraphQL input types. Shared shapes (NodeReferenceInput x9, CommentReferenceInput x2, AssignTaskInput/TagTaskInput for the un- verbs, BoardInput x2, UndoInput x2) become generic over a marker of the mutation, registered with `Input(..., as: "<Mutation>Input")`.
    - `MutationName.undo/redo` is also the op name written in event `ops`; only `collectBoards` is read back from ops (UndoLog), so the rename only changes the op text of new undo events.
    - Error hints in Errors.swift still show the pre-input form `undo(txn: ...)`; they must show the new call.
    - `KanbanFieldAliases.byField` keys the delete/undelete id aliases by mutation because the input type was shared; with one type per mutation they can key by type.
  timestamp: 2026-10-21T22:15:44.415972+00:00
- actor: claude-code
  id: 01m5ga947659rm3afjn8smv200
  text: |-
    Implementation landed (endpoint version 2, no alias for old forms):
    - All 34 mutations are now `name(input: NameInput!)`; golden SDL re-recorded (Tests/Fixtures/kanban.graphql). EndpointConventionTests runs the conformance check with no exception; the rule-7 exception and the mutationsOutsideRule7 list are gone.
    - Shared shapes are generic over a private marker (`SharedInputMutation`, new file GraphQL/SharedInputMutation.swift), because Graphiti maps one Swift type to one GraphQL type: NodeReferenceInput<M>, CommentReferenceInput<M>, AssignTaskInput<M>, TagTaskInput<M>, BoardInput<M>, ReverseInput<M>. `OptionalInputArguments`/`MutationArguments` removed; `input` is always required, `input: {}` for no field (new test proves a call without `input` fails validation for the 8 all-optional mutations).
    - undo/redo renamed undoChange/redoChange: Extras `expectedSignature` rejects every one-word name and exceptions are per-rule only, so no narrow exception exists. Per EXTRAS-9 rule 7 ("alias tables accept the bare verb") `undo`/`redo` stay as Mutation name aliases. Event ops now record "undoChange"/"redoChange".
    - repairLinks/collectBoards arguments moved into RepairLinksInput/CollectBoardsInput; error hints (undo txn/force/boards, repairLinks reach) show the new forms.
    - Field aliases keyed by the new per-mutation input types; byField mutation entries removed.
    - Callers updated: KanbanTool description, SKILL.md (examples + outputs), README, plan.md §4.2/§6.5, divergence.md synonym table, all tests.
    - Left as is: forgiving input-field aliases (board/reachable/preview inside repairLinks input) are field-name aliases, not old call forms; dated history lines in divergence.md.
  timestamp: 2026-10-21T22:46:00.166096+00:00
- actor: claude-code
  id: 01m5ga969bhxyg6rsxvav3axcw
  text: |-
    ### implement — changed
    - evidence: `swift test` 1751 tests in 146 suites passed, no package warnings; `swift build --build-tests` in IntegrationTests: Build complete; 48 files changed (18 Sources incl. new GraphQL/SharedInputMutation.swift, ~25 Tests, Tests/Fixtures/kanban.graphql, Documentation/kanban/SKILL.md, README.md, plan.md, divergence.md)
    - next: /review
  timestamp: 2026-10-21T22:46:02.283786+00:00
- actor: claude-code
  id: 01m5gbbn4aw806z4z2jn0hdk83
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (bd01871) — 6 findings (6 confirmed, 0 refuted): ColumnActorMutations.swift:132, CommentMutations.swift:65, MutationResolvers.swift:159, TaskOperationMutations.swift:56, TaskOperationMutations.swift:66, UndoMutations.swift:21 — code-hygiene/dead-code-swift: generic_type_param `Mutation` is unused.
    - next: implement — remove the unused generic `Mutation` parameter from each listed declaration and from every other declaration in those files with the same cause, then re-review.
  timestamp: 2026-10-21T23:04:51.594502+00:00
- actor: claude-code
  id: 01m5gbc7rfw32wb3dqw8sq0mqf
  text: |-
    ### finish iteration 2 — findings
    - user chose: bump endpoint version to "2", no alias for old forms
    - implement: changed — 48 files, all 34 mutations name(input: NameInput!), undoChange/redoChange
    - test: green — swift test 1751 tests / 146 suites; IntegrationTests build-tests
    - commit: bd01871
    - review: findings — ColumnActorMutations.swift:132, CommentMutations.swift:65, MutationResolvers.swift:159, TaskOperationMutations.swift:56, TaskOperationMutations.swift:66, UndoMutations.swift:21 (generic_type_param `Mutation` is unused)
  timestamp: 2026-10-21T23:05:10.671338+00:00
- actor: claude-code
  id: 01m5gbmh9bh19594t99yqtfbd0
  text: |-
    Fix for the 6 `code-hygiene/dead-code-swift — generic_type_param Mutation is unused` findings.

    Discoveries:
    - The findings come from periphery and point at the generic STRUCT declarations (NodeReferenceInput, CommentReferenceInput, BoardInput, AssignTaskInput, TagTaskInput, ReverseInput), not at resolver functions. The resolver helpers (changeDeleted, changeBoard, changeAssignee, reverse) already use their `Mutation` param (`Mutation.name`), so periphery never flagged them. The structs used `Mutation` only as a phantom type.
    - You can run periphery locally to get the same result: `swift build --build-tests`, then `periphery scan --skip-build --index-store-path .build/out --retain-public --retain-objc-accessible --retain-codable-properties --relative-results --report-exclude 'Tests/**'` (SwiftPM 6.4 writes the index store to .build/out). Before the fix this command printed exactly the 6 findings.

    Fix (option "use the marker so it carries meaning"):
    - Each of the 6 shared input structs now declares `static var inputTypeName: String { Mutation.inputTypeName }`, which is the GraphQL name of that specialization (EXTRAS-9 rule 7). Each make*Input builder registers `Input(X<Mutation>.self, as: X<Mutation>.inputTypeName)` instead of `mutation.inputTypeName`, so the GraphQL type name now comes from the input type itself. This is a real use of the marker, and there is no suppression marker.
    - Not chosen: one concrete struct per mutation. That would copy the 4-field BoardInput/ReverseInput bodies (with their docs) twice each and would break the duplication rule.
    - Schema output is unchanged: the golden SDL test passes.
  timestamp: 2026-10-21T23:09:42.571261+00:00
- actor: claude-code
  id: 01m5gbmn37ay05a8s3h19f85t9
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsKanban/GraphQL/{ColumnActorMutations,CommentMutations,MutationResolvers,TaskOperationMutations,UndoMutations,SharedInputMutation}.swift. periphery scan: 0 generic_type_param findings (6 before). `swift test`: 1751 tests in 146 suites passed, no package warnings. IntegrationTests `swift build --build-tests`: Build complete. Findings 6/6 ticked; task left in doing, not committed.
    - next: /review
  timestamp: 2026-10-21T23:09:46.471445+00:00
position_column: doing
position_ordinal: '80'
title: 'EXTRAS-9 rule 7: give each mutation the form verbNoun(input: VerbNounInput!)'
---
## What
EXTRAS-9 rule 7 asks that each mutation is `verbNoun(input: VerbNounInput!)`. The conformance test of ^esc56vk (Tests/FoundationModelsKanbanTests/GraphQL/EndpointConventionTests.swift) lists rule 7 as an exception that this task removes. Of the 34 mutations, 21 do not match (see Tests/Fixtures/kanban.graphql):

- shared input type: deleteColumn, undeleteColumn, deleteActor, undeleteActor, completeTask, deleteTask, undeleteTask, deleteTag, undeleteTag (`NodeReferenceInput!`); deleteComment, undeleteComment (`CommentReferenceInput!`); unassignTask (`AssignTaskInput!`); untagTask (`TagTaskInput!`)
- optional input: initBoard, updateBoard (`BoardInput`), addActor (`AddActorInput`), addTag (`AddTagInput`). plan.md §4 makes `input` optional when it has no required field, so a call with no input is part of the contract.
- one-word name and optional shared input: undo, redo (`UndoInput`)
- arguments and no input object: repairLinks(boards, reach, dryRun), collectBoards(sources, target, reach, dryRun)

The 13 that match: addColumn, updateColumn, updateActor, addTask, updateTask, moveTask, assignTask, tagTask, copyTask, addComment, updateComment, updateTag, renameTag.

## Why it was not fixed in ^esc56vk
`GraphQLNameRules` aliases fields, arguments and input fields only. The rewrite of Extras does not rename a type name in a variable definition (`$input: NodeReferenceInput!` stays and the call fails with an unknown type), cannot move top-level arguments into an `input` object, and cannot give a default for a missing required `input`. So no fix can keep the old form as an alias, and each fix breaks a caller.

## Options
- Add to Extras: type-name aliases for variable definitions, an argument-to-input move, and an empty-input default for a required input; then fix each mutation with the old form as an alias.
- Or bump the endpoint version (EXTRAS-9 rule 1) and change the schema with no alias.

Decision (user): bump the endpoint version to "2" and change the schema with no alias for the old forms.

## Acceptance Criteria
- [x] Each mutation is `verbNoun(input: VerbNounInput!)`, or the old form still works as an alias
- [x] The rule-7 exception is gone from EndpointConventionTests, and the golden SDL is recorded again

## Review Findings (2026-10-21 17:46)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 45 file(s) reviewed, 9 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 5 file(s) not reviewed — no validator matched:
> - `Documentation/kanban/SKILL.md` — no validator matches this file
> - `README.md` — no validator matches this file
> - `Tests/Fixtures/kanban.graphql` — no validator matches this file
> - `divergence.md` — no validator matches this file
> - `plan.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/GraphQL/ColumnActorMutations.swift:132` `code-hygiene/dead-code-swift` — generic_type_param `Mutation` is unused.
- [x] `Sources/FoundationModelsKanban/GraphQL/CommentMutations.swift:65` `code-hygiene/dead-code-swift` — generic_type_param `Mutation` is unused.
- [x] `Sources/FoundationModelsKanban/GraphQL/MutationResolvers.swift:159` `code-hygiene/dead-code-swift` — generic_type_param `Mutation` is unused.
- [x] `Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift:56` `code-hygiene/dead-code-swift` — generic_type_param `Mutation` is unused.
- [x] `Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift:66` `code-hygiene/dead-code-swift` — generic_type_param `Mutation` is unused.
- [x] `Sources/FoundationModelsKanban/GraphQL/UndoMutations.swift:21` `code-hygiene/dead-code-swift` — generic_type_param `Mutation` is unused.
