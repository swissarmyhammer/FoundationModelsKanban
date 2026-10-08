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
- actor: wballard
  id: 01m4cfmsg2fmsed6qxe7ma6s0h
  text: |-
    Research: the scan before the change reported 2 findings, both in Errors.swift: `ResponseError.path` and `ErrorResponse.errors`. Production code reads both, but only through the synthesized `encode(to:)`: `KanbanGraph.execute` catches a `KanbanError` and returns `responseJSON()`, which encodes `ErrorResponse(errors: [responseError()])`. That writes `errors`, and for each `ResponseError` it writes `path` (an empty list). `KanbanErrorTests.responseJSONHasOnlyErrors` holds that exact output (`{"errors":[{...,"path":[]}]}`), so the reads are real. Removing a property would change the error response JSON, so removal is not correct.

    Fix: `// periphery:ignore` above each property, with the reason on its own comment line above the marker. This is the same form as NameRewrite.swift and Schema.swift (`RewriteResponse.Extensions.rewrites`). `path`: "The synthesized `Encodable` and `Hashable` conformances read this property; periphery sees no reader." `errors`: "The synthesized `Encodable` conformance reads this property; periphery sees no reader." No code behavior changed, so no new test (only comments changed; the existing tests hold the JSON).
  timestamp: 2026-10-08T00:47:05.730938+00:00
- actor: wballard
  id: 01m4cfmw0zg61e0jyb7k7jscet
  text: |-
    ### implement — changed
    - evidence: 1 file — Sources/FoundationModelsKanban/GraphQL/Errors.swift. `periphery scan --retain-public --report-exclude 'Tests/**' --relative-results -- --build-system native --build-tests` gives "No unused code detected." `swift test` gives 848 tests in 50 suites passed, exit 0. The only build warning is the mlx-swift "missing creator for mutated node" kind that README.md records.
    - next: /review
  timestamp: 2026-10-08T00:47:08.319932+00:00
- actor: wballard
  id: 01m4cfrs3y9srz6b95z68nrw15
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (e7dfb63): 0 findings, 0 confirmed, 0 refuted; 7 validator runs, 0 failed. 1 file reviewed. 4 .kanban/ files are excluded by .reviewignore.
    - next: none. The task is in done.
  timestamp: 2026-10-08T00:49:16.414699+00:00
- actor: wballard
  id: 01m4cfrzgpxfgm1a3mnce9xa4y
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 1 file (GraphQL/Errors.swift); periphery: no unused code in the package
    - test: green — swift test, 848 passed; build warnings only the 2 accepted kinds
    - commit: e7dfb63
    - review: clean — 0 findings
  timestamp: 2026-10-08T00:49:22.966185+00:00
position_column: done
position_ordinal: ab80
title: 'Periphery: assign-only findings in KanbanError.ResponseError and ErrorResponse'
---
## What
`periphery scan --retain-public --report-exclude 'Tests/**' -- --build-system native --build-tests` on main (with the ^a9rehs7 work in the tree) reports five `Assign-only property` warnings in `Sources/FoundationModelsKanban/GraphQL/Errors.swift`:
- `ResponseError.Extensions.code`, `ResponseError.message`, `ResponseError.path`, `ResponseError.extensions`, and `ErrorResponse.errors`.

The synthesized `Codable` and `Hashable` code reads these properties, and periphery cannot see these reads. The ^a9rehs7 work does not change `Errors.swift`.

## Fix
Add `// periphery:ignore` with a reason line to each property (the project rule for a property that only synthesized code reads), or set the periphery option that keeps `Codable` properties. Choose the form that the other periphery exemptions of the project use.

## Acceptance Criteria
- [x] The periphery scan reports no finding in `Errors.swift`.
- [x] `swift test` passes.