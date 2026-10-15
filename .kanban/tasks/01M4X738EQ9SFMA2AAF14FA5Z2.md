---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4ykh805r8xh8fzkgafvhv4m
  text: |-
    Research done.
    - BoardStore.reverse (S/GraphQL/UndoMutations.swift) finds the home board, then boards(of:foundIn:) changes each key of the event `boards` to target(of: .named(key)), which is the first copy in scan order. The `.filter { !events.isEmpty }` then drops that copy when it has no events of the txn. That is the X5 partial reverse.
    - The host table is KanbanHost.engines (FolderIdentity -> EngineSlot). The key of an engine is `await engine.session.key`. A view adds a host engine to its own relatedBoards through KanbanGraph.loadRelatedBoard.
    - A resolver cannot load: it records a BoardRequest, and KanbanGraph.relatedBoards(updating:toAnswer:current:) answers it and runs the call again. A new request kind is necessary for "each loaded copy in the host table with key K".
    - Event `boards` holds the normalized key text of the other boards (Commit.swift Event.recording). It never names a path, so the undo must find the copy by its events.
    - Plan §6.5: when a board of the txn is missing, undo writes nothing and gives NOT_FOUND, and the message names the board.
    - Tests: GitGraphFixture.makeGraph makes one host for each graph (one process). GitSandbox.addWorktree makes a worktree with the same key. CrossRepoUndoTests holds the cross-board undo tests.
    Plan: add UndoInput.boards ([String], board refs, also paths); add BoardRequest.copies(ofKey:) answered from the host table; choose each candidate copy (host table, named boards, scan copy) that holds events of the txn; when no copy for a key holds them, throw a new NOT_FOUND error that names the key and the txn, and write nothing.
  timestamp: 2026-10-15T01:41:23.589700+00:00
- actor: claude-code
  id: 01m4ym5rzab4m7fzdzkcg6xbvr
  text: |-
    Implementation landed (TDD).
    - RED: the new suite CrossRepoCopyUndoTests failed in all 5 tests before the change (undo reversed only the current board; the unreachable case wrote a partial undo and gave no error; `boards` was an unknown input field). KanbanErrorTests.transactionBoardNotLoadedMessage failed to compile before the new error case.
    - GREEN: the 3 suites (46 tests) pass; the full `swift test` passes: 1291 tests in 101 suites. The only build warning is the accepted SwiftPM "missing creator" warning.
    - Design: new `BoardRequest.loadedCopies(key:)`, answered by `KanbanHost.loadedCopies(withKey:)` (the host table) through `KanbanGraph.loadedCopies(withKey:)`. `BoardStore.loadedTargets(withKey:)` gives them as targets. The undo looks in the scan copy of each key, in each host-table copy with the key, and in each `boards` input board with the key, and uses each copy that holds events of the txn. No copy with the events gives the new `KanbanError.transactionBoardNotLoaded(transaction:board:)` (code NOT_FOUND, the message names the key and shows `undo(txn:, boards: [path])`). When also the scan finds no board for the key, the error stays `boardNotFound` (existing test kept).
    - New `UndoInput.boards: [String]` (board refs, also paths).
    - Known limit, not in this card: when the home board is itself a related copy, its events do not list its own key, so a second copy of that same key in the same txn is not looked for.
    - Note for the next agent: one edit was done with a python one-liner in the shell; all other edits used the files tool.
  timestamp: 2026-10-15T01:52:36.330556+00:00
- actor: claude-code
  id: 01m4ym65wxyrdfe6vt49k73z0k
  text: |-
    ### implement — changed
    - evidence: 9 files — Sources/FoundationModelsKanban/GraphQL/UndoMutations.swift, Sources/FoundationModelsKanban/GraphQL/Errors.swift, Sources/FoundationModelsKanban/GraphQL/Schema.swift, Sources/FoundationModelsKanban/CrossRepo/RelatedBoards.swift, Sources/FoundationModelsKanban/Tool/KanbanHost.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoCopyUndoTests.swift (new), Tests/FoundationModelsKanbanTests/CrossRepo/CrossRepoUndoTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/KanbanErrorTests.swift. `swift test`: 1291 tests in 101 suites passed.
    - next: /review. Follow-up task ^wwntbag records the home-key limit.
  timestamp: 2026-10-15T01:52:49.565454+00:00
