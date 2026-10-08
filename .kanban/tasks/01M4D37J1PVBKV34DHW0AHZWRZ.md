---
comments:
- actor: wballard
  id: 01m4d4q54cwtrxfvn7fj7jhaaj
  text: |-
    Research done.
    - `Change.boards[0]` is the key of the board of the transaction: `ChangeBuilder.change(of:patching:inBoard:)` sets `[key] + first.boards`. For `history` it is the key of the history board. For a `DERIVED`-only change it is the key of the changed board (`derivedChange(of:inBoard:)`).
    - The lookup to reuse: `BoardStore.view(ofBoardNamed:)`. A current key gives `.current`. A related key gives the loaded copy, or `nil` and a `BoardRequest` (the run then runs again after the load), or `boardNotFound`.
    - For a subscription, the store of each event gets `round.after` (`KanbanGraph.publishLiveChanges`). It has a resolution for each key that a dependency of a loaded board names. Thus the key of a board that sends a `DERIVED`-only change has a resolution.
    - Known gap (not in this card): when the subscriber observes a RELATED board, `round.after` maps the engine current board to `.current`, but `BoardStore.reading` replaces `.current` with the board of the subscriber. Then a key of the engine current board reads the subscriber board. This also changes the cross-board readiness of the event resolvers. I record it as a new task.
    RED: new `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoActorTests.swift` (2 tests). Both fail on the expectation: the `history` response has `history: null` with NOT_FOUND `kanban://github.com/example/app/actor/lib-owner`, and the subscription event has `errors` NOT_FOUND for `changes.actor`.
  timestamp: 2026-10-08T06:55:23.276808+00:00
- actor: wballard
  id: 01m4d4y5exehhsra21bmsbqcb2
  text: |-
    ### implement — changed
    - evidence: `Sources/FoundationModelsKanban/Observe/Change.swift` (`Change.actor` finds the board of the first key of `boards` with the existing `BoardStore.view(ofBoardNamed:)`. A key that the scan cannot find throws `boardNotFound` from that lookup. A board that the engine did not load yet gives `nil`: the store records the request and the run is done again; the field throws `notFound(type: .board, ...)` for that run, and the engine drops that response). Tests: new `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoActorTests.swift` (2 tests), `Tool/GitGraphFixture.swift` (new `actingAs` parameter, default `KanbanGraphTests.sessionActor`), `Observe/SubscriptionTests.swift` (`oneEvent` is now internal, so that the new suite uses it). RED: 2 of 2 failed on the expectation (NOT_FOUND for `kanban://github.com/example/app/actor/lib-owner`). GREEN: 2 of 2 pass. `swift build --build-tests`: only the accepted SwiftPM "missing creator" warning. Full `swift test --skip-build` 3 times (120 s limit): 950 tests in 65 suites passed in 10.803 s, 10.627 s, 14.075 s. periphery (`--retain-public --report-exclude 'Tests/**'`): no unused code. swiftlint no_magic_numbers and line_length 120 on the 4 changed files: 0 violations.
    - new task: ^9qt2wvv (the event board of a subscription on a related board reads `.current` as the subscriber board; `NodeUpdate.node` of a related history reads the current board).
    - next: /review
  timestamp: 2026-10-08T06:59:12.989606+00:00
- actor: wballard
  id: 01m4d57fjxmrsqv4mnhm15ge82
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (742e964). 0 findings, 0 confirmed, 0 refuted. 4 files reviewed. 6 .kanban files not reviewed (.reviewignore).
    - next: none. The task is in done.
  timestamp: 2026-10-08T07:04:18.269524+00:00
- actor: wballard
  id: 01m4d57nhm9bddgevhne7c7vdw
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 4 files (Observe/Change.swift, new CrossRepoActorTests.swift, GitGraphFixture.swift, SubscriptionTests.swift)
    - test: green — swift test 3 runs with a 120 s limit, 950 passed each (14.4 s, 13.5 s, 13.9 s); build warnings only the 2 accepted kinds
    - commit: 742e964
    - review: clean — 0 findings
  timestamp: 2026-10-08T07:04:24.372860+00:00
position_column: done
position_ordinal: b480
title: 'Change.actor: resolve the actor in the board of the change'
---
## What
`Change.actor` (Observe/Change.swift) resolves `actorRef` in `context.store.view`: the current board of the call. Two cases give the wrong board:
- `board(id: <related>) { history { actor { name } } }`: the change is of the related board, and its actor ref is local to that board.
- A `DERIVED`-only change of the change feed (plan.md §6.7, derived updates across boards): the subscriber observes board A, and the transaction is of board B. The actor ref is local to B.
When board A has no actor with that slug, the field gives `NOT_FOUND`, and `actor: Actor!` makes the full change `null`.

Found while implementing ^3ahg2ct. Resolve the actor in the board whose key is `Change.boards[0]` (the board of the change), for example through the related boards of the view.

## Acceptance Criteria
- [x] `history { actor { name } }` of a related board gives the actor of that board.
- [x] A `DERIVED`-only change of a subscription gives the actor of the board of the transaction.

## Tests
- [x] A test in `Tests/FoundationModelsKanbanTests/Undo/HistoryTests.swift` or `CrossRepo` with an actor that only the related board has.