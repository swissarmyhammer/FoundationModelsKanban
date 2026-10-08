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