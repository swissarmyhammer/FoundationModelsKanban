---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5f4n68p69q7mbcdz05g2qyx
  text: 'Research (implement): Extras pinned at 11ffe56. Kanban copies vs toolkit: VariableReads/JSONListText identical apart from access level. ResponseWarnings identical, except kanban-only `BoardWarning` protocol (must move to a kanban file). NameMatcher differs only by the kanban verb tables (archive/done/finish/close/label/unlabel/restore/unarchive/recover synonyms, board create/new -> init, query verbs search/next) -> GraphQLNameRules. NameRewrite differs only by rules plumbing (board root container `_kanbanRoot` prefix, RemovedParameter enum -> GraphQLRemovedParameter list, GraphQLFieldAliases -> GraphQLAliasTable). Run/response code lives in GraphQL/Schema.swift (`API.respond/subscribe`, `RewriteResponse`, `.single/.encoding`), not in KanbanGraph; semantics match `GraphQLRunContext` respond/subscribe. Kanban has no `extensions.txn` key today. KanbanError cases invalidVariables/subscriptionNotInTool/graphQLParseFailed/graphQLValidationFailed/ambiguousName/internalFailure duplicate GraphQLToolkitError; their messages are identical, and the kanban subscription message equals toolkit message + hint "Use board { history(since: <txn>) } to get the changes after a known transaction." Toolkit scalars add SDL descriptions to DateTime and JSON (an intended SDL change). KanbanArguments duplicates GraphQLArguments decode.'
  timestamp: 2026-10-21T11:48:29.590871+00:00
- actor: claude-code
  id: 01m5f5a7m5z9yv5h8ay4h8hp9p
  text: 'Progress: deleted GraphQL/CodedError, ResponseWarnings, NameRewrite, NameMatcher, VariableReads, JSONListText and the DateTime/JSON scalars plus the run/response code of Schema.swift (API.respond/subscribe, RewriteResponse, stream helpers). Kanban-only parts now plug into toolkit extension points: GraphQLNameRules.kanban (new GraphQL/KanbanNameRules.swift: Rust verb synonyms, board create/new->init, search/next query verbs, `board` root container with `_kanbanRoot` prefix, RemovedParameter cases as GraphQLRemovedParameter), KanbanFieldAliases.table (GraphQLAliasTable), BoardWarning moved to CrossRepo/BoardWarning.swift, KanbanContext: GraphQLRunContext, KanbanError: CodedError (toolkit-duplicate cases removed). KanbanTool answers via GraphQLTool.answer with KanbanTool.subscriptionHint (same message text as before). KanbanArguments wraps GraphQLArguments (decode and schema from the toolkit). Package.swift GraphQL/Graphiti use named Extras floors with comments saying they follow Extras. Library target builds with no warnings. Note: no toolkit `.single` is public, so KanbanGraph builds its one-response stream inline. Tests that call DocumentRewriter/NameMatcher/PublicSchema.respond directly now pass `rules: .kanban` in their helpers (assertions unchanged).'
  timestamp: 2026-10-21T11:59:59.109812+00:00
