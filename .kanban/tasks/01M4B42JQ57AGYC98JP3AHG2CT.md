---
depends_on:
- 01M4B41VDXZ3NKEG4554PVXWQN
- 01M4B412DB2BSB0FAQEA72WN8T
- 01M4B3Z67TC96REJGDHD2DFH0R
- 01M4B421JA8K0E8GAC3EMWCZ5Z
- 01M4B433B8HKKXX0A08K77YCNF
position_column: todo
position_ordinal: a480
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
- [ ] A commit in this process sends one `Change` to a matching subscriber.
- [ ] A log line that a different process appends sends one `Change`; a `union` merge that rewrites a file sends only the new transactions.
- [ ] A task in a related board that becomes done sends a `DERIVED` update to a subscriber on the board of the dependent task.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Observe/SubscriptionTests.swift`.
- [ ] Run `swift test --filter SubscriptionTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.