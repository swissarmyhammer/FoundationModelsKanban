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
- actor: claude-code
  id: 01m5ffae4sb359k7cc6c7cp5r2
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (078e5e7): engine counts findings 1, confirmed 1, refuted 0, failed 0 (TaskMutations.swift:676 swift/fluent-usage). Prior findings: 7 of 8 fixed in code (task-id duplication via taskReferenceField, undo/UndoInput.txn, redo, addTag, placementColumn incl. same-board copyTask, UpdateTaskInput null semantics, labelColor). AddTagInput.name still not exact (TagName normalizing). Descriptions changed in 078e5e7: 31 checked, 6 wrong. Fresh sample, unchanged by 078e5e7: 120 checked, 6 added by this task wrong. Six more mismatches in descriptions older than this task were left out: linkStatus, linkTarget, collectResultRepairs, collectResultOtherLinks, VirtualTag.explanation READY/BLOCKED/DELETED. Open items: TaskMutations.swift:676, :694, :83; SchemaDescription+Mutations.swift:410, :265, :38, :101, :106, :315; SchemaDescription+Changes.swift:13, :7, :54; SchemaDescription.swift:405, :388; SchemaDescription+Types.swift:32, :344; CheckLinksField.swift:158.
    - next: implementer fixes the 17 open items (each cause across the whole file), records the golden SDL again, then re-review. A follow-up task can take the six mismatches older than this task.
  timestamp: 2026-10-21T14:54:51.545491+00:00
- actor: claude-code
  id: 01m5ffb2gtxsftn7jhfa4h8etv
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — 9 files, 8 findings worked, 27 more descriptions corrected
    - test: green — swift test 1728 / 144; IntegrationTests build ok
    - commit: 078e5e7
    - review: findings — TaskMutations.swift:676, :694, :83; SchemaDescription+Mutations.swift:410, :265, :38, :101, :106, :315; SchemaDescription+Changes.swift:13, :7, :54; SchemaDescription.swift:405, :388; SchemaDescription+Types.swift:32, :344; CheckLinksField.swift:158
  timestamp: 2026-10-21T14:55:12.410678+00:00
- actor: claude-code
  id: 01m5ffmvbw39x0hvv3fbwnesdf
  text: |-
    ### research (implement pickup, review round 3)
    - Traced for the 17 open items: AddTagInput.name = TagName(normalizing: input.name ?? key) where key = RefResolver.newNodeKey: a short form as written, the local id of a full URI, the <id> part of tag/<id>; so a given name also goes through the tag name rule. UndoLog.target: a collectBoards txn (isFinal) gives NOTHING_TO_UNDO with or without txn. ChangeBuilder: only NodeObject.trackedFields are compared (body, deleted, plus per type: Board name/model/summary, Column name/order, Actor name/color/avatar, Tag name/color, Task title/column/ordinal/assignees/tags/dependsOn/blockedBy/unresolvedDependsOn/ready/virtualTags/progress/started/completed, Comment task/author). The batch rule (one update per node, in the last transaction of the batch that patched it; derived updates of live nodes in the last change) applies to the subscription batches; Board.history builds each transaction alone (History.changes -> ChangeBuilder.change(of:)).
    - PriorityMove: table lookup on value.text.lowercased(); stay for medium/normal/p2 and any unknown text. addTask: ordinal = priority move ?? input ordinal ?? end. updateTask column: end, or top for a toTop priority.
    - LinkedBoard.check(of:): .unreadable gives .ok or .oldName with no node check.
    - RefResolver.storedRef accepts the stored form <type>/<id> for column and actor refs (nodeRef), but moveTask/copyTask column and addComment actor do not: a non-URI text is slugged first (Slug(columnOrActorName:)), so column/foo would make a column column-foo.
    - Duplication plan: one protocol + one make…Field() factory per shared input field, in the style of TaskReferenceInput: TaskPriorityInput, TargetBoardInput, NewNodeBodyInput, ChangedBodyInput, ChangedColorInput, ChangedNameInput, CommentReferringInput (id + task).
  timestamp: 2026-10-21T15:00:32.764569+00:00