- actor: claude-code
  id: 01m4ymn24cpwszxywdr079j2pa
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 9 files
    - test: green — swift test, 1291 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: 0ef789b
    - review: findings — Sources/FoundationModelsKanban/CrossRepo/RelatedBoards.swift:295
  timestamp: 2026-10-15T02:00:57.228994+00:00
- actor: claude-code
  id: 01m4ymttngdna2t8txb2xmtec6
  text: |-
    Review finding fixed: RelatedBoards.swift duplication/duplication. A new private generic helper `answer(_:otherwise:)` returns `stored ?? (canLoad ? nil : empty)`. `resolution(ofBoard:)`, `copies`, and `loadedCopies(ofKey:)` now all use it. No other `canLoad` fallback is in the file. This is a refactor with no change in behavior, so the tests that exist cover it (TDD refactor step). Note: the `dump validators` file for one Swift file was 754K characters, so it was not read whole.

    ### implement — changed
    - evidence: 1 file — Sources/FoundationModelsKanban/CrossRepo/RelatedBoards.swift. `swift test`: 1291 tests in 101 suites passed; the only build warning is the accepted SwiftPM "missing creator" warning.
    - next: /review
  timestamp: 2026-10-15T02:04:06.192263+00:00
depends_on:
- 01M4X6ZBTA66TCPVYM41QR0ACD
position_column: doing
position_ordinal: '80'
title: Make cross-board undo write nothing when it cannot reach each board, also on a second copy
---
## What
divergence.md X5 and S8 (§1.1, §7, §11 bugs; K6 stays as work). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem:
- X5: undo across boards can reverse part of a transaction, with no error. `boards(of:)` changes each key to the first copy in scan order (S/GraphQL/UndoMutations.swift:192-201). Then the undo field drops each board where the reverse wrote no events (:119). Example: a write to a second worktree of `lib`. The undo looks at the first copy, finds nothing, and reverses only the current board.
- S8: the `boards` list cannot name a second copy of the same repo. An undo reverses only one copy.

Each worktree has its own board with the same key (M6 final), so this case is normal now.

Change:
- Undo (and redo) of a transaction finds each board that the transaction wrote by the events themselves, not only by key: look in each loaded copy with that key (the host table), and use the copy that holds events of that `txn`.
- When undo cannot reach a board that the transaction wrote (no loaded copy has its events), undo writes nothing on any board and gives a clear error that names the board key. It does not reverse part of the transaction.
- Let the `boards` input of undo name a copy by path, so that an agent can name a second copy.

## Acceptance Criteria
- [x] A transaction that wrote the current board and the second copy of `lib` is reversed on both by `undo`.
- [x] When one board of the transaction is not reachable, undo writes nothing and gives an error that names that board.
- [x] `undo(boards: ["<path of second copy>"])` reaches that copy.

## Tests
- [x] Undo on a second copy (worktree) of the same repo (this is also in the K14 missing tests).
- [x] Undo with one board missing: no events written on any board.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-14 20:56)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 9 file(s) reviewed, 6 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

- [x] `Sources/FoundationModelsKanban/CrossRepo/RelatedBoards.swift:295` `duplication/duplication` — The new `loadedCopies(ofKey:)` repeats the `canLoad` fallback that `resolution(ofBoard:)` and `copies` already use. The three accessors differ only by the stored dictionary and the default value. A change to the fallback rule must now be made in three places. Add one private generic helper, for example `func answer<T>(_ stored: T?, otherwise empty: T) -> T?`, that returns `stored ?? (canLoad ? nil : empty)`. Use it in all three accessors. This is a low-severity finding because each line is short.
