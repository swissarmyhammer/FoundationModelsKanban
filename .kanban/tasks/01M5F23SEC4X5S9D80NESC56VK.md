---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f4m9seds7c15yvhfzc4h5a
  text: |-
    ### EXTRAS-11 heads-up from foundationmodelsmultitool-bc (2026-10-21)
    EXTRAS-11 is coded in Extras but not pushed yet; that session will send the sha. Once it is pushed, bump Extras and use:
    - `GraphQLEndpointConformance.problems(of:scope:probe:codes: [String] = [], exceptions: [GraphQLConventionException] = [])`.
    - Exception example: `GraphQLConventionException(rule: .rule9, removedBy: "e60e9sx")`. It checks rules 3, 7, 8 and 9, and each problem starts with "rule N:".
    - Rule 8: pass every error and warning code that KanbanGraph can give in `codes`. The SDL does not list them, so collect them from KanbanError and the warning codes, including INCOMPATIBLE_BOARD.
    - Task ^70231sy (after EXTRAS-11) adds an ID scalar to `addToolkitScalars()`. Keep kanban's NodeID if its forgiving input parsing must stay; the requirement is only that id, added, changed and removed render as ID in the SDL.
    If EXTRAS-11 is still not on Extras origin/main when this task starts, check with foundationmodelsmultitool-bc before writing the conformance test against the old API.
  timestamp: 2026-10-21T11:48:00.430691+00:00
- actor: claude-code
  id: 01m5f4w7n42ktf89x1xzkcpw1x
  text: |-
    ### EXTRAS-11 landed (2026-10-21)
    EXTRAS-11 is on FoundationModelsExtras origin/main: the code commit is dbf4202 and the tip is 02a207c. Set the Extras pin to 02a207c or later by hand. `swift package update FoundationModelsExtras` fails here on swift-case-paths, so edit the revision in Package.resolved and IntegrationTests/Package.resolved, then run `swift package resolve`, as in 91c116c. The API is `problems(of:scope:probe:codes:exceptions:)` with `GraphQLConventionException(rule:removedBy:)`. The ID scalar will be a separate opt-in, `addToolkitIDScalar()`, and `addToolkitScalars()` does not change. Kanban keeps NodeID: the rule-9 check reads the type name ID, so NodeID fields pass.
  timestamp: 2026-10-21T11:52:20.388456+00:00
- actor: claude-code
  id: 01m5fbkxgyy08c12vjndxyndcy
  text: |-
    ### research (implement pickup)
    - Extras origin/main tip is ac1b9f2 (contains dbf4202 EXTRAS-11 and 9c47e10/44c2f54 ToolkitID). Pins in Package.resolved and IntegrationTests/Package.resolved edited by hand to ac1b9f2c123f109bdb4b09cc33af3b3f56a3643e; `swift package resolve` ok in both.
    - API at that tip: `GraphQLEndpointConformance.problems(of:scope:probe:codes:exceptions:)`; `GraphQLConventionException(rule:removedBy:)` with `GraphQLConventionRule` cases `.scope`(3), `.mutations`(7), `.codes`(8), `.changes`(9). An exception covers a whole rule; there is no per-mutation exception.
    - Rule 7 check: a mutation passes only when its name matches `[a-z]+[A-Z][A-Za-z0-9]*` and its args are exactly `(input: <Name>Input!)`. So `undo`/`redo` (one word) can never pass.
    - `BOARD_INCOMPATIBLE` readers in siblings: no code reader. Mentions: skills/skills/kanban/SKILL.md (doc copy of Documentation/kanban/SKILL.md; KanbanSkillTests no longer compares with ../skills), TestudoApp/features/packages/foundationmodels-extras.md (the spec that asks for the rename). KanbanViewKit: none.
    - Siblings (Agents, Skills, ACPAgent, Multitool) put the golden SDL at Tests/Fixtures/<name>.graphql, outside the test target, so SwiftPM gives no unhandled-resource warning.
    - tool-gives-endpoint test exists: KanbanEndpointTests.toolGivesEndpoint.
  timestamp: 2026-10-21T13:50:07.902841+00:00
