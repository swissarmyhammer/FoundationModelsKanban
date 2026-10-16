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
- actor: claude-code
  id: 01m512m4h7ermwsb1cxjjgvkyd
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (bed1d78) gave 5 findings (5 confirmed, 0 refuted): Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift:1167 (duplication/duplication), Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift:1167 (reuse/reuse), Tests/FoundationModelsKanbanTests/GraphQL/RemovedParameterTests.swift:102 (completeness/invariant-propagation), Tests/FoundationModelsKanbanTests/GraphQL/RemovedParameterTests.swift:280 (duplication/duplication), Tests/FoundationModelsKanbanTests/GraphQL/RemovedParameterTests.swift:283 (reuse/reuse).
    - next: Do the 5 items in the "Review Findings (2026-10-15 19:35)" section. The task stays in review.
  timestamp: 2026-10-16T00:43:35.847591+00:00
- actor: claude-code
  id: 01m512mrhj572vqt5q58vr703q
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — NameRewrite.swift, VariableReads.swift (new), RemovedParameterTests.swift, NameRewriteTests.swift, divergence.md P4
    - test: green — swift test, 1544 passed; IntegrationTests 3 passed
    - commit: bed1d78
    - review: findings — Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift:1167 (x2), Tests/FoundationModelsKanbanTests/GraphQL/RemovedParameterTests.swift:102, :280, :283
  timestamp: 2026-10-16T00:43:56.338499+00:00
- actor: claude-code
  id: 01m5138m885r3w41yj7xnm22wv
  text: |-
    Review findings (2026-10-15 19:35) done. Notes:
    - Findings 1-2: NameRewrite.swift. The new private `Token.significant(stepping:)` takes a key path (`\.next` or `\.prev`) and skips comment tokens. `nextSignificant` and `previousSignificant` are now one-line calls to it. No other comment-skip loop is in the file.
    - Finding 3: `RemovedVariableCase` has the new fields `resultKey` and `warning`. The six `due` cases use the new constructor `dueVariableCase(document:variables:rewrittenText:)`. The new case `query ($p: Int) { board { tasks(page: $p) { totalCount } } }` gives the text `query  { board { tasks { totalCount } } }`, the result `board`, and the `page` warning. I used `board { tasks }` and not the root `tasks`, because the root move adds a generated alias to the text, and the argument site is the same. The case passed on the first run: the argument site already used the shared `visitNamedValue`, so this case locks behavior that was there. It does not show a bug.
    - Findings 4-5: new helpers `expectResult(at:in:)` and `expectRemovedWarning(_:in:)`, and the constant `dueWarning`. `removedVariableValueGivesWarning` calls both helpers. `expectFailure` calls `expectRemovedWarning(dueWarning, in:)`. The execute test now checks `data[resultKey]` and not the `addTask` title, so that one test body works for the `page` case too.
    - Choice for `removedVariableKeyGivesWarning`: I did not change it. Reason: `git show HEAD~1:Tests/FoundationModelsKanbanTests/GraphQL/RemovedParameterTests.swift` shows this test before bed1d78, so it existed before this task. The review skill has a written rule that drops findings that ask to refactor tests that already existed, and finding 4 also says "Do not edit the pre-existing test". For the same reason I did not change `removedParameterGivesWarning` or the `cases` list. Finding 4 asks to report that work as a separate task: ^68a8kbd.
  timestamp: 2026-10-16T00:54:47.304975+00:00
- actor: claude-code
  id: 01m5138pa2vfb4rvh3v0rfrcff
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift, Tests/FoundationModelsKanbanTests/GraphQL/RemovedParameterTests.swift. 5 of 5 review findings checked. `swift test --filter "RemovedParameterTests|NameRewriteTests"`: 45 tests in 2 suites passed (the variable-value test has 7 cases). `swift test`: 1544 tests in 122 suites passed, 0 failed. The only warning was the allowed SwiftPM "missing creator" warning. No time-limit failures. New task ^68a8kbd for the older tests.
    - next: /review
  timestamp: 2026-10-16T00:54:49.410018+00:00
