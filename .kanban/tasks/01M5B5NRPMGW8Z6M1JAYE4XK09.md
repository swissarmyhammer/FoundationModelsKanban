---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5bcznchrza1e9xj7859hywv
  text: |-
    Research:
    - `Event.files` is `Int?` now. `recording(fileCount:)` sets it. Commit `append(recording:changing:)` records `keptNodes.count` on each kept line. Merged collect lines keep their own `files` value, because `recording(operations:changing:inBoard:)` copies it.
    - The loader (`BoardLoader.readStages`) and `LiveGraph.reload` (through `readStages`) both use `IncompleteTransactions`. A change in `IncompleteTransactions` changes the two paths.
    - A "file" of a transaction is the node log of `patch.node`. `LocalRef` is `TextCodable`, so a list of refs encodes as a list of strings.
    - No test captures swift-log output. The warning text must come from a value that a test can read.
    - Plan: a new `TransactionFiles` enum (`.count(Int)` for old lines, `.refs([LocalRef])` for new lines). A count still encodes as a number, so that a merged old line keeps its own field. Commit writes only `.refs`.
  timestamp: 2026-10-20T00:57:03.633679+00:00
- actor: claude-code
  id: 01m5bdft94gv34x9kythw8n47w
  text: |-
    Implementation landed.
    - New `TransactionFiles` enum in `Event.swift`: `.count(Int)` (old lines) and `.refs([LocalRef])`. Decode reads a number or a list. Encode writes the form that the value has, so a merged old line keeps its own field. `Event.recording(files:)` records only a sorted list. `recording(fileCount:)` is removed.
    - `IncompleteTransactions` now holds `missingFiles: [ULID: [LocalRef]]`. The named files are the union of the lists of the lines of the transaction. With no list, the largest count applies (an empty missing list). `holdDetail` gives the warning text, and `recordHold()` logs it as `missingFiles` metadata. The loader and `LiveGraph.reload` use this type, so both get the same check.
    - Commit records `keptNodes` as the list. Merged collect lines keep their own field.
    - Discovery: after `collectBoards`, a fresh load of the target holds the merged lines of a source transaction that also wrote the source `board` log, because collect does not merge the board log. The old count check had the same problem (7 files counted, 6 in the target). This needs a decision, so I added ^16js6jx. The collect test of this card checks only the collect transaction.
    - Set equality of events with JSON object values failed after a round trip in the collect test, so that test compares event ids.
  timestamp: 2026-10-20T01:05:52.932573+00:00
- actor: claude-code
  id: 01m5bdfwpvamndftea97d2ykrr
  text: |-
    ### implement — changed
    - evidence: Sources/FoundationModelsKanban/Events/Event.swift, Sources/FoundationModelsKanban/Events/TransactionCheck.swift, Sources/FoundationModelsKanban/Tool/Commit.swift, Tests/FoundationModelsKanbanTests/Events/EventTests.swift, Tests/FoundationModelsKanbanTests/Events/TransactionCheckTests.swift, Tests/FoundationModelsKanbanTests/Tool/CommitCrashSafetyTests.swift, Tests/FoundationModelsKanbanTests/CrossRepo/CollectBoardsTests.swift; `swift test`: 1700 tests in 140 suites passed, only the accepted SwiftPM "missing creator" warning.
    - next: /review. Follow-up task ^16js6jx needs a human decision.
  timestamp: 2026-10-20T01:05:55.419189+00:00
- actor: claude-code
  id: 01m5bdnnjmh4hysv2pxgx7hcj4
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD (8048b50). 6 findings, 6 confirmed, 1 refuted. Sources/FoundationModelsKanban/Events/Event.swift:183, Sources/FoundationModelsKanban/Events/TransactionCheck.swift:39 (2 findings), Sources/FoundationModelsKanban/Events/TransactionCheck.swift:79, Tests/FoundationModelsKanbanTests/Events/TransactionCheckTests.swift:179, Tests/FoundationModelsKanbanTests/Events/TransactionCheckTests.swift:199
    - next: correct the 6 open items in "Review Findings (2026-10-19 20:06)". The task stays in review.
  timestamp: 2026-10-20T01:09:04.724989+00:00