- actor: claude-code
  id: 01m5f5gzqv0khj5cqm45v71k0e
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` clean (no warnings from package code); `swift test` 1700 tests in 140 suites passed, exit 0. 71 files changed (276+/3219-). Deleted Sources/FoundationModelsKanban/GraphQL/{CodedError,ResponseWarnings,NameRewrite,NameMatcher,VariableReads,JSONListText}.swift; added GraphQL/KanbanNameRules.swift and CrossRepo/BoardWarning.swift; rewrote FieldAliases.swift, RemovedParameters.swift, Scalars.swift, Errors.swift, Schema.swift (run/response code removed, KanbanContext: GraphQLRunContext), KanbanGraph.swift (rules: .kanban), KanbanTool.swift (GraphQLTool.answer + subscriptionHint), KanbanArguments.swift (wraps GraphQLArguments), Package.swift, plan.md; import FoundationModelsExtras added where toolkit types are used.
    - intended changes: (1) SDL: `scalar DateTime` and `scalar JSON` now carry the toolkit descriptions; (2) the tool parameter schema is GraphQLArguments.generationSchema (root name GraphQLArguments, description "One GraphQL request."); (3) a subscription stream whose source throws a CodedError now ends with one coded `errors` response (toolkit behavior; no kanban source throws one today). No response JSON drift in the existing suite; SUBSCRIPTION_NOT_IN_TOOL and INVALID_VARIABLES messages are byte-identical.
    - test changes: helpers pass `rules: .kanban` (NameRewrite/AliasTable/VariableRewrite/NameMatcher tests, QueryFixture, TaskQueryFixture); tie assertions cast to GraphQLToolkitError; KanbanErrorTests drop the six toolkit-owned cases and use CodedErrorJSON; KanbanToolTests check the rule-10 hint names `board { history(since: <txn>) }`.
    - next: /review
  timestamp: 2026-10-21T12:03:40.411766+00:00
- actor: claude-code
  id: 01m5f5mjgbjrbsv0etshdhnyhn
  text: |-
    ### test — green
    - evidence: `swift test` — 1700 tests in 140 suites passed, 0 failed, 0 skipped; `swift build --build-tests` in IntegrationTests/ — Build complete. No compiler warnings in package code. The only build warning is the third-party "missing creator for mutated node" (mlx-swift_Cmlx.bundle), out of scope. The runtime "warning FoundationModelsKanban: error=malformed" lines are expected log output of the tests that feed Replay malformed log lines.
    - next: review
  timestamp: 2026-10-21T12:05:37.931580+00:00
- actor: claude-code
  id: 01m5f64nf32bjxdp43nxr0gc91
  text: |-
    ### review — findings
    - evidence: `review sha HEAD~1..HEAD` (commit 9523924): engine counts findings 0, confirmed 0, refuted 0 (66 files reviewed; .kanban/ ignored; plan.md has no validator). Acceptance-criteria check: 1 finding at commit 9523924 (acceptance-criteria/tests). The commit message does not list the intended output changes: the toolkit DateTime/JSON scalar descriptions in introspection, the parameter schema root name and description (KanbanArguments → GraphQLArguments, "One GraphQL request to the kanban task graph." → "One GraphQL request."), and the coded-error end of a subscription stream. The other criteria are met. The parameter-schema description change loses no model-facing guidance: the property descriptions are the same, and KanbanTool.description starts with "Reads and changes the kanban task graph of this repo with GraphQL."
    - next: list the three intended changes in the commit message (amend the unpushed 9523924, or put them in a follow-up ^jk3fc4g commit), then /review ^jk3fc4g
  timestamp: 2026-10-21T12:14:25.251503+00:00
- actor: claude-code
  id: 01m5f6584sef8m9wxqmgbbrcqk
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 71 files, 6 GraphQL copies deleted, KanbanNameRules + BoardWarning added
    - test: green — swift test 1700 / 140 suites; IntegrationTests build ok
    - commit: 9523924
    - review: findings — commit 9523924 message does not list the intended response/output changes (Tests acceptance criterion)
  timestamp: 2026-10-21T12:14:44.377540+00:00
- actor: claude-code
  id: 01m5f66wk77dw1zhdn175c6st4
  text: |-
    ### implement — changed
    - evidence: amended the unpushed HEAD 9523924 with a new message only (`git commit --amend --only`, nothing staged). New HEAD is 2fb3fe16825d227f9761e51750c2bb38ce6f7ebd, and `git diff 9523924 HEAD` is empty, so the tree did not change. `git status -sb` shows main ahead of origin/main by 2. The commit body now has the section "Intentional output changes": (1) introspection of `scalar DateTime`/`scalar JSON` returns the toolkit descriptions; (2) the KanbanTool parameter schema root is `GraphQLArguments` with the description "One GraphQL request." (before: `KanbanArguments`, "One GraphQL request to the kanban task graph."), and KanbanTool.description still gives the kanban context; (3) a subscription whose source stream throws a CodedError ends with one final coded `{"errors":[...]}` response and then ends normally. The finding `commit 9523924` `acceptance-criteria/tests` is checked [x].
    - next: /review ^jk3fc4g (review sha HEAD~1..HEAD at 2fb3fe1)
  timestamp: 2026-10-21T12:15:38.087178+00:00
- actor: claude-code
  id: 01m5f6nghtgc53qy94rp27m463
  text: |-
    ### review — clean
    - evidence: `review sha HEAD~1..HEAD` at 56646c4: engine counts findings 0, confirmed 0, refuted 0 (66 files reviewed; 6 .kanban/ files ignored by .reviewignore; plan.md has no validator; the code-hygiene Swift tool rules declined only the six deleted GraphQL files). `git diff 9523924 HEAD` touches only .kanban/tasks/01M5F234JM2BZEQ1TDMJK3FC4G.{md,jsonl}, so the code tree is the same as 9523924. The HEAD commit body has the section "Intentional output changes" with all three changes: (1) toolkit descriptions for `scalar DateTime`/`scalar JSON` in introspection; (2) parameter schema root `GraphQLArguments`, "One GraphQL request." (before: `KanbanArguments`, "One GraphQL request to the kanban task graph."); (3) a subscription whose source throws a CodedError ends with one final coded `{"errors":[...]}` response. The prior finding `commit 9523924` `acceptance-criteria/tests` is checked. All 5 acceptance criteria and both Tests items are now ticked, per the 07:06 acceptance check and the green test record (1700 tests in 140 suites, 0 failed).
    - next: none. The task is in done. Commits are not pushed yet (main is 2 ahead of origin/main). ^d7sgpaz (KANBAN-5) is unblocked.
  timestamp: 2026-10-21T12:23:37.274472+00:00
- actor: claude-code
  id: 01m5f6p8qtyvrszdfjdkmhdfpw
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — amended commit message to list intended output changes; finding checked
    - test: green — code tree identical to 9523924 (1700 / 140 green); not re-run
    - commit: 56646c4 (amend, folded .kanban state)
    - review: clean — 0 findings
  timestamp: 2026-10-21T12:24:02.042153+00:00
position_column: done
position_ordinal: ffa980
title: Move the GraphQL layer to the Extras toolkit and align the GraphQL/Graphiti declarations with Extras
---
## What
Replace the kanban copies of toolkit parts with the FoundationModelsExtras GraphQL toolkit (main 6670bc0 or later), per EXTRAS-9 rev 2 rule 2 and D74/D86. Spec: TestudoApp/features/packages/foundationmodels-kanban.md KANBAN-5, foundationmodels-extras.md EXTRAS-6/EXTRAS-9.

Delete these copies and use the Extras versions:
- `Sources/FoundationModelsKanban/GraphQL/CodedError.swift`: use the Extras `CodedError` protocol. Kanban has codes of its own, so the kanban error enum stays and conforms to it.
- `ResponseWarnings.swift`, `NameRewrite.swift` (NameRewrite/DocumentRewriter), `NameMatcher.swift`, `VariableReads.swift`, `JSONListText.swift`
- the DateTime/JSON scalars in `Scalars.swift`: use `addToolkitScalars()`
- the kanban subscription refusal in `KanbanTool`: use `GraphQLToolkitError.subscriptionNotInTool` through `GraphQLTool.answer`
- the run/response code in `Tool/KanbanGraph.swift` (`execute`, `subscribe`, the response type near line 1442): use `GraphQLRunContext`, `respond` and `subscribe`
- the alias tables in `FieldAliases.swift` go to `GraphQLNameRules`, so rewrites still show in `extensions.rewrites`

Kanban-only parts stay: `RemovedParameters.swift` (old Rust parameter compat), the board schema and resolvers, the alias tables, the `board { … }` root container, `extensions.txn`, and the content of `extensions.warnings`.

Package.swift (EXTRAS-9 rev 2 rule 2, the same as ACPAgent): keep declaring GraphQL and Graphiti, but only with the Extras URLs and Extras version floors (today `https://github.com/GraphQLSwift/GraphQL.git` from 4.3.0 and `https://github.com/GraphQLSwift/Graphiti.git` from 3.1.0, which kanban already has). Rewrite the manifest comments to say that the pins follow Extras and are not their own choice. The 57 `import GraphQL`/`import Graphiti` lines stay.