- actor: claude-code
  id: 01m513dvwa995gxgvm4j74nv15
  text: |-
    ### test — green
    - evidence: swift build — Build complete, only the allowed SwiftPM "missing creator" warning. swift test — 1544 tests in 122 suites passed, exit code 0, 0 failed, 0 skipped, no other warnings. One full run. No fix was needed.
    - next: review
  timestamp: 2026-10-16T00:57:38.954143+00:00
- actor: claude-code
  id: 01m513ehxfqr3z55mdkhdafw44
  text: |-
    ### commit — changed
    - evidence: iteration 2 review fixes committed locally (not pushed). Files: NameRewrite.swift, RemovedParameterTests.swift, and the .kanban/tasks files for ^164tehz and ^68a8kbd. The sha is in the git log, subject: fix(rewrite): address review findings for unread variable removal (^164tehz).
    - next: review
  timestamp: 2026-10-16T00:58:01.519877+00:00
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

## Review Findings (2026-10-15 19:35)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `divergence.md` — no validator matches this file

- [x] `Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift:1167` `duplication/duplication` — The new `previousSignificant` property repeats the logic of `nextSignificant` with only the direction changed. Both skip comment tokens in a loop. A fix to one, such as a change to how comments are skipped, must be made to both. Extract one private helper on `Token` that takes the direction, for example a key path to `next` or `prev`, or a step closure, and that skips comments. Let `nextSignificant` and `previousSignificant` both call it. Keep the two accessors as one-line calls to the helper.
- [x] `Sources/FoundationModelsKanban/GraphQL/NameRewrite.swift:1167` `reuse/reuse` — The new `previousSignificant` property copies the body of the existing `nextSignificant` property, changing only the direction (`prev` for `next`, `prev` for `next`). Two near-identical loops that skip comment tokens now have to be maintained together, and a fix to one will be missed in the other. Generalize the existing property into one helper that takes the direction, for example a private func `significant(stepping:)` that takes a key path or closure to the neighbour token (`\.next` or `\.prev`). Then define `nextSignificant` and `previousSignificant` as one-line calls to it.
- [x] `Tests/FoundationModelsKanbanTests/GraphQL/RemovedParameterTests.swift:102` `completeness/invariant-propagation` — The new variable-value cases only use a removed input field (`due` in `AddTaskInput`). The same removal treatment also runs for a removed field argument (NameRewrite.swift:641 calls visitNamedValues, which calls visitNamedValue at line 683). No case proves that a variable read in a removed field argument drops its definition when no other read exists. Add one case to `variableCases` where the removed parameter is a field argument with a variable value, for example `query ($p: Int) { tasks(page: $p) { ... } }`, with the expected rewritten text. This locks the argument site as well as the input-field site.
- [x] `Tests/FoundationModelsKanbanTests/GraphQL/RemovedParameterTests.swift:280` `duplication/duplication` — The new test `removedVariableValueGivesWarning` repeats four statements verbatim from the existing test `removedVariableKeyGivesWarning`: the `added` lookup, the `added["title"]` check, the `warnings` lookup, and the `due` warning check. When the warning text or the response shape changes, both copies must change in step. Move the shared assertions into one helper, for example `expectAddedWithDueWarning(in response: String)`, and call it from the changed test. The existing `expectFailure` helper at line 309 already groups the same warning checks, so use it as the pattern. Do not edit the pre-existing test at line 258 in this change. Report folding that test into `variableCases` as a separate task.
- [x] `Tests/FoundationModelsKanbanTests/GraphQL/RemovedParameterTests.swift:283` `reuse/reuse` — The new test re-inlines the warning assertion that already exists in the file. The same check, that the single `due` warning message equals `"`due`" + Self.noDateText`, is written out again here instead of using a shared helper. Each copy must now be kept in step with the others. Move the `due` warning check into a small helper, for example `expectDueWarning(in response: String)`, and call it from `removedVariableKeyGivesWarning`, `removedVariableValueGivesWarning`, and `expectFailure`. This is a test-only near-match, so the fix is optional, but it is the same shape as the existing helper.