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
position_column: todo
position_ordinal: '8580'
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

## Acceptance Criteria
- [ ] Each mutation is `verbNoun(input: VerbNounInput!)`, or the old form still works as an alias
- [ ] The rule-7 exception is gone from EndpointConventionTests, and the golden SDL is recorded again