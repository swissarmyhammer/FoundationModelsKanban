---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5as7egx8ptn65gpj0n8xqrz
  text: |-
    Research done. Findings and plan:
    - A call runs in CommitSession.run: each run has a new WorkingCopy of the live graph, and a commit that finds a changed log applies the changed files and runs the call again. A run can also run again after a load of related boards. Thus a side effect in a resolver must happen one time for each call.
    - Plan: collectBoards writes the union of the source node logs to the target node logs at file level, one time for each call, under the locks of all boards (EventLog.lock(sortedByKey:)), with LogFileMark rollback and fsync, then removes each source .kanban. A call-scoped record (in KanbanContext) keeps the result, so a later run of the same call does not write again.
    - The `collected` board patches (old names of the target, and the source path) and the link repairs are normal kept patches of the call (one txn, ops collectBoards). The commit of the first run finds the changed target logs, applies them, and runs the call again, so the repairs of the last run read the merged graph.
    - The board log of a source is not merged: its board IDs, git key and old names become old names of the target through the collected patch. Thus the primary ID of the target does not change.
    - Links whose board key is a source name check against the target itself, because the scan index can still hold the source copy.
    - Undo: UndoLog must skip a collectBoards transaction (final).
    - After the call, the host expires the scan index for the target and the source folders.
  timestamp: 2026-10-19T19:11:47.229838+00:00
- actor: claude-code
  id: 01m5atb7z65bxf15hhqrrjjqst
  text: |-
    Implementation landed. The first plan changed: the commit does the whole write, so no call-scoped record is necessary.
    - WorkingCopy has `merged` (foreign events, written as they are, with their own txn, ops, and file count) and `collectedSources`. `merge(_:)` folds the source events into the working graph. BoardWrite writes kept and merged events; the file count of the call txn counts the kept nodes only.
    - The commit locks the sources with the other boards (EventLog.lock(sortedByKey:)), treats a changed source as a changed log (the call runs again), and removes each source .kanban after the append and the fsync, under the locks. A failed append rolls back with LogFileMark, and the sources stay.
    - The board log of a source is not merged. One `collected` board patch for each source sets the record (path, boardIds, gitKey, oldNames) and adds each source name to oldNames. Thus the primary ID of the target does not change, and a URI with a source name resolves to the target (RefResolver reads oldNames).
    - Link repair: checkedLinks(of:naming:) now takes the own names of the board, so a link with a source name checks against the merged target, and not against the stale scan copy of the source. Other boards: links that name a source are listed in otherLinks, and written only with reach.
    - Undo: a transaction with the op collectBoards is final. Undo with no txn takes only a transaction after the newest final one. Finding: without this barrier, undo took a merged transaction of a source (the same session actor), which is a surprise for the user.
    - Not done here: no explicit expire of the host scan index. The place watchers see the changed board logs and the removed source folders, the same as for each other write (see ^5agge22nag).
    - Shared Map.plainText (moved from PriorityValue) for conflict values.
  timestamp: 2026-10-19T19:31:20.166575+00:00
- actor: claude-code
  id: 01m5atbggmq7gwef47nwfyapsk
  text: |-
    ### implement — changed
    - evidence: swift test: 1684 tests in 139 suites passed, 0 build warnings (13 new tests in CollectBoardsTests). Files: Sources/FoundationModelsKanban/CrossRepo/BoardCollect.swift (new), Sources/FoundationModelsKanban/GraphQL/CollectBoardsField.swift (new), Tests/FoundationModelsKanbanTests/CrossRepo/CollectBoardsTests.swift (new), Tool/Commit.swift, Undo/UndoLog.swift, GraphQL/CheckLinksField.swift, GraphQL/RepairLinksField.swift, GraphQL/FieldAliases.swift, GraphQL/Schema.swift, GraphQL/SchemaDescription.swift, GraphQL/PriorityInput.swift, Tool/KanbanTool.swift.
    - next: /review
  timestamp: 2026-10-19T19:31:28.916112+00:00
