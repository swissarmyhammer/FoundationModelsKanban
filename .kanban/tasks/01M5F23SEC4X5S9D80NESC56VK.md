---
assignees:
- claude-code
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