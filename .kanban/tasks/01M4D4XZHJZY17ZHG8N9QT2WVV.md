---
comments:
- actor: wballard
  id: 01m4d5ecmesem9rwz0qwhwav8p
  text: |-
    Research done.
    - `ChangeRound.after` places the engine current board C with `with(current:)`, and each key resolution that names C is `.current` (`BoardIndex.resolution(of:currentRoot:currentKey:)`). `BoardStore.reading` then does `with(current: snapshot)` with the event board B, so `.current` reads B.
    - The views of `ChangeRound` (the `fields` of each update) read `before`/`after` directly. They are correct. Only the resolvers of the event (through `BoardStore`) read the wrong board.
    - Plan: a new `RelatedBoards` method gives the value as the reads of a loaded related board B see it: the resolutions `.current` become `.copy(<copy of C>)`, the resolutions of B become `.current`, C goes into the loaded boards and B goes out, and the listing of `Query.boards` gets the same change. `KanbanGraph.publishLiveChanges` uses it for each subscribed path that is not the current repo. The engine makes the copy of C from its root and key.
    - `NodeUpdate` gets the key of the board of its node from `ChangeBuilder` (`after.boardKey`). For a `DERIVED`-only change this key is NOT `Change.boards[0]` (that is the board of the transaction), so the node needs its own key. `NodeUpdate.node` and `Change.actor` share one fileprivate lookup (`view(ofBoardNamed:)`, then `notFound(.board)` when the board is not loaded yet).
  timestamp: 2026-10-08T07:08:04.622330+00:00
- actor: wballard
  id: 01m4d5ys46qw1qjvdq0dha6p44
  text: |-
    RED, and one more defect found on the way.
    - New `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoEventBoardTests.swift` (3 tests). First run: the two subscription tests got NO event (each waited the full 10 s of `StreamWait`). Cause: `KanbanGraph.relatedBoards(updating:toAnswer:currentKey:)` started its loop with `pending = requests`. In `publishLiveChanges` the requests come from the current graph only. When the current board has no cross-board dependency, `pending` is empty, the loop body never runs, and the dependency keys of the loaded related boards get no resolution. Then a task of B that depends on C reads "not done" before and after, the `DERIVED` update has no field change, and no change goes out. The doc comment of the function already says that the loop loads each board that a dependency of a loaded board names. Fix: `pending = requests.union(updated.loadedDependencyRequests)`.
    - After that fix, the 3 tests fail on the expectations of the card: actor `NOT_FOUND` for `kanban://github.com/example/lib/actor/app-owner`; `ready: false`; `history { updates { node } }` of the related board gives `node: null`.
  timestamp: 2026-10-08T07:17:01.702569+00:00
- actor: wballard
  id: 01m4d69w7pqznapfga7q5c27wp
  text: |-
    ### implement — changed
    - evidence: `Sources/FoundationModelsKanban/CrossRepo/RelatedBoards.swift` (new `centered(onBoardAt:movingCurrentTo:)`: the related board at the path becomes `current`, the old current board goes into the loaded boards as a copy, each `.current` resolution and listing entry becomes `.copy(<old current>)`, each resolution of the path becomes `.current`, and the session of the new current board is removed, so the value serves reads only); `CrossRepo/BoardLocator.swift` (new `BoardCopy.init(directory:key:)`, which reads `isEnabled`; the scan uses it, so the check is in one place); `Tool/KanbanGraph.swift` (`publishLiveChanges` gives each related-board subscriber `eventRelatedBoards(ofBoardAt:in:currentKey:)`; `relatedBoards(updating:toAnswer:currentKey:)` starts with `requests.union(updated.loadedDependencyRequests)`); `Observe/Change.swift` (`NodeUpdate.boardKey`; `NodeUpdate.node` and `Change.actor` share the one fileprivate lookup `KanbanContext.view(ofBoardOfChange:)`); `Observe/ChangeBuilder.swift` (sets `boardKey: after.boardKey`). Tests: new `Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoEventBoardTests.swift` (3 tests). RED: actor NOT_FOUND, `ready: false`, `node: null`. GREEN: 3 of 3 pass. `swift build --build-tests`: only the accepted SwiftPM "missing creator" warning. Full `swift test --skip-build` 3 times (120 s limit): 953 tests in 66 suites passed in 13.119 s, 16.544 s, 13.386 s. periphery (`--retain-public --report-exclude 'Tests/**' --relative-results -- --build-system native --build-tests`): no unused code. swiftlint no_magic_numbers and line_length on the 6 changed files: 0 violations.
    - note: the default swiftlint set (no project config) reports `file_length` for RelatedBoards.swift (404 lines, limit 400) after this change; KanbanGraph.swift was already over its limit before this change.
    - next: /review
  timestamp: 2026-10-08T07:23:05.334746+00:00
position_column: doing
position_ordinal: '8180'
title: 'Event board of a related-board subscription: `.current` reads the wrong board'
---
## What
Found while implementing ^0ahzwrz. Two related gaps:

1. A subscriber that observes a RELATED board B (`changes(board: B)`) gets events whose store holds B (`BoardStore.replace(with:)`). The `related` value of the event is `round.after` (`KanbanGraph.publishLiveChanges`). In that value, the key of the engine current board C resolves to `.current`. But `BoardStore.reading` does `related.with(current: snapshot)`, and the snapshot is B. Thus each read of the key of C in the event resolvers reads B:
   - `Change.actor` of a `DERIVED`-only change for a transaction of C looks up the actor in B (NOT_FOUND, or the actor of B with the same slug).
   - The cross-board readiness of a task of B that depends on a task of C reads B as C.
2. `NodeUpdate.node` (Observe/Change.swift) reads `context.store.view`. For `board(id: <related>) { history { updates { node { id } } } }` the node is of the related board, but the store view is the current board of the call.

## Acceptance Criteria
- [x] A subscription on a related board B that depends on a task of the engine current board C gives, for a transaction of C, the actor of C and the correct `ready` value of the task of B.
- [x] `history { updates { node { id } } }` of a related board gives the nodes of that board.

## Tests
- [x] Tests in `Tests/FoundationModelsKanbanTests/CrossRepo/` for both criteria.