- actor: claude-code
  id: 01m5fgcg8r1ccb802k3x0fxdad
  text: |-
    ### implement — changed
    - Duplication: one protocol plus one `make…Field()` factory per shared input field. TaskPriorityInput/makeTaskPriorityField (TaskMutations.swift); TargetBoardInput, NewNodeBodyInput, ChangedBodyInput, ChangedNameInput, ChangedColorInput with makeTargetBoardField/makeNewBodyField/makeChangedBodyField/makeChangedNameField/makeChangedColorField (MutationResolvers.swift, shared-input-fields section); CommentReferringInput with makeCommentReferenceField/makeCommentTaskField (CommentMutations.swift). All input types of TagMutations, ColumnActorMutations, CommentMutations, TaskMutations and BoardInput use them. taskReferenceField renamed makeTaskReferenceField at every call site.
    - Doc comments: UpdateTaskInput.column (top when the priority moves it), actorRef / UpdateColumnInput.id / UpdateActorInput.id / AssignTaskInput.actor / UpdateTagInput.id / RenameTagInput.from list the stored form and the name form; BoardInput says null for board gives the current board; AddTagInput.name says the tag name rule applies.
    - Descriptions, each traced in code: addTask, updateTask, newTaskOrdinal (priority move wins over the ordinal); newTagName (TagName rule, newNodeKey forms); slugReferenceText + actor forms + tag forms (stored form); updateColumnInput (null rule); updateCommentInput (null clears); undo/redo/undoTransaction (redo target is an undo that is not a redo; UNDO_CONFLICT unless force); Change (tracked fields + batch rule, worded without "patch" so the public SDL keeps no patch text); Change.txn (collectBoards cannot be reversed); NodeUpdate.fields (lists the tracked fields, names untracked ones); FieldChange; Subscription.changes; Query.boards (current repo included); Node.body; signal cosine; Priority scalar (case does not matter); FieldConflict.winner (empty body gives empty text); CollectedBoard.names (resolved keys, once each); Board.model (or null, no "no call set it" claim); checkLinks (dropped the unverified old-name warning claim); CollectBoardsResult.dryRun; filter ^id (tasks of the board that depend on them); LinkStatus.OK / OLD_NAME (or the board cannot be read).
    - Left alone as asked: linkStatus, linkTarget, collectResultRepairs, collectResultOtherLinks, VirtualTag explanation.
    - Golden Tests/Fixtures/kanban.graphql re-recorded with GRAPHQL_GOLDEN_RECORD=1. Full `swift test`: 1728 tests in 144 suites passed; the only build warning is the third-party mlx "missing creator for mutated node". All 17 findings of the 09:47 and 09:53 sections are checked. Not committed; task stays in doing.
  timestamp: 2026-10-21T15:13:27.832358+00:00
- actor: claude-code
  id: 01m5fgfep4xhd8xjmr6cz8akth
  text: |-
    ### test — green
    - evidence: `swift test` — 1728 tests in 144 suites passed, 0 failed, 0 skipped; `swift build --build-tests` in IntegrationTests/ — Build complete, exit 0. No package-code warnings; the only compiler warning is third-party (mlx-swift_Cmlx.bundle "missing creator for mutated node").
    - next: review
  timestamp: 2026-10-21T15:15:04.516046+00:00
