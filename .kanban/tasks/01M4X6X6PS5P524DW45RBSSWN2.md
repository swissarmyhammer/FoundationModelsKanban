---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4x7hhg5vax5t3n37erhnpgj
  text: |-
    Research done.
    - The response JSON is made in `API.respond` / `API.subscribe` (S/GraphQL/Schema.swift) through the private `RewriteResponse`. It already writes `extensions.rewrites` only when not empty. The warnings go into the same `extensions` object.
    - `KanbanTool.call` returns the JSON of `KanbanGraph.execute` as it is. Thus the warnings in the response also reach the tool result.
    - `CommitSession.run` (S/Tool/Commit.swift) can run the call closure more than one time (retry after a changed log, or a load of a related board). Thus the collector must be new for each run, not for each `execute`, or a retry repeats the warnings. `KanbanGraph.runCall` makes a new `KanbanContext` for each run, so the collector lives in `KanbanContext`.
    - Both `PublicSchema` and `PatchSchema` use `KanbanContext`.
    - The name rewrite runs inside `API.respond`, after the context exists, so the rewrite can add to the same collector of the context.
    - No production code gives a warning yet (Q7, P1-P4 are later tasks). The tests add a test field to the public schema through a test seam, to make a warning end to end.
  timestamp: 2026-10-14T12:52:35.973376+00:00
- actor: claude-code
  id: 01m4x8m2v392q9javqc3esd34w
  text: |-
    Implementation landed (TDD: 5 of the 7 new tests failed first for the missing `extensions`; the 2 guard tests for "no key" passed before and after).
    - New S/GraphQL/ResponseWarnings.swift: `ResponseWarning { message, code? }` and the actor `ResponseWarnings` with `add(_:code:)` and `take()`. An actor, not a Mutex, because the swift concurrency rule asks for an actor for new shared mutable state.
    - `KanbanContext.warnings`: a new collector for each context. `KanbanGraph.runCall` makes a new context for each run of `CommitSession.run`, so a retried run does not repeat warnings, and two calls never share a list.
    - `API.respond` takes the list and `RewriteResponse` writes `extensions.warnings` only when the list is not empty, beside `extensions.rewrites`. The `extension API` now has `where ContextType == KanbanContext` (both schemas use it).
    - Test seam: `SchemaExtension` (a `@Sendable` builder step), `PublicSchema(extendedWith:)` with `PublicSchema.noExtension`, and `KanbanGraph.init(..., extendingSchemaWith:)`. The tests add a `warn(message:)` query field. Package.swift: the test target now links Graphiti.
    - plan.md §4.4: the warnings bullet (divergence §14 says to change §4.4).
    Notes for the next tasks:
    - Name rewrite (P4): it runs inside `API.respond`, after the context exists. Give `context.warnings` to the rewrite, or carry the rewrite warnings in `RewrittenDocument` and add them to `context.warnings` before the run.
    - Related board load (Q7): the load runs in the `readingRelatedBoardsWith` closure of `KanbanGraph.runCall`, outside the context of a run. That task must route the warning into the collector of the run (for example, make the collector in `runCall` and give it to `KanbanContext`).
    - A subscription response has no `extensions.warnings` (documented in `API.subscribe`). The response of a call whose commit fails (`BOARD_BUSY`) is the error JSON only, with no warnings.
  timestamp: 2026-10-14T13:11:27.843274+00:00
- actor: claude-code
  id: 01m4x8m96092gwzpyqv2jfsx7g
  text: |-
    ### implement — changed
    - evidence: 9 files — Sources/FoundationModelsKanban/GraphQL/ResponseWarnings.swift (new), Sources/FoundationModelsKanban/GraphQL/Schema.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Sources/FoundationModelsKanban/Tool/KanbanTool.swift, Tests/FoundationModelsKanbanTests/GraphQL/ResponseWarningsTests.swift (new), Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanToolTests.swift, Package.swift, plan.md. `swift test`: 1136 tests in 82 suites passed, 0 compiler warnings outside the accepted mlx ones.
    - next: /review
  timestamp: 2026-10-14T13:11:34.336954+00:00
- actor: claude-code
  id: 01m4x916a5ftrtdn64y5ktdkc7
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (7769edb); 2 findings, 2 confirmed, 0 refuted — Sources/FoundationModelsKanban/GraphQL/Schema.swift:1155, Tests/FoundationModelsKanbanTests/GraphQL/ResponseWarningsTests.swift:92
    - next: implement the 2 open items in "Review Findings (2026-10-14 08:13)", then review again.
  timestamp: 2026-10-14T13:18:37.381820+00:00
