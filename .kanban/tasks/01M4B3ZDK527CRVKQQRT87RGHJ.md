---
comments:
- actor: wballard
  id: 01m4bsxrf0z50pwcymtvc6pzvv
  text: |-
    Research done. Findings:
    - KanbanGraph keeps a BoardStore that holds the live graph. Resolvers change it directly. No LiveGraph is in KanbanGraph yet, no ULID source, and no session actor value (the `actor` argument of the public init is not used).
    - NodeFold in Replay.swift is private. A patch can change a node only by a fold of all the events of that node. Thus the working copy folds the node again from its events (the events of the live graph plus the kept events). This gives the same state that a replay after the commit gives.
    - The event ids of one call must increase. Replay sorts by id, and two `edit` diffs of one body must apply in order. SystemULIDSource gives random bits, so two ids in the same millisecond can be out of order. The stamp makes each id larger than the one before.
    - The `updateBoard` stub changes the graph with no patch. The working copy has no write path without a patch, so the stub now writes `set name` and an `edit` diff through the working copy. The board card (^rck1fp8) keeps the full updateBoard and initBoard work.
    - The session actor for the envelope: the public init now uses the slug of `actor`, else the OS user name. The board card still must make sure that the actor node exists.
    - Plan: Tool/Commit.swift gets EventStamp, WorkingCopy (runField, apply with the trim of parts that change nothing), Committer (the run loop, 5 runs, BOARD_BUSY), and the lock/check/append on LiveGraph. The `patch` resolver applies one PatchInput to the working copy of the context.
  timestamp: 2026-10-07T18:27:30.912168+00:00
- actor: wballard
  id: 01m4btfp9ccb429sc6bvddyx04
  text: |-
    Implementation landed (TDD: CommitTests, the KanbanGraph session actor tests, and the KanbanErrorTests response JSON test were written first and failed to compile, then pass).

    What is where:
    - Tool/Commit.swift: `EventStamp` (txn, actor, event ids that always increase), `WorkingCopy` (`runField(as:_:)` runs a field on a copy-on-write copy and drops it on a throw; `apply(_:at:)` keeps only the parts that change, makes the event, folds the node again from all its events), `CommitSession` (the run loop, `maximumRuns = 5`, `BOARD_BUSY`; the commit takes `EventLog.lock(sortedByKey:)`, compares `nodeFileSignatures()` with the live signatures, applies changed files and runs again, else appends with the `ops` of the full call and calls `LiveGraph.adopt`).
    - Events/Replay.swift: `NodeLog(folding:for:)` and `PatchInput.changes(afterFolding:)` (the trim: the fold decides, so an add and a remove of one member in one patch keep the fold result).
    - Observe/LiveGraph.swift: `log` accessor and `adopt(_:writing:)`; the signature read and the state install are shared with `reload`.
    - GraphQL/PatchSchema.swift: the `patch` resolver applies the input to the working copy through `runField(as: nil)`.
    - GraphQL/Schema.swift: `BoardStore` now holds the `WorkingCopy`; the `updateBoard` stub writes `set name` and an `edit` diff (op name `PublicSchema.updateBoardField`).
    - GraphQL/Errors.swift: `responseJSON()` gives `{"errors":[...]}` for BOARD_BUSY.
    - Tool/KanbanGraph.swift: keeps a `CommitSession`; `sessionActor(named:)` = slug of the actor name, else of `NSUserName()`; the internal init takes `actingAs:` and `mintingFrom:`.

    Notes for the next cards:
    - Only one board is locked and `boards` is always nil. The multi-board commit card (^k77ycnf) must add the other changed and rule-read boards to the lock dictionary and fill `boards`.
    - A field that keeps no patch adds no name to `ops`. The `patch` mutation adds no name.
    - The board card (^rck1fp8) still owns auto-init, initBoard, and the "make sure the session actor exists" rule. The session actor slug fallback is done here.
    - A test `BoardStore.fixture(of:inBoard:)` (QueryFixture.swift) has no events; a mutation of a fixture node folds from the empty state.
  timestamp: 2026-10-07T18:37:18.508315+00:00
- actor: wballard
  id: 01m4btg3r6jy2vmkkkv8x6gvk6
  text: |-
    ### implement — changed
    - evidence: 2 new files (Sources/FoundationModelsKanban/Tool/Commit.swift, Tests/FoundationModelsKanbanTests/Tool/CommitTests.swift), 11 changed (Events/Replay.swift, Observe/LiveGraph.swift, GraphQL/PatchSchema.swift, GraphQL/Schema.swift, GraphQL/Errors.swift, Tool/KanbanGraph.swift, Tests: KanbanGraphTests, KanbanErrorTests, QueryFixture, TaskQueryFixture, GraphQLEngineTests). `swift test --filter "CommitTests|KanbanGraphTests|KanbanErrorTests|GraphQLEngineTests"`: 57 tests in 4 suites passed. `swift test`: 581 tests in 36 suites passed, 0 warnings. `periphery scan --retain-public ... -- --build-tests --build-system native`: no unused code.
    - next: /review
  timestamp: 2026-10-07T18:37:32.294657+00:00
depends_on:
- 01M4B3YYXT069TKADQ93CBAA93
- 01M4B3X08THVXHAJEQ4Z8PDB4H
- 01M4B4ADV9EPW7N9VGBVBVV8WM
- 01M4B4A8735GAP57Q8ZVDP5HY2
position_column: doing
position_ordinal: '8180'
title: 'Commit path: patch mutation, locks, signature check'
---
## What
The write side of a call. The basis is plan.md §5.4 steps 4 to 6.
- `Sources/FoundationModelsKanban/GraphQL/PatchSchema.swift`: the internal `patch` mutation applies one `PatchInput` to a working `Graph`.
- `Sources/FoundationModelsKanban/Tool/Commit.swift`: a mutation field works on a copy-on-write working copy. It makes patches (only the properties that change), applies them, checks the graph rules, and keeps them. A failed field discards only its own patches.
- Commit at the end of the call: lock each changed or rule-read board in key order; under the locks, compare the file signatures and the list of node files with the live graph; if a log changed, apply the changed files, discard the working copy, and run the call again; after 5 runs, return `BOARD_BUSY`. Append each patch with the `txn`, `ops`, and `boards` of the full call. Record the new signatures, then the working copy becomes the live graph.
- A call that changes nothing writes nothing.

## Acceptance Criteria
- [x] A failed mutation field writes none of its patches; the other fields of the call are written.
- [x] A file that changes before the commit makes the call run again; 5 changed runs give `BOARD_BUSY` and write nothing.
- [x] A failed field or a run again does not change the live graph.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Tool/CommitTests.swift`: drive the commit with a test mutation; simulate a write by a different process between the load and the commit.
- [x] Run `swift test --filter CommitTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.