- actor: claude-code
  id: 01m5fgwe2avpmknawp6qn1j1y7
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` on db30d62: 1 finding (1 confirmed, 0 refuted) — TaskTransferMutations.swift:443. Prior-finding check: 16 of 17 fixed; actorRef doc comment not fixed — TaskMutations.swift:262. Description check of db30d62: 82 checked, 6 wrong — MutationResolvers.swift:115, MutationResolvers.swift:148, SchemaDescription+Changes.swift:8, SchemaDescription+Mutations.swift:275, SchemaDescription+Types.swift:33, SchemaDescription+Types.swift:337. EndpointConventionTests pass (golden SDL matches). Older descriptions left to 01M5FFBDY50R40FT79XDD9G87W.
    - next: fix the 8 open items in the 10:15 sections, re-record Tests/Fixtures/kanban.graphql, commit, and review again.
  timestamp: 2026-10-21T15:22:09.866565+00:00
- actor: claude-code
  id: 01m5fgx3psjsx2y3fkjh48qwcz
  text: |-
    ### finish iteration 3 — findings
    - implement: changed — 13 files, 17/17 findings worked, field factories, descriptions traced and simplified
    - test: green — swift test 1728 / 144; IntegrationTests build ok
    - commit: db30d62
    - review: findings — TaskTransferMutations.swift:443, TaskMutations.swift:262, MutationResolvers.swift:115, MutationResolvers.swift:148, SchemaDescription+Changes.swift:8, SchemaDescription+Mutations.swift:275, SchemaDescription+Types.swift:33, SchemaDescription+Types.swift:337
  timestamp: 2026-10-21T15:22:32.025445+00:00
- actor: claude-code
  id: 01m5fh86kd998z9r174dn3sp4b
  text: |-
    ### research + implement (review round 4)
    Traced each of the 8 open items before writing:
    - make…Field call sites: only placementFields (TaskTransferMutations.swift) lacked `Self.`; every other call site already used it. Fixed.
    - actorRef: `nodeRef(for:ofType: .actor)` -> `storedRef` -> RefText sorts a full URI, the stored form `<type>/<id>`, or a short form; `candidateRef` for .actor uses `Slug.normalizedText(of: key)`, so a name that gives the slug works. Doc comment now lists all four forms; `actorRefs` points at actorRef for the forms. Sibling refs in TaskMutations.swift checked: `UpdateTaskInput.column` ("a full URI, the slug, or a name") is right as is: `columnRef(forMoveTo:)` slugs any non-URI text first (`Slug(columnOrActorName:)`), so `column/x` is not read as the stored form. Task refs ("a full URI or a short form") match the schema taskReference text and were left alone.
    - TargetBoardInput: conformers are AddColumnInput, AddActorInput, AddTaskInput, AddTagInput, RenameTagInput, BoardInput (initBoard/updateBoard). renameTag uses `MutationBoard.holding(input.from, orNamed: input.board)`; `reference` takes the board key of a parsed URI first. Doc comment fixed; the same rule also added to the schema `renameFrom` description, so the SDL says it too.
    - ChangedColorInput.color: `TagNode.resolvedColor` = `color ?? AutoColor.color(forText: slug)`; actor color is `state.color` (optional). Doc comment fixed.
    - Change: `ChangeRound.changes(of:atPath:)` -> `changesOfOtherBoards` -> `ChangeBuilder.changesOfOtherBoards(ofBatch:)` with `tasks(assignedToActorsPatchedBy:)` (live tasks only, kept with keepingNoFieldChange: true); derived updates skip tombstones. Description now scopes the first rule to a transaction of this board and adds the other-board rule; the batch rule is kept.
    - UpdateColumnInput: `input.order.map(PatchValue.integer)` unsets order; Replay reads `removeInteger(forKey: order) ?? 0`. Schema text and the Swift doc comments (type and `order` property) now say null gives the order 0.
    - Query.boards: `isCandidate` = `.git` entry or an existing board directory. Text says "repo or board folder".
    - SearchSignals.cosine: `matchesOfNewestCatalog` returns nil until the loop is idle on the newest catalog; then `hasCosine` is false and cosine is nil. Text says so.
    - Not touched (task 01M5FFBDY50R40FT79XDD9G87W): linkStatus, linkTarget, collectResultRepairs, collectResultOtherLinks, VirtualTag.explanation.
    - Golden re-recorded with `GRAPHQL_GOLDEN_RECORD=1 swift test --filter EndpointConventionTests` (4 passed); the SDL diff is description lines only.
  timestamp: 2026-10-21T15:28:35.437195+00:00
- actor: claude-code
  id: 01m5fh894356syvrzkz6wb4a6j
  text: |-
    ### implement — changed
    - evidence: 8 files — Sources/FoundationModelsKanban/GraphQL/TaskTransferMutations.swift, TaskMutations.swift, MutationResolvers.swift, ColumnActorMutations.swift, SchemaDescription+Changes.swift, SchemaDescription+Mutations.swift, SchemaDescription+Types.swift, Tests/Fixtures/kanban.graphql. `swift test`: 1728 tests in 144 suites passed, exit 0; the only build warning is the third-party "missing creator for mutated node … mlx-swift_Cmlx.bundle", no package-code warnings. All 8 items of the two 10:15 sections are checked. Not committed; task in doing.
    - next: /review
  timestamp: 2026-10-21T15:28:38.019862+00:00
- actor: claude-code
  id: 01m5fhbfc7fk4yda8pxcfdwa6y
  text: |-
    ### test — green
    - evidence: `swift test` — 1728 tests in 144 suites passed, 0 failed, 0 skipped; no package-code compiler warnings (only third-party mlx-swift_Cmlx bundle linker warning, out of scope). `swift build --build-tests` in IntegrationTests/ — Build complete, no package-code warnings.
    - next: review
  timestamp: 2026-10-21T15:30:22.727485+00:00
- actor: claude-code
  id: 01m5fhqmcaqdxveqwxa06vntqr
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (d02d62d): engine counts 0 findings, 0 confirmed, 0 refuted, 7 files attempted. All 8 findings of the 10:15 sections are fixed in the code. `swift test --filter EndpointConventionTests`: 4 tests passed (the golden SDL matches). Description check of d02d62d: 11 checked, 1 wrong — Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Changes.swift:10 (`Change`: the other-board Change comes only when this board did not change, and the batch rule for an assigned task follows the last transaction that wrote the actor).
    - next: implement the 10:34 item, record Tests/Fixtures/kanban.graphql again, commit, then /review 01M5F23SEC4X5S9D80NESC56VK HEAD~1..HEAD.
  timestamp: 2026-10-21T15:37:01.066937+00:00
- actor: claude-code
  id: 01m5fhr7yjvr85008a05c2szqx
  text: |-
    ### finish iteration 4 — findings
    - implement: changed — 8 files, 8/8 findings worked
    - test: green — swift test 1728 / 144; IntegrationTests build ok
    - commit: d02d62d
    - review: findings — SchemaDescription+Changes.swift:10 (Change description cross-board/batch rule; same description flagged in iteration 3 at :8)
  timestamp: 2026-10-21T15:37:21.106225+00:00
- actor: claude-code
  id: 01m5fj3xh4x5ts2hzq264xea5x
  text: |-
    ### research + implement (review round 5)
    - As directed, no third detailed rule set in the SDL. `Change` now says only: one transaction in the history or change feed of a board (txn, time, actor, mutations, boards, its updates of that board's nodes); an update tells which node and which tracked fields changed, so read the nodes again; transactions read together (for example after a git pull) can give one Change with an update for each node, so a Change can hold updates of nodes its transaction did not write.
    - Same cause removed from the rest of the change descriptions: `Change.updates` ("The updates of the change that the filter keeps"), `NodeUpdate`, `NodeUpdate.kind`, `FieldChange.before/after/added/removed/diff` ("the update", not "the transaction": in a batch the values span the whole batch), and the public `UpdateKind` type and value descriptions in Observe/Change.swift ("The transaction made the node" etc. were wrong for batched and cross-board updates).
    - The exact rules now live in Swift doc comments, traced against the code:
      - `ChangeBuilder` type doc: what a batch is (one `LiveGraphChange`, or every transaction of all changed boards in one `ChangeRound` for `changesOfOtherBoards(ofBatch:)`; `change(of:markingUndone:)` = batch of one, as in Board.history); each node has at most one update per batch; a patched node goes to the last transaction that patched it, kept with no field change, in first-patch order within that transaction; a patched node missing from the graph after gets none; other live nodes with changed fields go to the last transaction, slot order; values compare before the first and after the last transaction of the batch.
      - `ChangeBuilder.changesOfOtherBoards(ofBatch:)`: the written nodes belong to other boards; a live task whose assignee actor a transaction patched goes to the last transaction that patched one of its assignee actors (`lastPatchers`), kept with no field change; every other changed live node goes to the last transaction.
      - `ChangeRound` type doc, `changes(of:atPath:)`, and `changesOfOtherBoards(in:)`: a board that changed gets only its own transactions (live-graph changes in the order they happened, `txn` order within each) and nothing from other boards, even when the same call changed them (`guard let own = changed[path]`); a board that did not change gets one batch over all changed boards' transactions in `txn` order.
      - Discovered: the old `ChangeRound` doc said only boards "whose tasks depend on a task of a board that changed" get cross-board changes. The code gives them to every subscribed board that did not change. `BatchTransaction.grouping` said "order of the first event", but `groupedByTransaction()` sorts by `txn`. Both are corrected.
      - `Change`, `NodeUpdate`, `FieldChange`, and `UpdateKind` struct/enum doc comments now say "batch", not "transaction", and point to ChangeBuilder/ChangeRound.
    - Golden Tests/Fixtures/kanban.graphql re-recorded with `GRAPHQL_GOLDEN_RECORD=1 swift test --filter EndpointConventionTests` (4 passed). The SDL diff has description lines only.
  timestamp: 2026-10-21T15:43:43.652736+00:00
- actor: claude-code
  id: 01m5fj401mxkg0mwatat3xk0rx
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Changes.swift, Sources/FoundationModelsKanban/Observe/Change.swift, Sources/FoundationModelsKanban/Observe/ChangeBuilder.swift, Sources/FoundationModelsKanban/Observe/ChangeRound.swift, Tests/Fixtures/kanban.graphql. `swift test`: 1728 tests in 144 suites passed, exit 0. The only build warning is the third-party "missing creator for mutated node … mlx-swift_Cmlx.bundle". There are no package-code warnings. The 10:34 finding is checked; 0 open findings. Not committed; task in doing.
    - next: /review
  timestamp: 2026-10-21T15:43:46.228192+00:00
- actor: claude-code
  id: 01m5fj7a7j9y50ngjb59yq0fct
  text: |-
    ### test — green
    - evidence: swift test — 1728 tests in 144 suites passed, 0 failed, 0 skipped; swift build --build-tests in IntegrationTests/ — Build complete, exit 0. Only warning: third-party mlx-swift_Cmlx.bundle "missing creator for mutated node" (out of scope). Replay "warning" log lines are expected output of passing tests.
    - next: review
  timestamp: 2026-10-21T15:45:34.962352+00:00
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

## Review Findings (2026-10-21 09:47)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 3 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `Tests/Fixtures/kanban.graphql` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift:676` `swift/fluent-usage` — Factory method should begin with `make` per Swift API Design Guidelines. Rename to `makeTaskReferenceField()` to follow the convention that factory methods begin with `make`.