- actor: claude-code
  id: 01m5fc1rgrrn9k3jh5gbeyx6kr
  text: |-
    ### progress
    - Rename done: `UnreadableBoard.incompatibleWarningCode` is now `INCOMPATIBLE_BOARD` (BoardLocator.swift), docs in KanbanGraph.swift, Schema.swift, KanbanTool.swift (tool description), Documentation/kanban/SKILL.md, divergence.md Q6. IncompatibleBoardTests RED (got BOARD_INCOMPATIBLE) then GREEN. No `BOARD_INCOMPATIBLE` left in Sources, Tests, README, plan.md, divergence.md, Documentation. Not edited (other repo): skills/skills/kanban/SKILL.md still says `BOARD_INCOMPATIBLE` (a doc, not a code reader).
    - New Tests/FoundationModelsKanbanTests/GraphQL/EndpointConventionTests.swift: golden (RED: file missing, then recorded to Tests/Fixtures/kanban.graphql), descriptions, conformance with probe createTask -> addTask and exceptions rule 9 (e60e9sx) and rule 7 (gnn5vz8), plus a test that pins the 21 mutations that break rule 7.
    - Rule 7: 21 of 34 mutations break it. None can be fixed with the old form as an alias: the Extras rewrite does not rename type names in variable definitions, cannot move arguments into `input`, and cannot default a required `input` (plan.md §4 makes `input` optional). New task ^gnn5vz8 holds the work; rule 7 is an exception that names it.
    - Conformance passes under the two exceptions. Descriptions test is RED: about 350 undescribed parts. Adding descriptions now (three parallel forks: Schema.swift types, change/link types, mutations).
  timestamp: 2026-10-21T13:57:41.528418+00:00
- actor: claude-code
  id: 01m5fckg4kgrh8ajgdh5a6v9sk
  text: |-
    ### implement — changed
    - evidence: `swift test` exit 0: 1728 tests in 144 suites passed, 0 failed, 0 skipped. The only build warning is "missing creator for mutated node … mlx-swift_Cmlx.bundle", which HEAD also has. Extras is pinned at ac1b9f2 in Package.resolved and IntegrationTests/Package.resolved.
    - Descriptions: GraphQLSchemaDescriptions.undescribed was about 350 parts; it is now empty. New files: SchemaDescription+Types.swift, SchemaDescription+Changes.swift (with the `DescribedGraphQLEnum` protocol for enum values), and SchemaDescription+Mutations.swift (with the `mutationField(_:at:description:)` helper and the `MutationArguments.inputDescription`). The re-recorded golden SDL has the same structure as before; only descriptions were added.
    - Three existing tests matched one-line SDL text, which descriptions now split over several lines: MutationInputSchemaTests.addTagInputIsOptionalInSDL, NodeQueryTests.nodesFieldType, and UndoTests.schemaHasUndoAndRedo. They now read SDLSignatures.ofPublicSchema(). The undo description no longer says "patches", because GraphQLEngineTests and KanbanGraphTests check that the public SDL has no "patch".
    - Rule 7: 21 of 34 mutations break it and none could be fixed with the old form as an alias. The exception names ^gnn5vz8, and onlyKnownMutationsBreakRule7 pins the list.
    - Rule 9: the exception names e60e9sx (KANBAN-7).
    - Other repo, not edited: skills/skills/kanban/SKILL.md still says `BOARD_INCOMPATIBLE`.
    - next: /review
  timestamp: 2026-10-21T14:07:22.771295+00:00
- actor: claude-code
  id: 01m5fcqwr29dg2ec4x8qk7e018
  text: |-
    ### test — green
    - evidence: `swift test` (package root) — 1728 tests in 144 suites passed, 0 failed, 0 skipped, no compiler warnings in package code; `swift build --build-tests` in IntegrationTests/ — Build complete, no package-code warnings. Ran sequentially, not in parallel.
    - notes: the only `warning:` lines are the SwiftPM build-system message "missing creator for mutated node" on the third-party mlx-swift_Cmlx.bundle (out of scope), and runtime log lines emitted by tests that feed malformed log lines to replay on purpose.
    - next: review
  timestamp: 2026-10-21T14:09:46.754409+00:00
- actor: claude-code
  id: 01m5fdxcfhw47ts39y7q1d6xb2
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (a46ca01): engine counts findings 2, confirmed 2, refuted 1, failed 0. Description spot-check: 52 checked, 6 do not match the resolvers. Open items: Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift:625, :630 (duplication/duplication); SchemaDescription+Mutations.swift:178, :152, :394, :336, :315; SchemaDescription+Types.swift:169 (description/accuracy).
    - acceptance: all 3 acceptance boxes and both Tests boxes ticked. `swift test --filter 'EndpointConventionTests|KanbanEndpointTests|IncompatibleBoardTests'`: 22 tests in 3 suites passed. `rg -uu BOARD_INCOMPATIBLE`: none in Sources, Tests, README, Documentation, plan or divergence docs. The only matches are in .kanban task history and logs.
    - rule-7 deferral to ^gnn5vz8: sound. The FoundationModelsExtras NameRewrite (pinned ac1b9f2) edits only written field, argument and input-field names. It also removes parameters and wraps containers. It has no edit that renames a type name in a variable definition, moves top-level arguments into `input`, or supplies a missing required `input`. So no rule-7 fix can keep the old form as an alias. The exception covers all of rule 7. `onlyKnownMutationsBreakRule7` holds it to exactly the 21 named mutations, and that list can only get shorter. Both exceptions name existing tasks (^e60e9sx, ^gnn5vz8).
    - next: implementer fixes the 8 open items (fix each cause across the whole file), records the golden SDL again, then re-review.
  timestamp: 2026-10-21T14:30:15.281315+00:00
