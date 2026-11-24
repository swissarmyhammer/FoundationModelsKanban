---
depends_on:
- 01M86WE7KQXHJCAX08PMRGYRKR
- 01M86WEGWCS6X5RW20HFKQB54D
- 01M86WENX96J2YGHMBMKPXEWM2
- 01M86WEWDS64Z68K378JCYR7MK
position_column: todo
position_ordinal: '8480'
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
- [ ] The README has the new section with code that compiles.
- [ ] `ReadmeExamplesTests` runs each new example and passes.
- [ ] `DocumentationTests` passes.
- [ ] The two sessions got the API names and the commits.

## Tests (write them first)
- [ ] Add a test in `Tests/FoundationModelsKanbanTests/ReadmeExamplesTests.swift` for each new README example: a folder with no `.kanban/` folder gives "no board"; the stamp is the same after a read with no change; a new task shows in the stream.
- [ ] `swift test` passes. Run the headless root `swift test` one time only.

## Workflow
- Use `/tdd`: write the failing tests first, then make them pass.
- Run `/double-check` before review.

## Note
This work is for TestudoApp D214. The answer (the API names and the commit) goes to the FoundationModelsACPAgent session and to the TestudoApp session. #testudo