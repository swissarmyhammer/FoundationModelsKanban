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