- actor: claude-code
  id: 01m5fdy74zkcakghagqzcvf5kr
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — Extras → ac1b9f2, INCOMPATIBLE_BOARD rename, rule-11 tests, ~350 descriptions, new task ^gnn5vz8
    - test: green — swift test 1728 / 144; IntegrationTests build ok
    - commit: a46ca01
    - review: findings — TaskOperationMutations.swift:625, :630; SchemaDescription+Mutations.swift:152, :178, :315, :336, :394; SchemaDescription+Types.swift:169
  timestamp: 2026-10-21T14:30:42.591859+00:00
- actor: claude-code
  id: 01m5fe9k9qyybrgjnzqsvedkzd
  text: |-
    ### research (implement pickup, review round 2)
    - Audited each description in SchemaDescription+Types/+Changes/+Mutations against its resolver, plus `updateFilter`.
    - `updateFilter`, no filter, real behavior: in `history` and `changes`, ChangeFilter goes through TaskFilter, which hides a task that is deleted (in the graph the filter reads), except its DELETED update. Updates of deleted columns/actors/tags stay (only a task has a hidden state). `Change.updates` with no filter returns each update of the change. So "all updates are returned" is true only for Change.updates; the description now says both.
    - `AddTagInput.name` with no name: `TagName(normalizing: key)` where key is the id text for a short form, the local id (slug) for a full URI, and the `<id>` part for `tag/<id>`. So a short-form id gives its own text (normalized), not its slug; the description says so instead of "the slug of the id".
    - `undo` no txn (UndoLog.target): newest txn of the session actor, not undone, `undoes == nil` (so not an undo or a redo), after the newest collectBoards txn; searched in the current board and the loaded related boards. `redo` no txn: newest undo of the session actor, not undone, whose target is an original txn, after the newest collectBoards txn. `redo(txn: T)` takes the ORIGINAL txn T, so `Change.txn` "Give it to undo or redo to reverse this change" was wrong for redo.
    - Name refs: RefResolver accepts a column/actor name that gives the slug, so "a full URI or the slug" (columnReference, actorReference, assignees) left names out.
    - Duplication: the `id` input field with `SchemaDescription.taskReference` is in AssignTaskInput, TagTaskInput, placementFields, and also UpdateTaskInput (TaskMutations.swift): four copies. One shared helper fixes all four.
  timestamp: 2026-10-21T14:36:55.479707+00:00
- actor: claude-code
  id: 01m5fejj2s0a91pd32q14qj3ae
  text: |-
    ### implement — changed
    - Duplication: new `TaskReferenceInput` protocol (`var id: NodeID`) and `SchemaBuilder.taskReferenceField()` in TaskMutations.swift. AssignTaskInput, TagTaskInput, placementFields (via `TaskPlacementInput: TaskReferenceInput`) and UpdateTaskInput, the fourth copy, all call it. The SDL does not change from this.
    - The 6 findings are fixed: undo + UndoInput.txn, addTag, AddTagInput.name, Move/CopyTaskInput.column, UpdateTaskInput, Actor/Tag.color. AddTagInput.name differs from the suggested wording: a short-form id gives its own text as the name (TagName(normalizing: key)), not its slug; only a full URI or tag/<id> gives the slug. The description says both.
    - Full audit beyond the 6: 20 more descriptions changed. Types: queryBoards (search roots), taskComments (empty for a deleted task), taskStarted (first move to a non-first column, the add included), taskCompleted (null also with no column move), progress (- [X] also counts), Priority (which values move and which keep the place). Changes: changeTxn (redo takes the original txn), changeUndone (undo or redo), FieldChange.before/after (null when no value), LinkRepair (collectBoards also reports it), FieldConflict (winner is the merge of all events). Mutations: redo, BoardInput, UpdateActorInput, UpdateTagInput (null on name is ignored), actorReference + columnReference (a name also works; new helper slugReferenceText), AddTaskInput/UpdateTaskInput assignees (names also work).
    - updateFilter: real behavior is not "all updates": in history and changes, no filter drops the updates of a task that is deleted now, except its delete update; Change.updates with no filter keeps each update. The description says both.
    - Not changed, outside the asked files: SchemaDescription.conflictWinner ("the value of the last event") has the FieldConflict cause for the body field.
    - Golden SDL re-recorded with GRAPHQL_GOLDEN_RECORD=1 (EndpointConventionTests was RED on the golden test before). Only description lines changed.
    - evidence: `swift test` exit 0: 1728 tests in 144 suites passed, 0 failed. Only warning is the existing SwiftPM "missing creator for mutated node … mlx-swift_Cmlx.bundle" message, which HEAD also has.
    - next: /review
  timestamp: 2026-10-21T14:41:49.145635+00:00