- actor: claude-code
  id: 01m4x91kyvdgq6695n7haq69n3
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 9 files (plan.md edit reverted by the orchestrator: plan.md is frozen)
    - test: green — swift test, 1136 passed, 0 failed, 0 skipped
    - commit: 7769edb
    - review: findings — Sources/FoundationModelsKanban/GraphQL/Schema.swift:1155, Tests/FoundationModelsKanbanTests/GraphQL/ResponseWarningsTests.swift:92
  timestamp: 2026-10-14T13:18:51.355214+00:00
- actor: claude-code
  id: 01m4x99hg21trbz2htzszd0ngh
  text: |-
    Review findings fixed.
    - Schema.swift duplication: the one step that makes and encodes a response is now `RewriteResponse.encoded(result:rewrites:warnings:formattedWith:)` (a static of the private type). It replaces the instance `encoded(formattedWith:)`. `respond`, the `subscribe` encode closure, and `errorResponse` call it. The subscribe site keeps the `codedCallerResult` map.
    - What did not work: a `private static func encodedResponse` in the `extension API where ContextType == KanbanContext`. The `@Sendable` encode closure of `subscribe` then captures `Self.Type` of the generic protocol, and the compiler gives the warning "capture of non-Sendable type 'Self.Type' in an isolated closure". A static on the concrete `RewriteResponse` has no such capture.
    - ResponseWarningsTests reuse: `QueryFixture.respond` now has `extendedWith extend: SchemaExtension = PublicSchema.noExtension`. `respondWithoutGate` is removed; the warnings tests call `QueryFixture().respond(to:extendedWith:)`.
  timestamp: 2026-10-14T13:23:10.978137+00:00
- actor: claude-code
  id: 01m4x99kg8s32qtfnzw9q1yg08
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/GraphQL/Schema.swift, Tests/FoundationModelsKanbanTests/GraphQL/QueryFixture.swift, Tests/FoundationModelsKanbanTests/GraphQL/ResponseWarningsTests.swift. `swift test`: 1136 tests in 82 suites passed; only the accepted SwiftPM "missing creator" warning. 2/2 findings checked.
    - next: /review
  timestamp: 2026-10-14T13:23:13.032604+00:00
position_column: doing
position_ordinal: '80'
title: Add one warnings list to each GraphQL response
---
## What
divergence.md §14 "Warnings" (DECIDED with P1–P4): use one list for all warnings in the response, at `extensions.warnings`. This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

- Add one warnings collector for each call of `KanbanGraph.execute`. Resolvers, the name rewrite, and the load of related boards append to it.
- Put the list in the response as `extensions.warnings` (an array of strings, or of objects with `message` and an optional `code`). When the list is empty, do not add the key.
- These later tasks write to this list: Q7 (a related board that cannot be read), P1 (an unknown `before`/`after` ref), P2 (`priority`), P3 (a `dependsOn` URI to a missing task), and P4 (a removed Rust parameter). Make the API easy to call from a resolver and from the name rewrite (which runs before the engine).
- The tool output (`KanbanTool`) must show the warnings to the agent.
- Warnings of one call must not leak into a different call (calls can run at the same time).

## Acceptance Criteria
- [ ] A call that adds a warning returns it in `extensions.warnings`.
- [ ] A call with no warning has no `extensions.warnings` key.
- [ ] Two calls at the same time each get only their own warnings.
- [ ] The `KanbanTool` result shows the warnings.

## Tests
- [ ] A test resolver (or the name rewrite) that adds a warning, and a check that the response has it.
- [ ] A test that two calls at the same time do not share warnings.
- [ ] A `KanbanTool` test that the warning text is in the tool result.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-14 08:13)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 8 file(s) reviewed, 2 not reviewed.

> 2 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 2 file(s)

- [x] `Sources/FoundationModelsKanban/GraphQL/Schema.swift:1155` `duplication/duplication` — The subscribe encode closure repeats the wrap step that respond and errorResponse also use: build RewriteResponse, then call encoded(formattedWith:). A fix to this step must be made at each copy, and the copies can drift apart. Add one private helper, for example encodedResponse(result:rewrites:warnings:formattedWith:), that builds RewriteResponse and encodes it. Call it from the three sites. Keep the codedCallerResult mapping at the subscribe site, so the helper takes an already mapped GraphQLResult.
- [x] `Tests/FoundationModelsKanbanTests/GraphQL/ResponseWarningsTests.swift:92` `reuse/reuse` — `respondWithoutGate` is a near-match of the existing `QueryFixture.respond`, which already runs a document through `PublicSchema()` with a fixture context. The new helper copies that call and differs only in the schema it builds. The existing helper should take the schema extension as a parameter, so the test calls one helper, not a parallel copy. Add an `extendedWith` parameter with the default `PublicSchema.noExtension` to `QueryFixture.respond` (for example `respond(to:searchingWith:extendedWith:)`), and call it from the warnings tests. If the context shape differs too much for that, keep `respondWithoutGate` and note in its doc comment why the existing fixture does not fit.
