---
comments:
- actor: wballard
  id: 01m873ydaskapke6yz50jbv5v6
  text: 'Research done. The public API docs of this package are only in README.md. ARCHITECTURE.md has only the rule of no backward compatibility, and there is no DocC catalog. The README sections are numbered 1 to 6. The new section goes after 5 as section 6, and the layout of .kanban/ becomes section 7. ReadmeExamplesTests runs the same code as each README example. It does not compile the Swift blocks from the README. Its test eachSwiftDocumentIsRun compares the GraphQL strings of the Swift blocks with a fixed set, so the new Swift blocks must have no multi-line string. The stream tests (BoardFolderChangesTests) have helpers that the new tests can use: waitsForChange(of:ofTask:at:) and a writer on a second host (KanbanGraphTests.makeGraph(at:)). Note: a sah kanban write op from the shell prints its result but does not exit; send its output to a file, not to a pipe.'
  timestamp: 2026-11-24T15:49:13.177467+00:00
- actor: wballard
  id: 01m874c8kg31rb47sp42ptqr9e
  text: 'Implementation done. README.md has the new section ''### 6. Read and watch a folder with no session'' (the layout of .kanban/ is now section 7). It shows readBoard(inFolder:) with .noBoard and .board(snapshot), the stamp check with boardStamp(ofFolder:), and boardChanges(inFolder:) with the four kinds and follower.cancel(). It states the limits: no session, no lock, and no write for the read and the stamp; the stream writes only to merge iCloud conflict versions; the one-second file-time limit of the stamp; the caller must cancel the task that reads the stream. ReadmeExamplesTests has four new tests (no board, same stamp after a read, a new task shows in the stream, a cancel ends the loop). Each test runs the README code and checks that the README holds the call. RED: the four tests failed only on the README check. The new README Swift blocks were type-checked one time in a temporary test file, then the file was removed. Double-check: the double-check agent could not reach this repo (its tools are bound to KanbanViewKit); a general-purpose verifier gave PASS. Its one note: in the cancel test, #expect(ended) is always true, so the test fails only when the loop does not end before the time limit of FolderEventWait; BoardFolderChangesTests already tests that the watcher stops. The box ''The two sessions got the API names and the commits'' stays open: the coordinator sends the API names after the commit.'
  timestamp: 2026-11-24T15:56:47.088581+00:00
- actor: wballard
  id: 01m874cm54yyjqt2ethxeyx0yk
  text: |-
    ### implement — changed
    - evidence: README.md, Tests/FoundationModelsKanbanTests/ReadmeExamplesTests.swift; swift test: 1989 tests in 172 suites passed (only the accepted mlx-swift_Cmlx.bundle warning); ReadmeExamplesTests + DocumentationTests: 19 tests passed
    - next: /review. The coordinator sends the API names after the commit, and then checks the last box.
  timestamp: 2026-11-24T15:56:58.916826+00:00
- actor: wballard
  id: 01m874ka9n7zczc9p9nj08zbmk
  text: |-
    ### test — green
    - evidence: swift test at package root, 1989 tests in 172 suites passed, 0 failed, 0 skipped; only the accepted mlx-swift_Cmlx.bundle warning
    - next: review
  timestamp: 2026-11-24T16:00:38.197631+00:00
- actor: wballard
  id: 01m874ksrjr22mxp8q3tj6v5hj
  text: |-
    ### commit - changed
    - evidence: README section 6 documents readBoard(inFolder:), boardStamp(ofFolder:) and boardChanges(inFolder:) with one example and their limits. ReadmeExamplesTests runs the same code (4 tests).
    - next: none. The commit is local. It is not pushed.
  timestamp: 2026-11-24T16:00:54.034363+00:00
- actor: wballard
  id: 01m874q24kpfw5p57rk3y3cy21
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (147c4ed) — 0 findings, 0 confirmed, 1 refuted, 7 attempted, 0 failed. Reviewed: Tests/FoundationModelsKanbanTests/ReadmeExamplesTests.swift. Not reviewed: README.md (no validator matches), 2 .kanban/ files (.reviewignore).
    - next: the coordinator sends the API names and the commits to the two sessions, then moves the task to done.
  timestamp: 2026-11-24T16:02:40.915775+00:00
- actor: wballard
  id: 01m874r9b3z2pq3p16e6y2aw9j
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — README.md section 6, ReadmeExamplesTests (4 tests)
    - test: green — swift test, 1989 passed
    - commit: 147c4ed
    - review: clean — 0 findings
    - API names and commits sent to foundationmodelsrouter-09 and testudoapp
  timestamp: 2026-11-24T16:03:21.059076+00:00
depends_on:
- 01M86WE7KQXHJCAX08PMRGYRKR
- 01M86WEGWCS6X5RW20HFKQB54D
- 01M86WENX96J2YGHMBMKPXEWM2
- 01M86WEWDS64Z68K378JCYR7MK
position_column: done
position_ordinal: ffd280
title: Document the read, the stamp, and the change stream of a folder, and send the API names
---
## Problem
The read, the stamp, and the change stream of a folder with no session are new public API (brief `/Users/wballard/github/swissarmyhammer/.briefs/FoundationModelsKanban-spotlight-board-reads-2026-11-24.md`). The README tells only the session read (section "1. Open a board in a folder") and the session subscription (section "5. Watch changes"). TestudoApp and FoundationModelsACPAgent need the names, and they need the commit.

## What
- In `README.md`, add the section "Read and watch a folder with no session" after "5. Watch changes". Show `KanbanHost.shared.readBoard(inFolder:)` with `.noBoard` and `.board(snapshot)`, `KanbanHost.shared.boardStamp(ofFolder:)`, and `KanbanHost.shared.boardChanges(inFolder:)` with the four cases of `BoardFolderChange`. Tell that the read and the stamp write nothing, and that the stream writes only the merge of iCloud conflict versions.
- Add each new example to `Tests/FoundationModelsKanbanTests/ReadmeExamplesTests.swift`, the same as the examples that are there, so that the README stays correct.
- Write in ASD-STE100 Simplified Technical English, the same as the README.
- After the commit, send one message to the FoundationModelsACPAgent session and one to the TestudoApp session. Give the public names (`KanbanHost.readBoard(inFolder:)`, `BoardRead`, `BoardSnapshot` and its nested types, `BoardStamp`, `KanbanHost.boardStamp(ofFolder:)`, `KanbanHost.boardChanges(inFolder:)`, `BoardFolderChange`) and the commit hash of each card.

## Acceptance Criteria
- [x] The README has the new section with code that compiles.
- [x] `ReadmeExamplesTests` runs each new example and passes.
- [x] `DocumentationTests` passes.
- [x] The two sessions got the API names and the commits (foundationmodelsrouter-09 and testudoapp, 147c4ed).

## Tests (write them first)
- [x] Add a test in `Tests/FoundationModelsKanbanTests/ReadmeExamplesTests.swift` for each new README example: a folder with no `.kanban/` folder gives "no board"; the stamp is the same after a read with no change; a new task shows in the stream.
- [x] `swift test` passes. Run the headless root `swift test` one time only.

## Workflow
- Use `/tdd`: write the failing tests first, then make them pass.
- Run `/double-check` before review.

## Note
This work is for TestudoApp D214. The answer (the API names and the commit) goes to the FoundationModelsACPAgent session and to the TestudoApp session. #testudo