- actor: claude-code
  id: 01m5feqn0qxqnxsg151t6347d7
  text: |-
    ### implement — changed (coordinator follow-up: SchemaDescription.swift)
    - conflictWinner fixed: the winner is the merge of the events of all the boards (body edits merge, not "last event"); null when the field has no value.
    - Audited the rest of SchemaDescription.swift against the resolvers; 4 more fixed: taskFilter (a ^id or ~task atom also shows deleted tasks, FilterExpr.names), nextTask (READY = live, not done, and no dependency stops it; a done dependency in a cycle still stops it), updateTaskColumn (a priority can put the task at the top), collectedNames (also holds the board ref of the call, CollectedSource.names). The other descriptions match.
    - Golden SDL re-recorded (GRAPHQL_GOLDEN_RECORD=1).
    - evidence: `swift test` exit 0: 1728 tests in 144 suites passed, 0 failed; only warning is the existing SwiftPM "missing creator for mutated node … mlx-swift_Cmlx.bundle" message from a third-party package.
    - next: /review
  timestamp: 2026-10-21T14:44:35.991482+00:00
- actor: claude-code
  id: 01m5fetf3hhc3n4yycwsp6hnre
  text: |-
    ### test — green
    - evidence: swift test — 1728 tests in 144 suites passed, 0 failed, 0 skipped; swift build --build-tests in IntegrationTests/ — Build complete, exit 0. No package-code warnings; the only warning is third-party (mlx-swift_Cmlx.bundle "missing creator for mutated node").
    - next: review/commit
  timestamp: 2026-10-21T14:46:08.241596+00:00
depends_on:
- 01M5F23FSEG4MRQ3NWWD7SGPAZ
position_column: doing
position_ordinal: '80'
title: 'EXTRAS-9 alignment: rename the warning BOARD_INCOMPATIBLE to INCOMPATIBLE_BOARD and add the rule-11 endpoint tests'
---
## What
EXTRAS-9 rules 8 and 11 (TestudoApp/features/packages/foundationmodels-extras.md, D115).

1. Warning code: `BoardLocator.incompatibleWarningCode` (Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift:494) is `BOARD_INCOMPATIBLE`; the error is already `INCOMPATIBLE_BOARD`. Change the warning to `INCOMPATIBLE_BOARD`. Update the docs at BoardLocator.swift:487/502, GraphQL/Schema.swift:689, Tool/KanbanGraph.swift:1141, the tool description in Tool/KanbanTool.swift:65, and Tests/.../Tool/IncompatibleBoardTests.swift. No caller in the family reads the old code (check TestudoApp, KanbanViewKit, skills/ before removing); if one does, keep `BOARD_INCOMPATIBLE` as a second warning entry for one version. Do not bump the endpoint version for a warning code rename unless a reader is found.
2. Rule 11 tests, in Tests/FoundationModelsKanbanTests/GraphQL:
   - `GraphQLSchemaGolden` test of the kanban SDL (golden file checked in)
   - `GraphQLSchemaDescriptions.undescribed` is empty
   - `GraphQLEndpointConformance.problems` is empty, with an alias probe (for example `createTask` → `addTask`). Until KANBAN-7 lands, list rule 9 (changes(after:), cursor) as an exception with the id of the KANBAN-7 task, as EXTRAS-11 allows.
   - Check every mutation is `verbNoun(input: VerbNounInput!)`; any that is not (for example `repairLinks`, `collectBoards`, `undo`, `redo`, `initBoard`) is either fixed with the old form as an alias, or listed as an exception with a reason.