- actor: claude-code
  id: 01m5atph8xdwk9qd7jcknx0jc2
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (0f33760). 3 findings confirmed, 2 refuted — Sources/FoundationModelsKanban/Tool/Commit.swift:295, Sources/FoundationModelsKanban/Tool/Commit.swift:873, Tests/FoundationModelsKanbanTests/CrossRepo/CollectBoardsTests.swift:207
    - next: Implement the 3 open items in the "Review Findings (2026-10-19 14:33)" section. The task stays in review.
  timestamp: 2026-10-19T19:37:30.141508+00:00
- actor: claude-code
  id: 01m5atq2bst8ekxhcqkbyj2cz5
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 12 files
    - test: green — swift test, 1684 passed
    - commit: 0f33760
    - review: findings — Commit.swift:295, Commit.swift:873, CollectBoardsTests.swift:207
  timestamp: 2026-10-19T19:37:47.641053+00:00
- actor: claude-code
  id: 01m5atxcd9vjazqq7h5d3aamcr
  text: |-
    Review fixes:
    - Commit.swift:295 reuse: added `private func events(of ref: LocalRef) -> [Event]` on WorkingCopy. apply(_:at:undoing:) and merge(_:) use it. Note: in merge(_:) the parameter `events` hides the method, so the call is `self.events(of:)`. In apply, the local is `current` (Swift refuses `let events = events(of:)`).
    - CollectBoardsTests.swift:207 reuse: removed `errorCode(of:)`. The two tests now use `ErrorCoverageTests.code(of:)` on the first error of `NameRewriteTests.errors(of:)`.
    - Commit.swift:873 invariant-propagation: NOT done. It is a true conflict with a documented contract. divergence.md Q23: each line records "the count of files that the transaction wrote in this board". `IncompleteTransactions.isComplete` (Events/TransactionCheck.swift) groups by `txn` and counts the distinct nodes with lines of that `txn`. A merged event keeps its own `txn` and its own `files`, so its log does not hold lines of the collect transaction. With `writtenNodes.count`, the collect `txn` has lines in only `keptNodes.count` files, and each load holds the collect transaction always. Also, a partial crash cannot apply a partial collect transaction now: each merged transaction has its own count and the load checks it, and the source folders stay until after the fsync. A person must decide: drop the finding, or change the Q23 contract.
  timestamp: 2026-10-19T19:41:14.537243+00:00
- actor: claude-code
  id: 01m5atxf5gd06vf2f75xyz3nhr
  text: |-
    ### implement — stuck
    - evidence: 2 files — Sources/FoundationModelsKanban/Tool/Commit.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CollectBoardsTests.swift. swift build --build-tests: 0 warnings (only the accepted SwiftPM "missing creator" warning). swift test: 1684 tests in 139 suites passed. Findings Commit.swift:295 and CollectBoardsTests.swift:207 are fixed and checked. Finding Commit.swift:873 is open with a BLOCKER: it conflicts with divergence.md Q23 and IncompleteTransactions.isComplete.
    - next: a person decides on Commit.swift:873 (drop the finding, or change the Q23 contract). The task stays in doing.
  timestamp: 2026-10-19T19:41:17.360711+00:00
- actor: claude-code
  id: 01m5atyrkcphhthyvdhfgwcss0
  text: |-
    ### finish iteration 2 — stuck
    - implement: stuck — fixed Commit.swift:295 and CollectBoardsTests.swift:207; Commit.swift:873 not done
    - test: green — swift test, 1684 passed (implement run)
    - commit: c6b3d70 (checkpoint of the 2 fixes)
    - review: not run
    - blocker: the finding at Commit.swift:873 asks for `writtenNodes.count` as the Q23 file count. This conflicts with divergence.md Q23 and `IncompleteTransactions.isComplete` (Events/TransactionCheck.swift), which count only the nodes that hold lines of the same `txn`. Merged events keep their own `txn` and `files`. With the change, each load holds the collect transaction always.
    - next: a person decides. Drop the finding, or change the Q23 contract (for example, a second count for merged files). Then run /finish ^e8wypkz again.
  timestamp: 2026-10-19T19:41:59.788505+00:00
depends_on:
- 01M52RKV2MX3F84VYXAD5Y7AAY
- 01M52RM3SJT6S3R1PVF99E0H99
position_column: review
position_ordinal: '80'
title: Add collectBoards to combine .kanban folders into one target board
---
## What
divergence.md M9 "collectBoards". A user can combine any list of `.kanban` folders into one target `.kanban`, for example the subfolder boards below a repo top, or boards made by mistake with search up (^d5y7aay).

