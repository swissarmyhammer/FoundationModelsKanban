---
comments:
- actor: wballard
  id: 01m4cf1vjyxyg54am9ka0mx8w5
  text: |-
    ^asw5155 changed this scope. `API.result` in Schema.swift now reads `KanbanError.responseError()` for a real purpose: it copies `ResponseError.message` and `ResponseError.extensions.code` into each GraphQL error that a `KanbanError` caused, so `execute` gives `extensions.code`. `ResponseError.Extensions` also got an explicit `CodingKeys` enum, and the code key comes from `CodingKeys.code`.

    Periphery run (`periphery scan --retain-public --report-exclude 'Tests/**' --relative-results -- --build-system native --build-tests`) after ^asw5155:
    - REMOVED by ^asw5155: `ResponseError.Extensions.code`, `ResponseError.message`, `ResponseError.extensions`.
    - STILL OPEN in this card: `ResponseError.path` (Errors.swift, the `let path: [PathComponent]` line) and `ErrorResponse.errors` (Errors.swift, the `let errors: [ResponseError]` line). The engine keeps the path of the GraphQL error, so production code still does not read `ResponseError.path`.

    The same run also reports four findings outside Errors.swift (NameRewrite `from`/`to`/`path`, `RewriteResponse.Extensions.rewrites`). ^cwazjga tracks them. This card is not moved or closed.
  timestamp: 2026-10-08T00:36:45.278070+00:00
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