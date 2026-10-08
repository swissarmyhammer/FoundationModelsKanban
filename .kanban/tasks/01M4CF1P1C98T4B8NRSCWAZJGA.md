---
comments:
- actor: wballard
  id: 01m4cfcncqz9r900sq36d71fd3
  text: |-
    Research: the 4 properties are real output. `RewriteResponse.encode(to:)` encodes `Extensions(rewrites:)` into `extensions.rewrites` of each response, and the synthesized `Encodable` of `Extensions` and of `NameRewrite` reads the properties. The synthesized `Hashable` of `NameRewrite` also reads them (NameRewriteTests compare whole values). Thus the properties stay (dead-code-swift rule: do not delete; mark them). The project form is in `Undo/Inverse.swift`: the doc comment, then a `//` reason line, then `// periphery:ignore` on its own line.

    Periphery before the change (same command as the card): 6 findings, 2 in Errors.swift (^3p88txm), NameRewrite.swift from/to/path, Schema.swift `Extensions.rewrites`.

    Change: added the reason line and `// periphery:ignore` above `NameRewrite.from`, `NameRewrite.to`, `NameRewrite.path` (NameRewrite.swift) and above `RewriteResponse.Extensions.rewrites` (Schema.swift). No code change; the behavior of the name rewrite is the same.

    Periphery after: only `Errors.swift` `path` and `errors` stay (^3p88txm scope, not changed).
  timestamp: 2026-10-08T00:42:39.383729+00:00
- actor: wballard
  id: 01m4cfcqc5sy2g2gcyvpvnv8ha
  text: |-
    ### implement — changed
    - evidence: Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift, Sources/FoundationModelsKanban/GraphQL/Schema.swift. `periphery scan --retain-public --report-exclude 'Tests/**' --relative-results -- --build-system native --build-tests`: 0 findings in NameRewrite.swift and Schema.swift (2 remain in Errors.swift, ^3p88txm). `swift test`: 848 tests in 50 suites passed, 0 failures; only the mlx-swift `missing creator` warning that README.md accepts.
    - next: /review
  timestamp: 2026-10-08T00:42:41.413671+00:00
- actor: wballard
  id: 01m4cfgq35v254ms1ckyqvtvxv
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (aaee823). 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. 2 files reviewed. 4 .kanban/ files not reviewed (.reviewignore).
    - next: none. The task is in done.
  timestamp: 2026-10-08T00:44:52.197211+00:00
- actor: wballard
  id: 01m4cfgwk95bwcjwrvz2f4mqyp
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 2 files (GraphQL/NameRewrite.swift, GraphQL/Schema.swift); periphery 6 findings → 2 (both ^3p88txm)
    - test: green — swift test, 848 passed; build warnings only the 2 accepted kinds
    - commit: aaee823
    - review: clean — 0 findings
  timestamp: 2026-10-08T00:44:57.833745+00:00
position_column: done
position_ordinal: aa80
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
- [x] The periphery scan reports no finding in `NameRewrite.swift` and `Schema.swift`.
- [x] `swift test` passes.