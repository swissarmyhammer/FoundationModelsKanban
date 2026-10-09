---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gj2k7296a9qtqa45azbrd0
  text: |-
    Research:
    - `PublicSchema.respond` (GraphQL/Schema.swift) has three error paths with no code: (1) `errorResponse` for a parse error (the rewriter parse in `rewriting`, and the engine parse in `result(of:)`); (2) the validation errors that `graphql()` returns in `GraphQLResult.errors` (no path, no original error); (3) the ties of `RewriteWalk.canonicalName` (NameRewrite.swift), which `result(of:)` returns as they are. `codedError` only codes a `KanbanError`.
    - The engine (`locatedError`) wraps a resolver error that is not a GraphQLError with the path and `originalError`. So an `EventError` has a path and a non-Kanban original error.
    - Errors with no path and no original error come from the request phase: validation, variable coercion, operation choice. These get `GRAPHQL_VALIDATION_FAILED`.
    - The subscription path codes its errors through `codedCallerResult`, so the same rule covers it.
    - `KanbanError.code` is a computed property over the cases. The new codes become new cases: `graphQLParseFailed(detail:)`, `graphQLValidationFailed(detail:)`, `ambiguousName(name:matches:)`, `internalFailure(detail:)`. The message of the parse, validation and internal cases is the engine text as it is, so the "did you mean" text does not change.
  timestamp: 2026-10-09T14:46:32.930114+00:00
- actor: claude-code
  id: 01m4gjf5zr2yhk56rc8cnkv4yq
  text: |-
    Implementation landed (TDD: RED seen for the 3 execute tests and the INTERNAL unit test, then GREEN).
    - New file `GraphQL/CodedError.swift`: `GraphQLError.coded(as:)`, `codedAsParseFailure()`, `codedAsResultError()`. It replaces the private `codedError` in Schema.swift.
    - Rule chosen (closest to plan.md §4.4): a `KanbanError` keeps its code; an error with no path and no original error is a request error (validation, variable values, operation choice) and gets `GRAPHQL_VALIDATION_FAILED`; each other error gets `INTERNAL`. The parse, validation and internal errors keep the message of the engine, so the "did you mean" text does not change.
    - `errorResponse` (the parse path) codes its error as `GRAPHQL_PARSE_FAILED`. The rewrite ties are made coded as `AMBIGUOUS_NAME` in `RewriteWalk.canonicalName`; the tie message moved into `KanbanError.ambiguousName`.
    - Discovery: `PatchSchema().respond` shares this path, so the `GraphQLEngineTests` test for a patch with a bad node ref now expects `extensions.code == "INTERNAL"`. I changed that expected JSON.
    - plan.md §4.4 lists the four new codes.
  timestamp: 2026-10-09T14:53:25.368303+00:00
- actor: claude-code
  id: 01m4gjf818qmdfhj8h7kfw7jzk
  text: |-
    ### implement — changed
    - evidence: 8 files — Sources/FoundationModelsKanban/GraphQL/CodedError.swift (new), GraphQL/Errors.swift, GraphQL/Schema.swift, GraphQL/NameRewrite.swift, plan.md, Tests/.../GraphQL/ErrorCoverageTests.swift, Tests/.../GraphQL/KanbanErrorTests.swift, Tests/.../GraphQLEngineTests.swift. `swift test`: 1064 tests in 74 suites passed, 0 failures; only the accepted SwiftPM "missing creator" warning.
    - next: /review
  timestamp: 2026-10-09T14:53:27.464398+00:00
- actor: claude-code
  id: 01m4gjq04dqk4avpg3gywmd6bz
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 8 files
    - test: green — swift test, 1064 tests in 74 suites passed
    - commit: 07921c7
    - review: findings — plan.md:332 (the commit message says "plan.md section 7"; the change is in plan.md §4.4)
  timestamp: 2026-10-09T14:57:41.517248+00:00
- actor: claude-code
  id: 01m4gjq189175a8gw030km64cr
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD — engine 0 findings (2 refuted); commit message check 1 finding — plan.md:332
    - next: correct the message of commit 07921c7, then /review
  timestamp: 2026-10-09T14:57:42.665416+00:00
- actor: claude-code
  id: 01m4gjrpsd4e4z9c9qwz2bd88v
  text: |-
    ### implement — changed
    - evidence: `git commit --amend --only` changed only the message. Commit 07921c7 is now f825827. The tree is d4cd2342 before and after the amend, and `git diff 07921c7 f825827` is empty. The new message says: "In plan.md section 4.4 (Errors), add the four new codes to the list of codes. Also add two bullets that give the meaning of the codes: one bullet for GRAPHQL_PARSE_FAILED, GRAPHQL_VALIDATION_FAILED and AMBIGUOUS_NAME, and one bullet for INTERNAL." All other lines of the message did not change. The finding `plan.md:332` is `- [x]`. No code change, no other commit.
    - next: /review
  timestamp: 2026-10-09T14:58:37.485653+00:00
- actor: claude-code
  id: 01m4gjy1c6jmhvg1yx6vhqvdm3
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD — engine 0 findings (0 confirmed, 0 refuted); 2 .kanban files excluded by .reviewignore. Commit message check: f825827 (HEAD~1) is true for its diff. 843d2a0 (HEAD) 1 finding — .kanban/tasks/01M4G9J3T6GYAK2C87GK5XF03F.md:32 (the message names an iteration 1 implement record that the diff does not add)
    - next: correct the message of commit 843d2a0, then /review
  timestamp: 2026-10-09T15:01:32.166912+00:00