- actor: claude-code
  id: 01m5bdpcdz4vnsshvjxmejkma4
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — Event.swift, TransactionCheck.swift, Commit.swift, 4 test files
    - test: green — swift test, 1700 passed (run by the implement step on the same tree)
    - commit: 8048b50
    - review: findings — Events/Event.swift:183, Events/TransactionCheck.swift:39 (x2), Events/TransactionCheck.swift:79, TransactionCheckTests.swift:179, TransactionCheckTests.swift:199
  timestamp: 2026-10-20T01:09:28.127642+00:00
- actor: claude-code
  id: 01m5bdyhbzsy32atn8x3znmn09
  text: |-
    Review findings corrected.
    - Items 1-3: `LocalRef` is now `Comparable` by its text (`Identity/LocalRef.swift`). `TransactionFiles.named`, `IncompleteTransactions.missingFiles(of:)`, and both sorts in `Tool/Commit.swift` (the apply of the changed files and `synchronize()`) call `sorted()`. Item 2 said not to edit Commit.swift; item 1 says to call the shared order from the commit code. Item 1 was followed, because only then no copy of the comparator stays. A line under item 2 on the card records this.
    - Item 4: the `namedRefs` and `oldCount` accessors are removed. `missingFiles(of:)` reads each line with one `switch` on `event.files`.
    - Items 5-6: `StrayFixture` is removed. `Fixture` has an optional `missing` field. A new `makeBoard(taskCount:)` helper makes the folder, the log, and the board tasks; `makeFixture`, `makeStrayFixture`, and the two other tests with the same setup call it.
    - New test `LocalRefTests.refsSortByText`: RED was a compile error (LocalRef not Comparable), then GREEN.
    - Discovery: `BoardCollect.swift` and `Loader.swift` also sort local refs by `description`. They are out of the scope of this card, so I added a follow-up task.
  timestamp: 2026-10-20T01:13:55.327374+00:00
- actor: claude-code
  id: 01m5bdyqjba2jm9x0g3d1jgrxw
  text: |-
    ### implement — changed
    - evidence: Sources/FoundationModelsKanban/Identity/LocalRef.swift, Sources/FoundationModelsKanban/Events/Event.swift, Sources/FoundationModelsKanban/Events/TransactionCheck.swift, Sources/FoundationModelsKanban/Tool/Commit.swift, Tests/FoundationModelsKanbanTests/Identity/LocalRefTests.swift, Tests/FoundationModelsKanbanTests/Events/TransactionCheckTests.swift; `swift test`: 1701 tests in 140 suites passed, only the accepted SwiftPM "missing creator" warning.
    - next: /review. Follow-up task ^m2sdwxr for the other LocalRef text sorts.
  timestamp: 2026-10-20T01:14:01.675195+00:00
- actor: claude-code
  id: 01m5be1s5jcmhbmn5y808m8r8m
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (commit 4226aac). 6 files reviewed, 4 .kanban files not reviewed (ignore rule). Counts: findings 0, confirmed 0, refuted 1, attempted 7, failed 0. All 6 items of the 2026-10-19 20:06 findings are checked.
    - next: none. The task is in done.
  timestamp: 2026-10-20T01:15:41.618184+00:00
- actor: claude-code
  id: 01m5be21jm5gysmpgq4zn0mg96
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — LocalRef.swift, Event.swift, TransactionCheck.swift, Commit.swift, LocalRefTests.swift, TransactionCheckTests.swift
    - test: green — swift test, 1701 passed (run by the implement step on the same tree)
    - commit: 4226aac
    - review: clean — 0 findings
  timestamp: 2026-10-20T01:15:50.228848+00:00
position_column: done
position_ordinal: ffa580
title: Record the refs of the written files in each transaction line, not a count
---
## What
divergence.md Q23, "Changed (2026-10-19)". Each event line of a transaction records the local refs of all the log files that the transaction writes in its board, not the count of these files. A count cannot tell which file is missing, and a wrong file with the same `txn` can fill it.