### Prior-finding check and description spot-check (2026-10-21 09:53)

> The caller asked for proof that each earlier finding is fixed, and for a fresh sample of descriptions checked against their resolvers. Earlier findings: the task-id duplication, undo/UndoInput.txn, addTag, Move/CopyTaskInput.column, UpdateTaskInput and Actor/Tag.color are fixed in the code. AddTagInput.name is still not exact (item below). Descriptions changed in 078e5e7: 31 checked, 6 still wrong. Fresh sample of descriptions that 078e5e7 did not change: 120 checked, 6 that this task added (a46ca01) are wrong. Six more mismatches are in descriptions older than this task (linkStatus, linkTarget, collectResultRepairs, collectResultOtherLinks from 77354ea/0f33760; VirtualTag.explanation from a578709). They are outside this task and are not listed here. Record Tests/Fixtures/kanban.graphql again after each fix.

- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Mutations.swift:410` `description/accuracy` — `AddTagInput.name` says "No name gives the id as the name: the text of a short form, or the slug of a full URI or of the stored form tag/<slug>." addTag sets the name to `TagName(normalizing: key).name` (TagMutations.swift; the rule is in Tags/TagSlug.swift): NUL removed, ends trimmed, each run of white space becomes `_`. So the short form `Bug Fix` gives `Bug_Fix`, not its text. For the stored form, `RefResolver.newNodeKey` gives the `<id>` part as written, not a slug. Say: "No name gives the id after the tag name rule: the short form, the id of a full URI, or the <id> part of the stored form tag/<id>."
- [x] `Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift:694` `duplication/duplication` — `InputField("priority", at: \.priority).description(SchemaDescription.taskPriority)` is written out the same way in AddTaskInput (:694) and UpdateTaskInput (:705). This is the same cause as the task `id` finding. Give it one helper, in the style of `taskReferenceField()`. The same cause is also in files that this task changed: `boardToChange`, `changedBody`, `newNodeBody`, `changedColor`, `changedName`, `commentReference` and `commentTask` input fields are repeated in TagMutations.swift, ColumnActorMutations.swift, CommentMutations.swift and MutationResolvers.swift.
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Changes.swift:13` `description/accuracy` — `Change.txn` says "Give it as txn to undo to reverse this change, or to redo to apply it again after its undo." For a collectBoards transaction, `UndoLog.target` (Undo/UndoLog.swift) throws `nothingToUndo`. Add "A collectBoards change cannot be reversed."
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription.swift:405` `description/accuracy` — `FieldConflict.winner` says "Null when the field has no value." For body the winner is `merged.body` (CrossRepo/BoardCollect.swift), a non-optional String: an empty body gives "", never null. Say: "Null when a property has no value. An empty body gives the empty text."
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription.swift:388` `description/accuracy` — `CollectedBoard.names` says "the board ref of the call". `CollectedSource` (CrossRepo/BoardCollect.swift) stores the key that the ref resolved to, not the text of the ref, and each name only once. Say: "The names of the source board, each one time: the key that the board ref of the call gave, its board IDs, its git key, and its old names."
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Types.swift:32` `description/accuracy` — `Query.boards` says "the repos next to the current repo, and the repos in each search root of the config." `BoardLocator.places(around:)` (CrossRepo/BoardLocator.swift) scans the parent folder of the current repo, so the current repo is in the list too. Say: "each repo one level down in the parent folder of the current repo, the current repo included, then in each search root of the config."
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Mutations.swift:265` `description/accuracy` — `UpdateColumnInput` says "A field that is not set does not change." In `updateColumn` (ColumnActorMutations.swift), null clears the order and the body, and null for the name gives no change and a warning. This is the same cause that 078e5e7 fixed for UpdateActorInput and UpdateTagInput. Use the same wording.
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Mutations.swift:38` `description/accuracy` — `slugReferenceText` (actorReference, columnReference) and `newTaskAssignees` / `changedTaskAssignees` leave out the stored form `actor/<slug>` / `column/<slug>`. RefResolver accepts that form (RefResolver.swift), and `tagForms` lists `tag/<slug>`. Say: "a full URI, the stored form <type>/<slug>, the slug, or a name that gives the slug."
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Types.swift:344` `description/accuracy` — The `Priority` scalar lists "urgent, critical, high, p0, p1, or true … low, p3, or p4". `PriorityMove.init(of:)` (GraphQL/PriorityInput.swift) looks up `value.text.lowercased()`, so `HIGH` and `P0` move the task too. `taskPriority` (SchemaDescription.swift) writes `P0, P1`. Add "The case does not matter." to both.
- [x] `Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift:83` `description/accuracy` — The doc comment on `UpdateTaskInput.column` says the task goes "at the end of the column". `place(of:movingTo:by:resolvingWith:at:)` puts it at the top when the priority moves it. 078e5e7 corrected `updateTaskColumn` but not this comment. The same cause, "a full URI or the slug" with the name form left out, is in the doc comments of `actorRef` (TaskMutations.swift:252), `UpdateColumnInput.id` (ColumnActorMutations.swift:93) and `UpdateActorInput.id` (ColumnActorMutations.swift:137). The `BoardInput` comment (MutationResolvers.swift:115) also says "null clears the field", but a null `board` gives the current board.
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Changes.swift:7` `description/accuracy` — `Change` says "one update for each node that the transaction changed, also each node whose derived fields changed." `ChangeBuilder` (Observe/ChangeBuilder.swift) compares only the tracked fields. `Column.taskCount` / `readyCount` are not tracked, so a task move gives no update to its columns. When one batch holds several transactions, `changes(ofBatch:patching:)` puts a node's update only in the last transaction that patched it. Say which fields are tracked, and give the batch rule.
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Changes.swift:54` `description/accuracy` — `NodeUpdate.fields` says "The change of each public field of the node". Only the `trackedFields` of each type are compared (ChangeBuilder.swift). `created`, `updated`, `key`, `boardId`, `names`, `path`, `taskCount`, `readyCount`, the child-node lists and the fields with arguments are never reported. Say "each tracked field that changed", and name the fields that are not tracked.
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Mutations.swift:101` `description/accuracy` — `Mutation.addTask` says "The task goes to the end of its column, unless the input gives an ordinal or a priority." In `PriorityMove` (GraphQL/PriorityInput.swift), medium, normal, p2 and any other value are `.stay`, so the task still goes to the end. low, p3 and p4 send it to the end, and an ordinal given with them is ignored with `ORDINAL_IGNORED`. Say: "The task goes to the end of its column, unless a priority moves it to the top. An ordinal gives the place when the priority makes no move. A priority that moves the task wins over the ordinal."
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Mutations.swift:106` `description/accuracy` — `Mutation.updateTask` says "A column moves the task to the end of that column." `WorkingCopy.place(of:movingTo:by:resolvingWith:at:)` (TaskMutations.swift) puts it at the top when the priority moves it there. 078e5e7 corrected `updateTaskColumn` for this. Add "or to the top when the priority moves it there."
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Mutations.swift:315` `description/accuracy` — `AddTaskInput.ordinal` says "No ordinal puts the task at the end of the column." With no ordinal, urgent, critical, high, p0, p1 or true puts the task at the top. A given ordinal is ignored when the priority moves the task (`PriorityMove.ordinalWarning`). Say: "No ordinal puts the task at the end of the column, unless the priority moves it. A priority that moves the task wins over the ordinal."
- [x] `Sources/FoundationModelsKanban/GraphQL/CheckLinksField.swift:158` `description/accuracy` — `LinkStatus.OK` says "The link names its board by a current name, and the board has the node." For a related board that cannot be read, `LinkedBoard.check(of:)` (CrossRepo/LinkCheck.swift) gives `.ok` without checking the node. Say: "…and the board has the node, or the board cannot be read."

## Review Findings (2026-10-21 10:15)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 12 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `Tests/Fixtures/kanban.graphql` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/GraphQL/TaskTransferMutations.swift:443` `completeness/invariant-propagation` — Factory method called without `Self.` prefix, inconsistent with the established pattern — all other factory method calls in this change (makeNewBodyField, makeTargetBoardField, makeTaskReferenceField, makeChangedBodyField, makeTaskPriorityField) consistently use the `Self.` prefix to invoke other static methods in the SchemaBuilder extension. Change line 443 from `makeTaskReferenceField()` to `Self.makeTaskReferenceField()` for consistency with the pattern established throughout the change.