## Acceptance Criteria
- [x] No file under Sources/FoundationModelsKanban/GraphQL duplicates a toolkit part (CodedError protocol, ResponseWarnings, NameRewrite, DocumentRewriter, NameMatcher, VariableReads, JSONListText, DateTime/JSON scalars)
- [x] The GraphQL and Graphiti declarations in Package.swift use the same URLs and floors as FoundationModelsExtras/Package.swift
- [x] Alias names still rewrite and show in `extensions.rewrites`; old Rust parameter names still work
- [x] `extensions.txn` and `extensions.warnings` are unchanged for existing calls
- [x] A subscription through KanbanTool gives `SUBSCRIPTION_NOT_IN_TOOL`, with a hint that names the query to read again (rule 10)

## Tests
- [x] The full existing suite is green (`swift test`), with no response JSON drift except intentional changes listed in the commit
- [x] The existing alias/rewrite, warnings and Rust-compat tests pass unchanged

## Review Findings (2026-10-21 07:06)

> Scope: `review sha HEAD~1..HEAD` (commit 9523924). The engine reviewed only the diffs: the lines this change added or modified. It reviewed 66 files and did not review 7. Engine counts: findings 0, confirmed 0, refuted 0.

> 6 files not reviewed. An ignore rule excludes them:
> - `.kanban/ (from .reviewignore)` (6 files)

