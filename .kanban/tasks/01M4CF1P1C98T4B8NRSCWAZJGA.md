---
position_column: todo
position_ordinal: b480
title: 'Periphery: assign-only findings in NameRewrite and RewriteResponse'
---
## What
`periphery scan --retain-public --report-exclude 'Tests/**' --relative-results -- --build-system native --build-tests` on main (with the ^asw5155 work in the tree) reports four `Assign-only property` warnings outside `Errors.swift`:
- `Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift`: `NameRewrite.from`, `NameRewrite.to`, `NameRewrite.path`.
- `Sources/FoundationModelsKanban/GraphQL/Schema.swift`: `RewriteResponse.Extensions.rewrites`.

The synthesized `Encodable` (and `Hashable`) code reads these properties, and periphery cannot see these reads. The ^asw5155 work does not change these types. ^3p88txm covers only the findings in `Errors.swift`.

## Fix
Add `// periphery:ignore` with a reason line above each property (the project rule for a property that only synthesized code reads), in the same form as ^3p88txm uses.

## Acceptance Criteria
- [ ] The periphery scan reports no finding in `NameRewrite.swift` and `Schema.swift`.
- [ ] `swift test` passes.