### Prior-finding check and description spot-check (2026-10-21 10:15)

> The caller asked for proof that each of the 17 findings of the 09:47 and 09:53 sections is fixed in db30d62, and for a check of every description that db30d62 changed against its resolver. 16 of the 17 are fixed in the code. The `actorRef` part of the `UpdateTaskInput.column` finding is not fixed (item below). `swift test --filter EndpointConventionTests` passes, so Tests/Fixtures/kanban.graphql matches the Swift strings. Descriptions and doc comments that db30d62 added or changed: 82 checked, 6 wrong. Mismatches in descriptions older than this task (linkStatus, linkTarget, collectResultRepairs, collectResultOtherLinks, VirtualTag.explanation) are covered by 01M5FFBDY50R40FT79XDD9G87W and are not listed here. Record Tests/Fixtures/kanban.graphql again after each fix.

- [x] `Sources/FoundationModelsKanban/GraphQL/MutationResolvers.swift:115` `description/accuracy` — The `TargetBoardInput` doc comment says it is "the input of a mutation that makes a node, of `renameTag`, and of `initBoard` and `updateBoard`". `addComment` and `copyTask` make nodes, but `AddCommentInput` (CommentMutations.swift) and `CopyTaskInput` (TaskTransferMutations.swift) do not conform. The `board` property says "`nil` for the current board", but `renameTag` uses `MutationBoard.holding(input.from, orNamed: input.board)` (TagMutations.swift), and `MutationBoard.reference` (MutationResolvers.swift) takes the board key of a full-URI `from` first: then `nil` does not give the current board, and a given `board` is ignored. Say: "the input of `addColumn`, `addActor`, `addTask`, `addTag`, `renameTag`, `initBoard`, and `updateBoard`", and for the property add "For `renameTag`, a full URI in `from` names the board, and this field is ignored."
- [x] `Sources/FoundationModelsKanban/GraphQL/MutationResolvers.swift:148` `description/accuracy` — The `ChangedColorInput.color` doc comment says "`null` clears the color." For a tag, `updateTag` unsets the stored color, but `TagObject.color` returns `state.resolvedColor` (QueryResolvers.swift), which is `color ?? AutoColor.color(forText: slug)` (Tags/AutoColor.swift). A tag never shows a cleared color. Say: "`null` clears the stored color: an actor then has no color, and a tag shows the auto color of its slug."
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Changes.swift:8` `description/accuracy` — `Change` says "It has an update for each node that the transaction wrote, and for each other live node whose tracked fields changed." When this board's log did not change, `ChangeRound.changes(of:atPath:)` calls `changesOfOtherBoards(in:)` (Observe/ChangeRound.swift): a transaction of a different board gives a Change that holds none of the nodes it wrote. `ChangeBuilder.changesOfOtherBoards(ofBatch:)` (Observe/ChangeBuilder.swift) also adds an update for each live task whose assignee is an actor that the transaction patched, kept with `update(of:keepingNoFieldChange: true)` even when no field of the task changed. Say: "In Subscription.changes, a transaction of a different board gives a Change with the updates of the nodes of this board whose tracked fields changed, and of each live task whose assignee is an actor that the transaction wrote, also when no field of the task changed."
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Mutations.swift:275` `description/accuracy` — `UpdateColumnInput` says "Null clears the order or the body". `updateColumn` (ColumnActorMutations.swift) sends `input.order.map(PatchValue.integer)`, so null unsets `order`, and replay reads a missing order as 0 (`properties.removeInteger(forKey: PropertyName.order) ?? 0`, Events/Replay.swift). Null gives the order 0, which sorts the column toward the front. Say: "Null for the order gives the order 0; null clears the body; null for the name gives no change and a warning."
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Types.swift:33` `description/accuracy` — `Query.boards` says "each repo one level down in the parent folder of the current repo". `BoardLocator.repos(in:)` keeps each folder that `isCandidate(_:)` accepts: a `.git` entry, or a `.kanban/` with no git (a board outside git, CrossRepo/BoardLocator.swift). Say: "each repo or board folder one level down in the parent folder of the current repo, the current repo included, then in each search root of the config."
- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Types.swift:337` `description/accuracy` — db30d62 changed `SearchSignals.cosine` from "Null when the search has no embedder, or the embeddings are not done yet" to "Null when the search gives no cosine score, for example with no embedder." `TaskSearch.rankedMatches(for:limit:)` (Search/TaskSearch.swift) uses the keyword searcher until the embedded catalog holds the newest catalog, also with an embedder, and `signals(of:withCosine:)` then gives `cosine: nil`. Say: "Null when the keyword searcher ranked the hit: the search has no embedder, or the embeddings of the newest catalog are not done yet."
- [x] `Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift:262` `description/accuracy` — The 09:53 `UpdateTaskInput.column` finding named the `actorRef` doc comment; it still says "`id`: The ref as the caller wrote it: a full URI or the slug." `RefResolver.actorRef(for:includingTombstones:)` calls `nodeRef(for:ofType: .actor)`, which also accepts the stored form `actor/<slug>` and a name that gives the slug. Say: "a full URI, the stored form actor/<slug>, the slug, or a name that gives the slug."

