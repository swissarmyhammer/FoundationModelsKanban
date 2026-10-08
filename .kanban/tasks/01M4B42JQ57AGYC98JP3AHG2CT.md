---
comments:
- actor: wballard
  id: 01m4d21w51d7m00xvn7jwet44k
  text: |-
    Research done.
    - Graphiti 3.1.0: `SubscriptionField(name, as: FieldType, atSub:)` and `Subscription { }` with `SchemaBuilder.addSubscription`. `API.subscribe(request:context:variables:operationName:)` returns `Result<AsyncThrowingStream<GraphQLResult, Error>, GraphQLErrors>`.
    - GraphQLSwift 4.3.0 `subscribe` runs each source event with `execute(..., rootValue: event, context: <the context of the subscribe call>)` in its own Task. The context is fixed for the life of the stream. `createSourceEventStream` is internal.
    - Thus the per-event state of the context must be refreshed through the serial gate before each event executes.
    - `History.swift` has a private `ChangeFilter` (type, node, actor, filter, derived). The feed can share it.
    - `LiveGraph.apply(changedPaths:)` already returns the new event ids (a union merge gives only the new ids). The callers drop them now (`_ =`). The commit check (`BoardWrite.applyChangedFiles`) also applies changes of other processes; the watcher then sees equal signatures. So the feed must take changes from each change of a live graph, not only from the watcher.
    - Cross-board readiness needs a `RelatedBoards` value with a resolution for each dependency key; `relatedBoards(updating:toAnswer:currentKey:)` of the engine makes it and loads the boards that the dependencies reach.
  timestamp: 2026-10-08T06:08:48.801077+00:00
- actor: wballard
  id: 01m4d2jww035rbhczydmcacdt0
  text: 'RED: `Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift` has 7 tests. With a stub `subscribe` that gives an open stream with no event, all 7 fail on an expectation (no event, or no end). The time-limited race of `BoardWatcherTests.hasBatch` moved to the shared helper `Tests/FoundationModelsKanbanTests/Observe/StreamWait.swift`; the BoardWatcher suite still passes.'
  timestamp: 2026-10-08T06:18:06.592673+00:00
- actor: wballard
  id: 01m4d37dqbvxz3ma5kdwn33g8t
  text: |-
    Design choices that plan.md §6.7 does not state (recorded for review):
    1. Serial gate: GraphQLSwift runs each event of a subscription with the context of the `subscribe` call, in its own task. Thus the engine reads the board of each event through the serial gate when it sends the event (`EventBoard`), and before the event runs, the store of the subscription context gets that board (`BoardStore.replace(with:)`). The events run one at a time, outside the gate, on a value that the gate made. `NodeUpdate.node` shows the node as it was just after the operation of the event.
    2. Change source: each change of a live graph that adds events records a `LiveGraphChange` (a commit `adopt`, a watcher batch `apply`, and also the commit check that applies the files of a different process). After each operation of the gate (a call, a subscribe, a watcher batch), the engine takes them and sends them (`ChangeRound`). Without a subscriber they are only dropped.
    3. A subscription that cannot start (a parse, validation, or argument error, for example `INVALID_FILTER`) gives a stream with one error response, and the stream then ends. `subscribe` throws only for an I/O fault, the same as `execute`.
    4. Filters: `node` and `actor` resolve one time, at the start. `filter` tests the tasks of the board just after the change. `ChangeFilter` moved from `Undo/History.swift` to `Observe/ChangeFilter.swift`, and `history` and `changes` share it.
    5. A subscribed board that did not change, while a board that it depends on changed, gets one `DERIVED`-only change for each new transaction of that board; `boards` starts with the key of the changed board. A change with no update after the filters is not sent.
    6. Before it sends changes, the engine loads each board that a `dependsOn` edge of a loaded board reaches (`relatedBoards(updating:toAnswer:currentKey:)`), so a new cross-board edge from a different process is also watched. A load error is logged, and the changes of that operation are not sent.
    7. The subscribers of the feed are keyed by the canonical path of the repo directory of their board, not by the board key, because two copies of one repo have one key.
    8. `subscribe` after `close()` gives a stream that has ended.
  timestamp: 2026-10-08T06:29:19.211898+00:00