## Do
- `Event.files` (`S/Events/Event.swift`): decode the old number and the new list of local refs. Encode only the list. A line with no field is complete.
- The commit path (`S/Tool/Commit.swift`, `append(recording:changing:)`): record the refs of `keptNodes`, sorted, on each kept line. The merged lines of a `collectBoards` call keep their own field.
- `IncompleteTransactions` (`S/Events/TransactionCheck.swift`): a transaction with a list is complete only when each named ref has a line with that `txn`. A transaction with only old numbers keeps the count check. When lines have both kinds, the list applies.
- `recordHold()`: name the missing refs of each held transaction.
- `LiveGraph.reload` and the loader use the same check.
- Use the file editing tool only. Do not edit plan.md.

## Acceptance Criteria
- [x] A transaction with one named file cut off is held, and the warning names the missing ref.
- [x] A transaction is held when a file that the list does not name holds a line of the `txn`, and a named file is missing.
- [x] A complete transaction is applied.
- [x] An old line with a number is checked by count, and an old line with no field is applied.
- [x] A collect transaction lists only the files of its new lines, and it is applied after a load.
- [x] Tests use temporary folders only.

## Review Findings (2026-10-19 20:06)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 7 file(s) reviewed, 6 not reviewed.

> 6 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 6 file(s)

- [x] `Sources/FoundationModelsKanban/Events/Event.swift:183` `reuse/reuse` — The new `named` function sorts LocalRef values by `description` with an inline comparator. The same comparator is written again in the new missingFiles code, and it already appears in the commit code. Each copy is a separate place that must agree on the sort order. Add one shared sort helper for LocalRef by text, or a Comparable conformance if one fits the type, and call it from all three sites.
- [x] `Sources/FoundationModelsKanban/Events/TransactionCheck.swift:39` `duplication/duplication` — The new sort of missing refs by `lhs.description < rhs.description` repeats the same comparator that the new `TransactionFiles.named` uses. The comparator is copied, not shared, so a change to the ref sort order must be made in two places. Give one shared sort, for example a `LocalRef` ordering or a small static helper that both call sites use. Then use it at Event.swift:183 and TransactionCheck.swift:39. Keep the change in the changed code. Do not edit Commit.swift:900 in this change.
  - Commit.swift also calls the shared order, because item 1 tells the change to call it from the commit code, and only then is no copy of the comparator left.
- [x] `Sources/FoundationModelsKanban/Events/TransactionCheck.swift:39` `reuse/reuse` — The new missingFiles code sorts LocalRef values by `description` with an inline comparator that duplicates the sort in Event.swift `named`. This is the second copy in the change. Call the same shared LocalRef text-sort helper that Event.swift `named` uses.
- [x] `Sources/FoundationModelsKanban/Events/TransactionCheck.swift:79` `reuse/reuse` — The new namedRefs and oldCount accessors repeat the same guard-case extraction pattern. Each one unwraps one case of TransactionFiles and returns nil for the other. Two parallel accessors for one enum add a second copy of the same shape. Use the enum's own pattern directly at the two call sites (for example `if case .refs(let refs)?`), or keep one generic helper. Do not keep two copies of the same accessor.
- [x] `Tests/FoundationModelsKanbanTests/Events/TransactionCheckTests.swift:179` `reuse/reuse` — The new StrayFixture struct repeats the fields of the existing Fixture struct (directory, log, tasks, events). Only the extra `missing` field differs. A parallel type makes two fixture shapes to keep in step. Give Fixture an optional or extra field for the missing task, or make StrayFixture reuse Fixture with a `missing` property added to Fixture. Keep one fixture type.
- [x] `Tests/FoundationModelsKanbanTests/Events/TransactionCheckTests.swift:199` `reuse/reuse` — makeStrayFixture repeats the setup of makeFixture: a TemporaryDirectory, an EventLog on it, and writeBoard prefix to a task count. Only the task count and the event set differ. Extract the shared setup (directory, log, and board tasks for a count) into one helper that both makeFixture and makeStrayFixture call. Pass the task count as a parameter.