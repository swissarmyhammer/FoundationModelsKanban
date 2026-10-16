---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m51174fmvc05nnpr5j1ph4x4
  text: |-
    Research:
    - The walk removes a removed parameter in RewriteWalk.visitNamedValue. It returns a TextEdit for the range of the name and the value. It does not visit the value, so a variable in the value records no use.
    - The GraphQL parser gives each node a location that ends at its first token (loc is made before the children parse). Thus the span of a variable definition must come from the tokens: from its `$` to the start of the next definition, or to the closing parenthesis.
    - `visit(root:visitor:)` of the GraphQL module is internal, so the rewrite cannot use it. The uses of a variable must come from our own walk of the syntax tree: arguments, directives (on operations, fields, fragments, spreads), and the fragments that the operation spreads, at all depths.
    - An extra value in `variables` with no definition is ignored by execution, so the value of a removed definition needs no change.
    Plan: record the range of each removal edit. After the walk, for each operation, find the uses of each variable (also through spread fragments). A definition whose uses are all in removed ranges goes out. When no definition stays, the parentheses go out. A variable that the caller did not use at all stays as it is (validation still reports it).
  timestamp: 2026-10-16T00:19:01.236007+00:00
- actor: claude-code
  id: 01m511v4k6hhb511y0azw8gd5w
  text: |-
    Implementation landed (TDD).
    - RED: the new tests failed with "Variable \"$d\" is never used." (GRAPHQL_VALIDATION_FAILED) for the 3 cases with no other read, as expected.
    - New file S/GraphQL/VariableReads.swift: `VariableReads.variables(readBy:in:)` walks an operation (arguments, directives of the operation, fields, inline fragments, spreads) and each fragment that it spreads, at all depths, and gives each Variable node.
    - NameRewrite.swift: RewriteWalk records the range of each removed parameter (`removedRanges`). New `takeOutUnreadDefinitions(of:)` runs after `visit(_:)` in `DocumentRewriter.rewrittenDocument`. A definition whose every read is in a removed range goes out: from its `$` to the next definition, or to `)`. When all definitions go out, the edit takes out `(`…`)`. New Token helper `previousSignificant`.
    - A variable that the caller defined and never read keeps its definition (validation still reports it). This keeps the change to the removed-parameter case only.
    - divergence.md P4: added a DECIDED line for this behavior.
    - Note: default swiftlint reports file_length and type_body_length on NameRewrite.swift. Both were already over the limits before this change (1149 lines). The project has no .swiftlint.yml, and the review tool rules do not enable these two rules.
    - Test run under load: the first full run failed only on the 60 s time limit in 5 cross-repo/change-feed suites. Those suites passed alone (45 tests), and the next full run passed: 1544 tests in 122 suites.
  timestamp: 2026-10-16T00:29:56.710458+00:00
- actor: claude-code
  id: 01m511vb5jxr01g0yk7gderg3e
  text: |-
    ### implement — changed
    - evidence: 5 files — Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift, Sources/FoundationModelsKanban/GraphQL/VariableReads.swift (new), Tests/FoundationModelsKanbanTests/GraphQL/RemovedParameterTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift, divergence.md. New tests: 13 cases (6 execute + 6 text + 1 guard). `swift test`: 1544 tests in 122 suites passed.
    - next: /review
  timestamp: 2026-10-16T00:30:03.442279+00:00
- actor: claude-code
  id: 01m5124h0mtzfyzvt5ba3fwcz6
  text: |-
    ### test — green
    - evidence: swift build — complete, only the allowed SwiftPM "missing creator" warning. swift test — 1544 tests in 122 suites passed, 0 failed, 0 skipped. swift test --package-path IntegrationTests (with the integration scratch path) — 3 tests in 3 suites passed, 0 failed. Full suite ran one time. No time-limit failures.
    - next: review
  timestamp: 2026-10-16T00:35:04.340564+00:00
- actor: claude-code
  id: 01m5125783ekns6p9yqnyn8s65
  text: |-
    ### commit — changed
    - evidence: local commit "fix(rewrite): take out an unread variable definition after a removed parameter (^164tehz)". Files: Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift, Sources/FoundationModelsKanban/GraphQL/VariableReads.swift, Tests/FoundationModelsKanbanTests/GraphQL/RemovedParameterTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift, divergence.md, and the changed .kanban/tasks files. The sha is in the step block of the caller, because a comment cannot hold its own sha. Not pushed.
    - next: review
  timestamp: 2026-10-16T00:35:27.107757+00:00
position_column: doing
position_ordinal: '80'
title: Take out the unused variable definition when the rewrite removes a removed Rust parameter whose value is a variable
---
## What
This is work on the Swift package (S/ = Sources/FoundationModelsKanban/). Code: S/GraphQL/NameRewrite.swift.

The name rewrite takes a removed Rust parameter (`RemovedParameter`, divergence.md Q12 as P4 changed it) out of the document with a warning. When the value of that parameter is a variable, for example `mutation($d: String) { addTask(input: {title: "x", due: $d}) { id } }`, the variable `$d` has no use after the rewrite. GraphQL then gives the NoUnusedVariables validation error, and the call fails. This is not forgiving.

The walk does not know all the uses of a variable: it does not visit directive arguments, and it records only the first use.

## Acceptance Criteria
- [x] A removed parameter whose value is a variable works: the call runs, and the response has the "removed" warning.
- [x] When the variable has other uses (also in a directive), its definition stays.
- [x] When the variable has no other use, the rewrite takes out its definition (and the parentheses when no definition stays).

## Tests
- [x] A test for each criterion. Use temporary fixture folders. Never use the `.kanban/` of this repo.
- [x] `swift test` passes.

Found while working on ^y8nr5v3.