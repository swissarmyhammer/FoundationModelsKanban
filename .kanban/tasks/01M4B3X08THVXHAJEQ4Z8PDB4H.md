---
comments:
- actor: wballard
  id: 01m4benhe68ay0bck15y45s1ez
  text: |-
    Research done.
    - Event (Events/Event.swift) has `init(parsing:)` and `encodedLine()`; NodeLog (Events/Replay.swift) has `init(parsing:for:)` and skips blank and bad lines. Thus the event log reads lines and gives them to NodeLog.
    - LocalRef has `nodeType`, `localID`, and `init(parsing:)`. PatchNodeType is CaseIterable and has `pathSegment`. The directory of each node type comes from an exhaustive switch.
    - BoardKey has a text `description`. The multi-board lock sorts by this text.
    - flock locks belong to an open file description. Thus two `open` calls in one process conflict, and a test can use two file descriptors.
    - Plan: EventLog (paths, append, read, signatures), FileSignature, BoardLock (~Copyable, holds the descriptors, `consuming func unlock()`), EventLogError.
    - Validator dump is very large (12k lines). The Swift rules are: periphery dead code with --build-tests (a test is a caller), swiftlint no_magic_numbers, missing_docs, force rules, swift-format idioms (let in each bound case variable, literal empty collections, for loop not forEach).
  timestamp: 2026-10-07T15:10:47.238651+00:00
- actor: wballard
  id: 01m4bf1x7zzcq4ag2tnqhy2xy3
  text: |-
    Implementation landed (TDD: RED was a compile failure, "cannot find EventLog in scope"; then GREEN).
    - Events/EventLog.swift: `EventLog(repositoryAt:)`, `fileURL(for:)`, `lockFileURL`, `append(contentsOf:toLogOf:)`, `readLog(of:)` (gives a NodeLog; a missing file gives an empty log), `signature(of:)`, `nodeFileSignatures()`, `FileSignature`, `EventLogError`, `PatchNodeType.logDirectoryName`.
    - Events/BoardLock.swift: `lock()`, `lock(sortedByKey:)`, `lockOrder(of:)`, `BoardLock` (~Copyable, `consuming func unlock()`), private `LockedFile` class (its deinit closes the descriptor; thus a failure in a multi-board lock releases the locks that it already got).
    - The lock code is in its own file, because EventLog.swift was more than 400 lines.
    - An append refuses an event of a different node (`nodeMismatch`) and then writes nothing. When the last line of a file has no line break, the append adds one first.
    - `BoardLock.files` has `// periphery:ignore`, because no code reads it: it only keeps the files open.
    - The signature reads only the `id` of the last line (a private Decodable), so a line whose patch breaks a rule still gives its id.
    - The multi-board lock test checks `lockOrder(of:)` for the order, and checks with LOCK_NB on separate descriptors that each board is locked.
    - The default swiftlint config (not the gate) reports orphaned_doc_comment on the periphery marker, trailing_comma, and optional_data_string_conversion. The gate rules (no_magic_numbers, missing_docs, force rules) report nothing on the source files. Periphery: no unused code.
  timestamp: 2026-10-07T15:17:32.543547+00:00
- actor: wballard
  id: 01m4bf2043476bnhknn9md2sv7
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/Events/EventLog.swift, Sources/FoundationModelsKanban/Events/BoardLock.swift, Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift. `swift test --filter EventLogTests`: 16 tests passed. `swift test`: 293 tests in 17 suites passed, 0 compiler warnings. `periphery scan` (native build, --build-tests): no unused code.
    - next: /review
  timestamp: 2026-10-07T15:17:35.491075+00:00
- actor: wballard
  id: 01m4bf9e1q850r3svvsy0hbdjn
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (df75081). 3 files reviewed. 0 findings, 0 confirmed, 1 refuted. 4 files in .kanban/ not reviewed (.reviewignore).
    - next: none. The task is in done.
  timestamp: 2026-10-07T15:21:39.127965+00:00
- actor: wballard
  id: 01m4bf9kdz2544a57bk6wt817x
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 files (Events/EventLog.swift, Events/BoardLock.swift, EventLogTests.swift)
    - test: green — swift test, 293 passed, 0 warnings
    - commit: df75081
    - review: clean — 0 findings
  timestamp: 2026-10-07T15:21:44.639606+00:00
depends_on:
- 01M4B3WK197P3T3VZHX3JHWP3E
position_column: done
position_ordinal: '8e80'
title: 'Event log: append, lock, and file signatures'
---
## What
Read and write the log files of one board. The basis is plan.md §5.2, §5.4 step 5, and §5.6 (file signature).
- `Sources/FoundationModelsKanban/Events/EventLog.swift`: paths `.kanban/board.jsonl`, `columns/<slug>.jsonl`, `actors/<slug>.jsonl`, `tags/<slug>.jsonl`, `tasks/<ULID>.jsonl`, `comments/<ULID>.jsonl`.
- Append events to one node file. Make directories when needed. On the first write, make `.kanban/.gitattributes` (`*.jsonl merge=union`) and `.kanban/.gitignore` (`.lock`).
- Lock: exclusive `flock` on `.kanban/.lock`. A function that locks many boards in the sort order of the board key.
- `FileSignature`: size, modification time, id of the last event. Calculate it for one file; list all node files of a board with their signatures.

## Acceptance Criteria
- [x] An append adds one line for each event and does not change other lines.
- [x] Two processes that lock the same board run one after the other (test with two child processes or two file descriptors).
- [x] The signature changes after an append and does not change after a read.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift`, in a temporary directory.
- [x] Run `swift test --filter EventLogTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.