> 1 file not reviewed. No validator matched it:
> - `plan.md`. No validator matches this file.

> The code-hygiene Swift tool rules (disallowed-constructs-swift, function-length-swift, idioms-swift, magic-numbers-swift, missing-docs-swift) declined the six files that this commit deletes: CodedError, JSONListText, NameMatcher, NameRewrite, ResponseWarnings and VariableReads under Sources/FoundationModelsKanban/GraphQL. Each rule found no file at that path, so it could not read the constructs, bodies, declarations or literals there.

### Acceptance criteria check

- [x] `commit 9523924` `acceptance-criteria/tests` — The Tests criterion permits "no response JSON drift except intentional changes listed in the commit". The commit message lists no intentional change. The implement record names three: (1) introspection of `scalar DateTime` and `scalar JSON` now returns the toolkit descriptions ("A point in time: RFC 3339 text in UTC with milliseconds, …" and "Any JSON value. The keys of each object are in sorted order."), which is response JSON drift for `__type`/`__schema` queries; (2) the KanbanTool parameter schema is now `GraphQLArguments.generationSchema`, so the root name changes from `KanbanArguments` to `GraphQLArguments` and the root description changes from "One GraphQL request to the kanban task graph." to "One GraphQL request."; (3) a subscription stream whose source throws a CodedError now ends with one coded `errors` response. List all three as intentional changes in the commit message. The commit is not pushed (origin/main..HEAD holds it), so amend 9523924 or put the list in the next commit for ^jk3fc4g.

Other criteria checked, all met: no toolkit duplicate is left under Sources/FoundationModelsKanban/GraphQL (Scalars.swift calls `addToolkitScalars()`); the Package.swift GraphQL and Graphiti URLs and floors (4.3.0, 3.1.0) are the same as in FoundationModelsExtras/Package.swift; the alias, rewrite, warnings and Rust-compat test assertions keep their expected values (only `rules: .kanban` plumbing and the `GraphQLToolkitError` tie type changed, which the deletion of the duplicate requires); SUBSCRIPTION_NOT_IN_TOOL names `board { history(since: <txn>) }` and KanbanToolTests checks it; the test record is green (1700 tests, 0 failed).

Parameter-schema description: no model-facing guidance is lost. The `query`, `variables` and `operationName` property descriptions are the same text as before. The kanban scope that the old root description gave ("the kanban task graph") is also the first sentence of `KanbanTool.description`, "Reads and changes the kanban task graph of this repo with GraphQL.", and the model sees that sentence with the parameters. The change is intended, but the commit message must still list it (finding above).