## Acceptance Criteria
- [x] A call that reaches a Rust `.kanban` sibling via `boards` gives warning `INCOMPATIBLE_BOARD`
- [x] No `BOARD_INCOMPATIBLE` left in Sources, Tests, README, skill, or plan docs (unless kept as an alias for a found reader)
- [x] Four rule-11 tests exist and pass; exceptions name a task id

## Tests
- [x] IncompatibleBoardTests updated to the new code
- [x] Golden, descriptions, conformance-with-alias-probe, tool-gives-endpoint tests

## Review Findings (2026-10-21 09:10)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 26 file(s) reviewed, 11 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

> 5 file(s) not reviewed — no validator matched:
> - `Documentation/kanban/SKILL.md` — no validator matches this file
> - `IntegrationTests/Package.resolved` — no validator matches this file
> - `Package.resolved` — no validator matches this file
> - `Tests/Fixtures/kanban.graphql` — no validator matches this file
> - `divergence.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift:625` `duplication/duplication` — Identical input field definition for 'id' appears verbatim at TaskTransferMutations.swift:443, creating a changed-set duplicate within this change that could drift out of sync if updated in one place but not the other. Extract a shared helper function that returns this input field definition, then call it from both AssignTaskInput and placementFields. This creates a single source of truth for the 'id' field across input types.
- [x] `Sources/FoundationModelsKanban/GraphQL/TaskOperationMutations.swift:630` `duplication/duplication` — Identical input field definition for 'id' appears in a third location (TagTaskInput at line 630), alongside the same definition at line 625 (AssignTaskInput) and TaskTransferMutations.swift:443 (placementFields). This is a three-way changed-set duplicate that could drift out of sync. Extract a shared helper function that returns the 'id' input field definition, and call it from all three locations (TagTaskInput, AssignTaskInput, and placementFields). This consolidates the duplication into a single source of truth.

### Description accuracy spot-check (2026-10-21 09:29)

> The caller asked for a check of the added schema descriptions against the resolvers. 52 descriptions were checked; 46 match the code, and the 6 below do not. Each one is a description that this commit added. The SDL in Tests/Fixtures/kanban.graphql must be recorded again after each fix.

- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Mutations.swift:178` `description/accuracy` — `Mutation.undo` says "No txn reverses the newest transaction of the session actor that is not undone." With no txn, `UndoLog.target(of:named:by:)` (Sources/FoundationModelsKanban/Undo/UndoLog.swift) takes only a transaction that is not itself an undo (`undoes == nil`) and that comes after the newest `collectBoards` transaction. Say both conditions. The same cause is in `undoTransaction` (`UndoInput.txn`, SchemaDescription+Mutations.swift:428, "No txn gives the newest one of the session actor"): correct it too.
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Mutations.swift:152` `description/accuracy` — `Mutation.addTag` says an existing slug "gives that tag, and makes it live again when it is a tombstone." `ensureLiveTag` follows the rename redirect (`undeleteTag(redirectedFrom:at:)` in Sources/FoundationModelsKanban/GraphQL/TagMutations.swift) and gives, and revives, the tag at the end of the rename chain. Say that a renamed slug gives the tag it redirects to.
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Mutations.swift:394` `description/accuracy` — `AddTagInput.name` says "No name gives the text of the id." The name comes from `RefResolver.newNodeKey(for:ofType:)`: for a full tag URI or the stored form `tag/<slug>` it is the local id (the slug), not the text that was written. Say that no name gives the slug of the id.
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Mutations.swift:336` `description/accuracy` — `MoveTaskInput.column` / `CopyTaskInput.column` say "No column keeps the column of the task." For copyTask, and for moveTask to a different board, `column(of:named:resolvingWith:at:)` in Sources/FoundationModelsKanban/GraphQL/TaskTransferMutations.swift uses the live column of the target board with the same slug, and the first column of the target board when it has none. Say this for the cross-board case.
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Mutations.swift:315` `description/accuracy` — `UpdateTaskInput` says "A field that is not set does not change, and null clears it." `column` and `priority` are plain optionals in Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift: null means no move, not a clear; `title` null is ignored with a warning. Name the fields where null clears, or say which fields do not clear.
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Types.swift:169` `description/accuracy` — `Actor.color` / `Tag.color` say "The display color: 6 hex digits with no #." No code validates or normalizes a color: addActor, updateActor, addTag and updateTag store the given string as is, and the resolvers in Sources/FoundationModelsKanban/GraphQL/QueryResolvers.swift return it. Only the tag auto color is 6 hex digits. Either validate the color on write or describe the field as the stored string.