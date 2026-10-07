---
position_column: todo
position_ordinal: b380
title: 'Periphery: assign-only findings in KanbanError.ResponseError and ErrorResponse'
---
## What
`periphery scan --retain-public --report-exclude 'Tests/**' -- --build-system native --build-tests` on main (with the ^a9rehs7 work in the tree) reports five `Assign-only property` warnings in `Sources/FoundationModelsKanban/GraphQL/Errors.swift`:
- `ResponseError.Extensions.code`, `ResponseError.message`, `ResponseError.path`, `ResponseError.extensions`, and `ErrorResponse.errors`.

The synthesized `Codable` and `Hashable` code reads these properties, and periphery cannot see these reads. The ^a9rehs7 work does not change `Errors.swift`.

## Fix
Add `// periphery:ignore` with a reason line to each property (the project rule for a property that only synthesized code reads), or set the periphery option that keeps `Codable` properties. Choose the form that the other periphery exemptions of the project use.

## Acceptance Criteria
- [ ] The periphery scan reports no finding in `Errors.swift`.
- [ ] `swift test` passes.