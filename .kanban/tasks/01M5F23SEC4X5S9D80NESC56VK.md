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
depends_on:
- 01M5F23FSEG4MRQ3NWWD7SGPAZ
position_column: todo
position_ordinal: '8280'
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