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
- [ ] A call that reaches a Rust `.kanban` sibling via `boards` gives warning `INCOMPATIBLE_BOARD`
- [ ] No `BOARD_INCOMPATIBLE` left in Sources, Tests, README, skill, or plan docs (unless kept as an alias for a found reader)
- [ ] Four rule-11 tests exist and pass; exceptions name a task id

## Tests
- [ ] IncompatibleBoardTests updated to the new code
- [ ] Golden, descriptions, conformance-with-alias-probe, tool-gives-endpoint tests