## Review Findings (2026-10-21 10:30)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 3 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `Tests/Fixtures/kanban.graphql` — no validator matches this file

### Prior-finding check and description spot-check (2026-10-21 10:34)

> The caller asked for proof that each of the 8 findings of the 10:15 sections is fixed in d02d62d, and for a check of every description and doc comment that d02d62d changed against its resolver. All 8 are fixed in the code: `Self.makeTaskReferenceField()` in placementFields; the `TargetBoardInput` conformers are exactly AddColumnInput, AddActorInput, AddTaskInput, AddTagInput, RenameTagInput and BoardInput (initBoard, updateBoard), and `MutationBoard.reference` takes the board key of a full-URI `from`; `ChangedColorInput.color` matches `ActorObject.color` (stored, optional) and `TagObject.color` (`resolvedColor`); `UpdateColumnInput` matches `input.order.map(PatchValue.integer)` and the `?? 0` in Events/Replay.swift; `Query.boards` matches `BoardLocator.isCandidate(_:)`; `SearchSignals.cosine` matches `TaskSearch.rankedMatches(for:limit:)` and `EmbeddedTaskCatalog.matchesOfNewestCatalog(for:limit:)`; the `actorRef` / `actorRefs` doc comments list every form that `nodeRef(for:ofType:)` accepts. `swift test --filter EndpointConventionTests` passes (4 tests), so Tests/Fixtures/kanban.graphql matches the Swift strings. Descriptions and doc comments that d02d62d changed: 11 checked, 1 wrong. Mismatches in descriptions older than this task (linkStatus, linkTarget, collectResultRepairs, collectResultOtherLinks, VirtualTag.explanation) are covered by 01M5FFBDY50R40FT79XDD9G87W and are not listed here. Record Tests/Fixtures/kanban.graphql again after the fix.

- [x] `Sources/FoundationModelsKanban/GraphQL/SchemaDescription+Changes.swift:10` `description/accuracy` — `Change` now says "In Subscription.changes, a transaction of a different board gives a Change with …", and keeps the batch rule "a node has one update only: in the last transaction of the batch that wrote the node, else in the last transaction of the batch." Two parts do not match the code. (1) `ChangeRound.changes(of:atPath:)` (Observe/ChangeRound.swift) calls `changesOfOtherBoards(in:)` only when this board's log did not change (`guard let own = changed[path] else`). When one write changes this board and a different board (for example moveTask to a different board), the transactions of the different board give no Change to this board. (2) In `ChangeBuilder.changesOfOtherBoards(ofBatch:)` (Observe/ChangeBuilder.swift), the patched set of a transaction is `tasks(assignedToActorsPatchedBy:)`, and `lastPatchers(of:)` puts the update of such a task in the last transaction of the batch that wrote the actor, not in the last transaction that wrote the task, and not in the last transaction of the batch. Say: "In Subscription.changes, when this board did not change, a transaction of a different board gives a Change with …", and give the batch rule for the assignee case: "the update of a task whose assignee is an actor of a different board is in the last transaction of the batch that wrote that actor."