## Do
- `collectBoards(sources:, target:, dryRun:, reach:)`. A source is any folder or board ref.
- Add the event lines of each source node log to the target node log with the same name (the same as a git union merge). Tasks and comments keep their ULIDs. The same slug for a column, tag, or actor becomes one node. List each field conflict and the value that won by event order.
- Write one `collected` event on the target board for each source: each board ID, git key, and old name of the source, and the source path, time, and actor. These become old names of the target (^e65466d).
- When the target has no board, make it with a new ULID. In a git repo the target must be the repo top.
- Lock all boards. A Rust board stops the call with `INCOMPATIBLE_BOARD`. The write is crash safe.
- Remove each source `.kanban` folder after the write.
- Collect is final; `undo` does not reverse it. `dryRun: true` reports the slug merges, the conflicts, and the link repairs, and writes nothing.
- Run `checkLinks` and `repairLinks` (^rctvtvc, ^99e0h99) on the target. Repair other reachable boards only with `reach: true`. Always report the old-name links found in other boards.

## Acceptance Criteria
- [x] Two boards with tasks, comments, and a shared `todo` column collect into one board with all tasks and one `todo` column.
- [x] A URI with an old name of a source resolves to the target after collect.
- [x] A `dependsOn` between the two sources becomes a local ref.
- [x] Each source folder is removed. `dryRun: true` writes and removes nothing.
- [x] A target with no board is made.
- [x] A Rust source stops the call and writes nothing.
- [x] Tests use temporary folders and temporary git repos only.

## Review Findings (2026-10-19 14:33)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 12 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/Tool/Commit.swift:295` `reuse/reuse` — The new merge(_:) builds the current event list of a node with the same expression that apply(_:at:undoing:) already uses. Two copies of this lookup can drift apart, for example if one side later changes its fallback to the live events. Move the expression into one private helper on WorkingCopy, for example `private func events(of ref: LocalRef) -> [Event]`, and call it from both apply(_:at:undoing:) and merge(_:).
- [ ] `Sources/FoundationModelsKanban/Tool/Commit.swift:873` `completeness/invariant-propagation` — The Q23 file count recorded on each kept event is `keptNodes.count`, but the same transaction also appends merged events to the node logs in `writtenNodes` (`keptNodes` plus the nodes of `work.merged`). The count therefore omits every log file that only holds merged events. A load then treats the transaction as complete after fewer files than were written, so a crash that leaves only some of the files can pass the completeness check and apply a partial transaction. Use the same set for the count as for the writes: `let fileCount = writtenNodes.count`, and compute it before the `recorded` map. Add a test where a collect merges an event into a node that the kept patches do not touch, then check that the recorded `files` equals the number of node logs appended to.
  - **BLOCKER (conflict with a documented contract):** divergence.md Q23 says that each line records "the count of files that the transaction wrote in this board". `IncompleteTransactions.isComplete` (Events/TransactionCheck.swift) groups the events by `txn` and compares the count with the number of distinct nodes that hold lines of that `txn`. A merged event keeps its own `txn` and its own `files`, so it is not part of the collect transaction. The lines of the collect transaction are only in the `keptNodes` logs. With `writtenNodes.count`, each load finds fewer files for the collect `txn` than the count, and holds the collect transaction always (its `collected` names and link repairs never apply). Thus the fix that the finding asks for breaks the load. A person must decide: drop the finding, or change the Q23 contract (for example, a second count for the merged files). The code is not changed for this item.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/CollectBoardsTests.swift:207` `reuse/reuse` — The `errorCode(of:)` helper rebuilds the `extensions.code` lookup that already exists in `ErrorCoverageTests.code(of:)`. The copy repeats the same error-to-code extraction, so a fix to one would not reach the other. Call `ErrorCoverageTests.code(of:)` on the first error from `NameRewriteTests.errors(of:)`, for example `try #require(ErrorCoverageTests.code(of: try #require(NameRewriteTests.errors(of: response).first)))`, and remove the local extraction.