- actor: wballard
  id: 01m4d37qvx1hyn8zahjx2fee8s
  text: |-
    ### implement — changed
    - evidence: new `Sources/FoundationModelsKanban/Observe/ChangeFeed.swift`, `ChangeFilter.swift`, `ChangeRound.swift`, `ChangeSubscription.swift`; changed `Observe/LiveGraph.swift`, `Observe/ChangeBuilder.swift`, `Tool/KanbanGraph.swift`, `Tool/Commit.swift`, `GraphQL/Schema.swift`, `Undo/History.swift`, `CrossRepo/RelatedBoards.swift`; tests: new `Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift` (7 tests) and `Observe/StreamWait.swift` (shared wait, from `BoardWatcherTests.hasBatch`), changed `BoardWatcherTests.swift`, `Tool/CommitTests.swift`. RED: 7 of 7 failed on an expectation with a stub; GREEN: 7 of 7 pass. `swift build --build-tests`: only the accepted SwiftPM "missing creator" warning. Full `swift test --skip-build` 3 times (120 s limit): 947 tests in 64 suites passed in 8.697 s, 8.386 s, 8.941 s. Periphery: no unused code.
    - follow-up: ^0ahzwrz (Change.actor in the board of the change).
    - next: /review
  timestamp: 2026-10-08T06:29:29.597521+00:00
- actor: wballard
  id: 01m4d3mxphzsaks8xeecpntbvw
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (8a9f38f); 5 findings (5 confirmed, 10 refuted) — Sources/FoundationModelsKanban/GraphQL/Schema.swift:1167, Sources/FoundationModelsKanban/Observe/ChangeSubscription.swift:57, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:262, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:263, Tests/FoundationModelsKanbanTests/Observe/StreamWait.swift:11
    - next: correct all 5 items in "Review Findings (2026-10-08 01:32)", then do the review again.
  timestamp: 2026-10-08T06:36:41.553271+00:00
- actor: wballard
  id: 01m4d3n8myn8f2sgagk90ae8jv
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 4 new Observe sources, 7 changed sources, 4 test files (new SubscriptionTests.swift, StreamWait.swift)
    - test: green — swift test 3 runs with a 120 s limit, 947 passed each (8.6 s, 8.1 s, 8.6 s); build warnings only the 2 accepted kinds
    - commit: 8a9f38f
    - review: findings — Sources/FoundationModelsKanban/GraphQL/Schema.swift:1167, Sources/FoundationModelsKanban/Observe/ChangeSubscription.swift:57, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:262, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:263, Tests/FoundationModelsKanbanTests/Observe/StreamWait.swift:11
  timestamp: 2026-10-08T06:36:52.766181+00:00
- actor: wballard
  id: 01m4d44g901a052jkxvw6f2myd
  text: |-
    Review findings (2026-10-08 01:32) are corrected. Notes for the next agent:
    1. Schema.swift: one private helper `rewriting(_:formattedWith:answeringFailureWith:_:)` does the name rewrite and makes the parse-error response for `respond` and `subscribe`. One private static `errorResponse(_:formattedWith:)` makes the one-error response. `respond` uses it also for a GraphQLError from `result(of:...)`, as before.
    2. ChangeSubscription.swift: a board with no repo directory now throws `KanbanError.notFound(type: .board, reference: <board key>)` from `events`. The log line stays. The `assertionFailure` is removed. The subscription gives one NOT_FOUND response and ends. I used the existing NOT_FOUND code, because plan.md §4.4 fixes the code catalog. I did not make the state impossible in the types: `BoardView.source` is optional for graph rules, history replay, and test fixtures, and a test reaches this path with `GraphQLEngineTests.makeContext()`. New test: `SubscriptionTests.boardWithNoDirectoryGivesOneErrorAndEnds`. RED: the test process stopped at the `assertionFailure` (signal 5). GREEN: pass.
    3. KanbanGraph.swift: one private helper `runSchemaCall(answeringFailureWith:_:)` holds the only `catch let error as KanbanError` around `runCall`. `respond` and `startSubscription` call it.
    4. Tests: `StreamWait.timeLimitSeconds`; in SubscriptionTests `oneEvent`, `twoEvents`, `linesBeforeBranchLine`, and the file-scope `subscriptionSuiteMinutes`. A `@Suite` attribute cannot read a static member of its own type (the compiler reports "circular reference resolving attached macro 'Suite'"), so that constant is at file scope. The INVALID_FILTER test and the new test share `errorCode(of:)`.
    5. periphery with `--retain-public --skip-build --index-store-path .build/out`: Sources has no finding. It still reports 7 items in test files that this change did not touch (MergeTests.swift, ChangeBuilderTests.swift, TaskSearchTests.swift, KanbanGraphTests.swift).
  timestamp: 2026-10-08T06:45:12.096692+00:00
- actor: wballard
  id: 01m4d44jym1x4tmrm92f6jxbda
  text: |-
    ### implement — changed
    - evidence: Sources/FoundationModelsKanban/GraphQL/Schema.swift, Sources/FoundationModelsKanban/Observe/ChangeSubscription.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Tests/FoundationModelsKanbanTests/Observe/StreamWait.swift, Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift. `swift build --build-tests`: only the accepted SwiftPM "missing creator" warning. Full `swift test --skip-build` 3 times (120 s limit): 948 tests in 64 suites passed in 8.663 s, 8.445 s, 7.915 s. swiftlint no_magic_numbers (allowed 0, 1, -1, 100) on the 5 changed files: 0 violations. periphery --retain-public: Sources clean. No line is longer than 120 characters.
    - next: /review
  timestamp: 2026-10-08T06:45:14.836631+00:00
