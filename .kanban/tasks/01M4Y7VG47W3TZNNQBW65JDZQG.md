---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m50bh5dy8mmsfmy5d0mbwf0c
  text: |-
    Research done.
    - `TaskObject.trackedFields` (S/Observe/ChangeBuilder.swift) lists the Task fields. `FieldChange(named:from:to:)` already gives `added`/`removed` for a `.list` value. Derived updates compare all slots, so a new tracked field also flows to tasks that no patch changed.
    - `TaskObject.unresolvedDependsOn` (S/GraphQL/QueryResolvers.swift) gives `[NodeID]`; the tracked value is `.list` of the URI text.
    - A `dependsOn` URI of the current board to a missing task gives NOT_FOUND in RefResolver (local key lookup). A body marker to a missing task of the current board is stored (UnresolvedDependsOnTests.bodyMarkerToMissingTaskIsUnresolved). The tests use a body marker, so that no BoardLocator scan of the temp folder parent runs.
    - ChangeBuilderTests: `selections` uses `selections[name] ?? name`; `listFields` drives `expectedChange`.
  timestamp: 2026-10-15T18:00:01.214692+00:00
- actor: claude-code
  id: 01m50bt4ctyx6fdb0qqrbxb2qa
  text: |-
    ### implement — changed
    - evidence: 2 files. Sources/FoundationModelsKanban/Observe/ChangeBuilder.swift: `TaskObject.trackedFields` has `unresolvedDependsOn` as a `.list` of URI text, after `blockedBy`. Tests/FoundationModelsKanbanTests/Observe/ChangeBuilderTests.swift: `unresolvedField` constant, the field in `selections` and `listFields`, the cases `addMissingDependency` and `removeMissingDependency` (body marker to `missingTaskURI` on the temp fixture board), the helper `expectUnresolvedChange`, and 2 tests. Each test also compares each field change with a query (`expectFieldsEqualQueries`).
    - RED: 2 tests failed with "no field unresolvedDependsOn". GREEN: 2 tests passed. Full `swift test`: 1514 tests in 120 suites passed; only the accepted SwiftPM "missing creator" warning.
    - next: /review
  timestamp: 2026-10-15T18:04:55.066918+00:00
- actor: claude-code
  id: 01m50caky9af4mtva3381kdzzk
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 files
    - test: green — swift test, 1514 passed, 0 failed, 0 skipped; IntegrationTests 3 passed
    - commit: 0fc4e64
    - review: clean — none (review sha HEAD~1..HEAD: 0 findings, 0 confirmed, 1 refuted, 7 attempted, 0 failed)
  timestamp: 2026-10-15T18:13:55.273005+00:00
position_column: done
position_ordinal: ff8880
title: Send unresolvedDependsOn changes in the change feed
---
## What
Task ^d8r4c92 added the public field `Task.unresolvedDependsOn: [ID!]!` (divergence.md Q2). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

`TaskObject.trackedFields` in S/Observe/ChangeBuilder.swift lists the public Task fields that the change feed and `Board.history` compare. The list does not have `unresolvedDependsOn`. Thus no `FieldChange` shows when the list of unresolved targets of a task changes, for example when a related board becomes readable again, or when a URI with a typo is corrected.

## Acceptance Criteria
- [x] `trackedFields` has `unresolvedDependsOn` as a list field, with `added` and `removed`.
- [x] A change that adds a dependency on a missing task gives a `FieldChange` for `unresolvedDependsOn`.
- [x] A change that removes that dependency gives a `FieldChange` for `unresolvedDependsOn` with `removed`.

## Tests
- [x] Add `unresolvedDependsOn` to `ChangeBuilderTests.listFields` and the selection table, and add the cases above.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.