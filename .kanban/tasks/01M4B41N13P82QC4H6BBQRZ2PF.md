---
comments:
- actor: wballard
  id: 01m4cbrt3r9pdkrc47mg0cvapf
  text: |-
    Research notes (implement step):
    - Inputs: the global event list is `LiveGraph.events` (event id order). A run gets it in `WorkingCopy.liveEvents` (private now); the history resolver reads it through `BoardStore.work`. The board view of the call (`BoardObject.view`) is "the graph now", the same graph that `Change.actor` and `NodeUpdate.node` read.
    - Plan: `Undo/UndoneState.swift` reads only the `undoes` of each transaction: walk the undo transactions newest first; an undo that is not undone makes its (earlier) target undone. `Undo/History.swift` groups the events by `txn`, sorts the groups by txn ULID, and replays them into a `Graph` with `NodeLog(folding:for:)` + `Graph.update(with:)` (the same fold as `WorkingCopy.apply`). It makes a `BoardView` before and after each transaction and calls `ChangeBuilder.change(of:markingUndone:)`. Views are made only for the transactions after `since`.
    - Order: transactions sort by txn ULID (newest first = largest txn). Each node fold sorts its events by event id, so the final graph is the replay graph. `since` keeps the transactions whose txn ULID sorts after it, so an unknown txn needs no new error code (plan.md §4.4 has no code for a missing transaction).
    - Filters (plan.md §6.7) use the graph now: `type`, `node` (anyLocalRef, as `Change.updates`), `actor` (storedRef of type actor, tombstones included), `filter` (FilterEvaluator over the tasks; a comment matches when its task matches), `derived: false` drops DERIVED updates. A Change with no update left is dropped. Then `first` (default 20) of the newest.
    - `Board.history` can throw (filter, ambiguous id), so it returns `[Change!]` (nullable), the same rule as `Board.tasks`.
    - The internal patch schema shares `makeKanbanBuilder()`, so `addChangeTypes()` moves there: Board references `Change`.
    - The forgiving rewrite moves a root field that only Board has into `board`. `history` is only on Board, so `{ history { txn } }` moves; a case is added to `NameRewriteTests.rootFieldMovesIntoBoard`.
  timestamp: 2026-10-07T23:39:23.128408+00:00
- actor: wballard
  id: 01m4ccftewt9ne7q752zccrpfb
  text: |-
    Implementation landed (TDD: each new test failed on an assertion first: UndoneStateTests against a stub that marked all transactions undone; HistoryTests against a resolver that gave []; the SDL and root-move tests with the field taken out of the schema; the lowercase `since` and unknown `node` tests with those two code paths taken out).
    - New: `Sources/FoundationModelsKanban/Undo/UndoneState.swift` (`UndoneState(of:)`, `isUndone(txn:)`), `Sources/FoundationModelsKanban/Undo/History.swift` (private `History`, `Projection`, `ChangeFilter`; `BoardObject.history`).
    - Changed: `GraphQL/Schema.swift` (`HistoryArguments` with defaults `derived = true`, `first = 20`; `Board.history` field; `addChangeTypes()` moved into `makeKanbanBuilder()`, because the internal patch schema shares the Board type and Board now references `Change`), `Tool/Commit.swift` (`WorkingCopy.liveEvents` is internal so the resolver can read the global event list; `apply` uses the new `Graph.update(folding:for:)`), `Events/Replay.swift` (`Graph.update(folding:for:)`, shared by the working copy and the history replay).
    - Tests: `Tests/FoundationModelsKanbanTests/Undo/UndoneStateTests.swift` (5 tests, one is the union-merge test through `BoardLoader`), `Tests/FoundationModelsKanbanTests/Undo/HistoryTests.swift` (12 tests). `ChangeBuilderTests`: new shared helper `baseSession(inRepoAt:writing:)` (also used by `record`), and `run(_:in:)` now returns the `GraphQLResult` (discardable). `NameRewriteTests.rootFieldMovesIntoBoard` has a `history` case: the root rewrite moves `{ history { txn } }` into `board`.
    - Decisions to know: (1) Transactions sort by txn ULID; newest first is the largest txn. (2) `since` keeps the transactions whose txn ULID text sorts after the given text (uppercased), so an unknown or old txn needs no new error code (plan.md §4.4 has none for a missing transaction). (3) The filters use the graph now (the same rule as `Change.actor` and `NodeUpdate.node`). (4) `node` that names no node gives no change; note that `Change.updates(node:)` from ^a72wn8t keeps all updates in that case. (5) `history` reads the committed log only; patches of the same call are not listed. (6) `Change.actor` is non-null, so a transaction whose actor node never existed in the graph would null the list (GraphQLSwift non-null rule). Real logs always have the session actor; the test fixtures run the base setup to write it.
  timestamp: 2026-10-07T23:51:57.148003+00:00
- actor: wballard
  id: 01m4ccfxn4cj2pmaza0gzw3m9w
  text: |-
    ### implement — changed
    - evidence: `swift build --build-tests` + `swift test --skip-build`: 812 tests in 48 suites passed (HistoryTests 12, UndoneStateTests 5); only the accepted SwiftPM "missing creator" build warning; `periphery scan --retain-public --quiet -- --build-tests --build-system native`: no item in the new or changed code (only the items that were there before). Files: Sources/FoundationModelsKanban/Undo/UndoneState.swift, Sources/FoundationModelsKanban/Undo/History.swift, Sources/FoundationModelsKanban/GraphQL/Schema.swift, Sources/FoundationModelsKanban/Tool/Commit.swift, Sources/FoundationModelsKanban/Events/Replay.swift, Tests/FoundationModelsKanbanTests/Undo/UndoneStateTests.swift, Tests/FoundationModelsKanbanTests/Undo/HistoryTests.swift, Tests/FoundationModelsKanbanTests/Observe/ChangeBuilderTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/NameRewriteTests.swift
    - next: /review
  timestamp: 2026-10-07T23:52:00.420906+00:00
depends_on:
- 01M4B412DB2BSB0FAQEA72WN8T
- 01M4B3Z67TC96REJGDHD2DFH0R
position_column: doing
position_ordinal: '80'
title: History query and undone state
---
## What
List the transactions of a board. The basis is plan.md §6.5 (history, undone state) and §6.7 (Arguments).
- `Sources/FoundationModelsKanban/Undo/UndoneState.swift`: a transaction is undone when a later transaction has `undoes` = its `txn` and that later transaction is not itself undone. Derived from the global event list; no stored stack.
- `Undo/History.swift`: group the global event list by `txn`; build each `Change` with `ChangeBuilder` (projection before and after the transaction).
- `Board.history(type, node, actor, filter, derived, since, first)`: newest first; `since` = only the transactions after that `txn`; `filter` keeps updates of matching tasks and of their comments; a `Change` with no update after the filters is not returned.

## Acceptance Criteria
- [x] `history` lists the transactions newest first, with `ops`, `actor`, and `updates`.
- [x] `history(since: <txn>)` returns only the later transactions.
- [x] After a `union` merge of two branches, the undone state is correct for transactions from both branches.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Undo/HistoryTests.swift` and `UndoneStateTests.swift`.
- [x] Run `swift test --filter HistoryTests` and `--filter UndoneStateTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.