- actor: claude-code
  id: 01m4gjy30287t7cmqrnv25v89z
  text: |-
    ### finish iteration 2 — findings
    - implement: changed — message of 07921c7 amended to f825827
    - test: green — swift test, 1064 tests in 74 suites passed
    - commit: 843d2a0
    - review: findings — .kanban/tasks/01M4G9J3T6GYAK2C87GK5XF03F.md:32 (the message of 843d2a0 names an iteration 1 implement record that the diff does not add)
  timestamp: 2026-10-09T15:01:33.826790+00:00
- actor: claude-code
  id: 01m4gjzx3gd8nqg4njzd4qvekp
  text: |-
    ### implement — changed
    - evidence: `git commit --amend --only` changed only the message. Commit 843d2a0 is now 86e2d18. The tree is 1a31d97b before and after the amend, and `git diff 843d2a0 86e2d18` is empty. `git show` showed that the diff changes only the two task files of ^k5xf03f. It adds three comments (`### finish iteration 1 — findings`, `### review — findings`, and the `### implement — changed` record of the message correction) and the Review Findings section with the checked finding plan.md:332. The `### implement — changed` record is not a review comment, so the body names it. New message: subject "chore(kanban): record review round 1 of ^k5xf03f", body "Add the review record, the ledger comment, the implement record of the message correction and the checked finding of ^k5xf03f." The finding `.kanban/tasks/01M4G9J3T6GYAK2C87GK5XF03F.md:32` is `- [x]`. No code change, no other commit. The commit was not pushed (no remote branch contains it).
    - next: /review
  timestamp: 2026-10-09T15:02:33.328436+00:00
- actor: claude-code
  id: 01m4gk3ym7y993zmnzd9nyzqbc
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD — engine 0 findings (0 confirmed, 0 refuted); 2 .kanban files excluded by .reviewignore. Commit message check: 86e2d18 (HEAD~1) is true for its diff (it adds the `### review — findings` record, the `### finish iteration 1 — findings` ledger comment, the `### implement — changed` record of the message correction, and the Review Findings section with the checked finding plan.md:332). 8310f1e (HEAD) is true for its diff (it changes only the two task files of ^k5xf03f and records review round 2). All prior findings are checked.
    - next: none — task moved to done
  timestamp: 2026-10-09T15:04:45.959736+00:00
- actor: claude-code
  id: 01m4gk3zmpfgzz0rjv9tsz3npt
  text: |-
    ### finish iteration 3 — clean
    - implement: changed — message of 843d2a0 amended to 86e2d18
    - test: green — swift test, 1064 tests in 74 suites passed
    - commit: 8310f1e
    - review: clean — 0 findings
  timestamp: 2026-10-09T15:04:46.998904+00:00
position_column: done
position_ordinal: ca80
title: Each GraphQL error has extensions.code
---
## What
plan.md §4.4: "Each error has `message`, `path`, and `extensions.code`." Now `Sources/FoundationModelsKanban/GraphQL/Schema.swift:1244-1247` (`codedError`) adds a code only for a `KanbanError`. These errors have no code: parse errors, validation errors, the tie errors of the name rewrite (`GraphQL/NameRewrite.swift:516`), and `EventError`.

- Add codes to the §4.4 list in plan.md and to the `KanbanError` code enum: `GRAPHQL_PARSE_FAILED` (syntax error), `GRAPHQL_VALIDATION_FAILED` (unknown field, wrong argument type, and others), `AMBIGUOUS_NAME` (rewrite tie), and `INTERNAL` (an `EventError` or other error that is not a `KanbanError`).
- Set the code in `codedError` and in the parse, validation and rewrite error paths.

## Acceptance Criteria
- [x] A document with a syntax error gives one error with `extensions.code == "GRAPHQL_PARSE_FAILED"`.
- [x] A document with an unknown field gives `GRAPHQL_VALIDATION_FAILED`.
- [x] A name that ties in the rewrite gives `AMBIGUOUS_NAME`.
- [x] No response from the tool has an error with no `extensions.code`.

## Tests
- [x] Tests in `Tests/FoundationModelsKanbanTests/GraphQL/` (the error coverage tests) for each case.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-09 09:55)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 5 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

> 1 file(s) not reviewed — no validator matched:
> - `plan.md` — no validator matches this file

- [x] `plan.md:332` `commit/message-accuracy` — The message of commit 07921c7 says "Add the four new codes to the list of codes in plan.md section 7". The change is in plan.md §4.4 Errors, not in section 7. The change also adds two bullets that give the meaning of `GRAPHQL_PARSE_FAILED`, `GRAPHQL_VALIDATION_FAILED`, `AMBIGUOUS_NAME` and `INTERNAL`, and the message does not tell about them. Correct the message so that it names §4.4 and tells about the two new bullets.

## Review Findings (2026-10-09 10:00)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 0 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

> Every file in scope was excluded — 2 of 2 file(s) — so nothing was left to review. The exclusions above are deliberate: this is a clean review, not an empty scope, a failed run, or a size-cap skip.

> Commit message check: each statement in the message of f825827 (HEAD~1) is true for its diff. The message of 843d2a0 (HEAD) has one statement that is not true.

- [x] `.kanban/tasks/01M4G9J3T6GYAK2C87GK5XF03F.md:32` `commit/message-accuracy` — The message of commit 843d2a0 says "Add the comments for iteration 1: the implement, finish and review records, and the implement record of the commit message correction." The diff adds only three comments: `### finish iteration 1 — findings`, `### review — findings`, and the `### implement — changed` record of the message correction. The `### implement — changed` record of iteration 1 (timestamp 2026-10-09T14:53:27) is already in f825827 (HEAD~1), and 843d2a0 does not add it. Correct the message so that it names only the three comments that the diff adds.