depends_on:
- 01M4B41VDXZ3NKEG4554PVXWQN
- 01M4B412DB2BSB0FAQEA72WN8T
- 01M4B3Z67TC96REJGDHD2DFH0R
- 01M4B421JA8K0E8GAC3EMWCZ5Z
- 01M4B433B8HKKXX0A08K77YCNF
position_column: doing
position_ordinal: '8180'
title: 'Subscriptions: changes feed and kanban watch support'
---
## What
GraphQL subscriptions on `KanbanGraph`. The basis is plan.md §6.7 and §12 item 17.
- `Sources/FoundationModelsKanban/Observe/ChangeFeed.swift`: subscribers with their arguments (`board`, `type`, `node`, `actor`, `filter`, `derived`). One `AsyncStream<Change>` for each subscriber.
- Sources of events: a commit in this process sends its `Change` at once; a watcher batch sends one `Change` for each new `txn`, in `txn` order, with values from the live graph before and after the batch.
- `Subscription.changes` with Graphiti `SubscriptionField`; `KanbanGraph.subscribe(query:variables:operationName:)` returns `AsyncThrowingStream<String, Error>` (one GraphQL response JSON for each event). A stream does not hold the serial gate; each `Change` is resolved through the gate.
- Filters: `type`, `node`, `filter` (matching tasks and their comments); a `Change` with no update after the filters is not sent. A subscriber on a board loads the boards that its `dependsOn` edges reach.
- `close()` ends all streams.

## Acceptance Criteria
- [x] A commit in this process sends one `Change` to a matching subscriber.
- [x] A log line that a different process appends sends one `Change`; a `union` merge that rewrites a file sends only the new transactions.
- [x] A task in a related board that becomes done sends a `DERIVED` update to a subscriber on the board of the dependent task.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift`.
- [x] Run `swift test --filter SubscriptionTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-08 01:32)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 15 file(s) reviewed, 6 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

- [x] `Sources/FoundationModelsKanban/GraphQL/Schema.swift:1167` `duplication/duplication` — The `subscribe` function repeats the rewrite-or-error block that `respond` already has. Both call `DocumentRewriter(for:).rewrittenDocument(from:)`, catch a `GraphQLError`, and wrap it in `RewriteResponse(result: GraphQLResult(errors: [error]), rewrites: [])`. A change to how rewrite errors are reported has to be made in two places. Move the rewrite step into one private helper that returns either the rewritten document or the one-error response JSON. Use it from both `respond` and `subscribe`.
- [x] `Sources/FoundationModelsKanban/Observe/ChangeSubscription.swift:57` `completeness/public-output-contract` — When a subscription names a board that has no repo directory, the resolver returns an ended stream with no response and no errors. The Schema.swift `subscribe` doc says a subscription that cannot start gives one response with the errors and then ends. In a release build the `assertionFailure` does nothing, so the client gets an empty stream with no error and no reason. The error is logged but never returned. Return a stream that yields one GraphQL error response before it ends, for example by throwing a KanbanError from `events` so that `subscribe` returns `.single(...)` through the existing failure path. Keep the log line. Do not rely on `assertionFailure` alone to reach the client.
- [x] `Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:262` `reuse/reuse` — `respond` and `startSubscription` repeat the same wrapper: call `runCall` with a schema method, then catch `KanbanError` and turn it into a response. The new subscription path copies the wrapper instead of sharing it. The two copies can diverge in how errors are handled. Add one private helper that takes the schema call and an error-mapping closure, or make `startSubscription` call `respond` and wrap the result with `.single` where needed. Keep one place that catches `KanbanError` for the gate-level calls.
- [x] `Sources/FoundationModelsKanban/Tool/KanbanGraph.swift:263` `duplication/duplication` — `respond` and `startSubscription` repeat the same wrapper: `do { return try await runCall { context in try await schema.<op>(to: query, variables: variables, operationName: operationName, formattedWith: .sortedKeys, context: context) } } catch let error as KanbanError { ... }`. Only the schema operation (`respond` vs `subscribe`) and the error wrapper (`responseJSON()` vs `.single(...)`) differ. If one copy changes, for example the formatting argument or the `runCall` arguments, the other copy drifts. Extract one private helper that takes the schema call as a closure and the error mapping as a parameter, for example `runSchemaCall(_ call: (PublicSchema, KanbanContext) async throws -> Response, onError: (KanbanError) throws -> Output)`. Call it from `respond` and `startSubscription`, and delete the second copy of the do/catch.
- [x] `Tests/FoundationModelsKanbanTests/Observe/StreamWait.swift:11` `code-hygiene/magic-numbers-swift` — Magic numbers should be replaced by named constants.