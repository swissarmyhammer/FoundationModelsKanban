---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4xwk52y8sheemy7mn97e3f9
  text: |-
    Research done. Discoveries:
    - Each call starts with `RelatedBoards.loadable`, so a resolution lives for one call only. A miss in `KanbanGraph.resolution(of:current:)` calls `host.rescan(around:)`. `loadEachCopy` (Query.boards) also calls `host.rescan` on each call.
    - `BoardLocator.scan(reusing:)` keeps the keys of known repos, but reads the key of each repo whose read failed again on each scan (git each call).
    - Plan: the host keeps one scan record for each list of places, with a "current" state. A miss uses the record when it is current, and scans only when it is not. A file watcher on each scan place (one FSEvents stream for each place, owned by the host) makes the record stale for a new or removed folder, a new or removed `.git`, a changed `.git/config` (forget the key of that repo), and a new `.kanban/` or `board.jsonl` (enabled state). `BoardIndex` keeps the failed key reads, so a rescan runs no git for them.
    - A generation number in the record stops a change during a scan from being lost.
    - Existing test `CrossRepoReadTests.unknownKeyScansAgain` makes a repo and calls at once. With the cache, it must wait for the watcher. A scan observer in `HostConfiguration` (the same pattern as `BoardLoadObserver`) gives the tests a count of scans and a signal when the watcher makes the record stale.
  timestamp: 2026-10-14T19:00:28.894264+00:00
- actor: claude-code
  id: 01m4xxthdrbzrzmcedzxmej5v3
  text: |-
    Implementation landed (TDD: RED seen for each new test, then GREEN).
    - New `CrossRepo/ScanChange.swift`: `ScanChange` (repo, board, commits, place), `WatchedPlace` (sorts a changed path of a scan place into a change), the index rules `BoardIndex.isExpired(by:)` and `forgetting(_:)`, and the `BoardScanObserver` test hook.
    - New `CrossRepo/ScanCache.swift`: one index for each list of places, with a "current" state. A change during a running scan makes the result not current, and the result forgets the repo of the change.
    - `BoardIndex.unreadable` keeps the failed key reads; `BoardLocator.scan(reusing:)` does not read them again.
    - `KanbanHost.currentScanIndex(around:)` replaces `rescan(around:)`. The host starts one FSEvents watcher for each scan place (before the scan), and `close()` stops them. `KanbanGraph.resolution(of:current:)` and `loadEachCopy` (Query.boards) use it.
    - Discovery: `URL.standardizedFileURL` drops `/private` only when the path exists, so it cannot compare an FSEvents path of a removed or new folder with the place. The classifier splits the path text and compares with the canonical path and the `realpath(3)` of the place.
    - Changed existing test `CrossRepoReadTests.unknownKeyScansAgain`: it now moves the new repo into the place and waits for the watcher (the old contract was "scan on each miss").
    - Known limit (not on this card): a path ref to a folder outside the scan places still runs git on each call. Card ^72zmqxw ("Put a board that a call reached by a path into the key index") covers it.

    ### implement — changed
    - evidence: `swift test` 1217 tests in 90 suites passed, 0 failures; only the accepted SwiftPM "missing creator" warning. Files: Sources/FoundationModelsKanban/CrossRepo/{ScanChange.swift (new), ScanCache.swift (new), BoardLocator.swift, RelatedBoards.swift}, Sources/FoundationModelsKanban/Tool/{KanbanHost.swift, KanbanGraph.swift, BoardEngine.swift}, Tests/FoundationModelsKanbanTests/CrossRepo/{ScanCacheTests.swift (new), ScanChangeTests.swift (new), BoardLocatorTests.swift, CrossRepoReadTests.swift}, Tests/FoundationModelsKanbanTests/Tool/KanbanHostTests.swift
    - next: /review
  timestamp: 2026-10-14T19:21:59.480276+00:00
- actor: claude-code
  id: 01m4xxtzag5g47z5jek18kgc6j
  text: 'Correction to the comment before: the card for path boards in the key index is ^gz2mxwz, not "^72zmqxw". That card puts a board reached by a path into the index, so a later ref hits the index with no git. A path ref to a folder that is not in a git repo (NOT_A_REPO), or to a repo whose key read fails, still runs `git` on each call. I record this as a new card.'
  timestamp: 2026-10-14T19:22:13.712895+00:00
- actor: claude-code
  id: 01m4xxvdt4mvb2c3as3k56543d
  text: |-
    ### implement — changed
    - evidence: `swift test` 1217 tests in 90 suites passed, 0 failures; only the accepted SwiftPM "missing creator" warning. 13 files: 2 new sources (CrossRepo/ScanChange.swift, CrossRepo/ScanCache.swift), 5 changed sources (BoardLocator.swift, RelatedBoards.swift, KanbanHost.swift, KanbanGraph.swift, BoardEngine.swift), 2 new tests (ScanCacheTests.swift, ScanChangeTests.swift), 3 changed tests (BoardLocatorTests.swift, CrossRepoReadTests.swift, KanbanHostTests.swift). New follow-up card: ^58v2scm (path refs that run git on each call).
    - next: /review
  timestamp: 2026-10-14T19:22:28.548086+00:00
depends_on:
- 01M4X6ZBTA66TCPVYM41QR0ACD
position_column: doing
position_ordinal: '80'
title: Keep a "board not found" result in memory and run no git on reads
---
## What
divergence.md §16 Gap 1 and X10 (K9 keeps it as work). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Now a board ref or a `dependsOn` URI that names no known board starts a new scan on each call (S/Tool/KanbanGraph.swift:720). The "not found" result lasts for one call only (S/Tool/Commit.swift:409). The scan runs `git` in each repo that it finds, and git runs again on each call for repos whose key read failed (S/CrossRepo/BoardLocator.swift:174-193). With P3, a URI with a typo is stored, so each call that reaches that task runs the scan again. This breaks the user rule: a read (a query, `nextTask`, a filter, search) reads no file and runs no `git`. It uses only memory.

Change:
- Keep the "not found" result for a board key (and the failed key reads) in the host, in memory.
- Scan again only when a watcher sees a new folder (or a new `.kanban/`, or a changed git remote) in a scan place. Then clear the cached "not found" results.
- A read never runs `git` and never scans.

## Acceptance Criteria
- [x] A second call that reaches the same unknown key runs no scan and no `git`.
- [x] When a new repo with that key appears in a scan place, the watcher clears the cache and the next call finds the board.
- [x] Reads run no `git` (check with a git-call counter or test hook).

## Tests
- [x] Two calls that reach an unknown key: the scan runs one time.
- [x] A new repo folder in a scan place: the next call resolves the key.
- [x] A counter of git runs stays the same over many read calls.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.