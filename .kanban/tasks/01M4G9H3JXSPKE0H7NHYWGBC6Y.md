---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4gsdstvzt323y5far2bhmgw
  text: |-
    Research and implementation notes:
    - `EventLog.lines(of:)` is the one split helper. `readLog(of:)` (replay, also the loader and the watcher reload path through `Loader`) and `signature(of:)` both use it. No other code reads log data with its own split.
    - `rg -n "isNewline" Sources` finds one more use: `BodyLines.content(of:)` in `Body/BodyLines.swift`. It works on the task body text, not on log data, so it is out of scope and did not change.
    - The old split accepted CRLF, because Swift keeps "\r\n" as one `Character` and `isNewline` is true for it. To keep this behavior, the new split ends a line only at the `Character` "\n" or the `Character` "\r\n" (new private constant `EventLog.lineBreaks`). A lone "\r", U+2028, U+2029 and U+0085 no longer end a line. Choice: keep CRLF lines readable, as the card says ("if the code accepts CRLF now").
    - RED: 4 new tests failed for the expected reason (replay skipped the pieces of the line, `lastEventID` was nil, the reloaded task kept only the first title). GREEN after the change.
    - Test helpers added in `EventLogTests`: `unicodeBreakText`, `crlfLineBreak`, `unicodeBreakTitleEvents()`, `appendToTaskLog(_:in:)`, `writeLogFile(_:of:in:)`. `appendEndsLastLine` now uses `writeLogFile` instead of its own copy of the directory and write calls.
  timestamp: 2026-10-09T16:55:00.187442+00:00
- actor: claude-code
  id: 01m4gsdvewf69nm4twmpkrpsy1
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/Events/EventLog.swift, Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift, Tests/FoundationModelsKanbanTests/Mutations/AddUpdateTaskTests.swift. `swift test`: 1082 tests in 76 suites passed, 0 failures; only the accepted SwiftPM "missing creator for mutated node" warning.
    - next: /review
  timestamp: 2026-10-09T16:55:01.852311+00:00
- actor: claude-code
  id: 01m4gsk5rmk3ep9hcm9g340ts9
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD — 1 finding — Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift:95 (duplication/duplication). The commit message cfbb39c is true for the diff. All acceptance and test items are met.
    - next: /implement the open finding
  timestamp: 2026-10-09T16:57:56.244845+00:00
- actor: claude-code
  id: 01m4gsk6w4k57vc45bjsvmwzjb
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 3 files
    - test: green — swift test, 1082 tests in 76 suites passed
    - commit: cfbb39c
    - review: findings — Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift:95
  timestamp: 2026-10-09T16:57:57.380291+00:00
- actor: claude-code
  id: 01m4gspr481wvmfp78dy7vd6qn
  text: 'Finding fix: `firstAndLastTitleEvents(lastTitle:)` now takes the title of step 2 as a parameter. The default is `"last"`, so the old callers did not change. `unicodeBreakTitleEvents()` is deleted. Its three callers (`readKeepsUnicodeBreaksInLine`, `readAcceptsCRLFLines`, `signatureReadsLastLineWithUnicodeBreaks`) now call `firstAndLastTitleEvents(lastTitle: Self.unicodeBreakText)`. The finding asked for a separate task for the edit to `firstAndLastTitleEvents`. The dispatcher said that no separate task is necessary, because one copy stays in the same file. Thus no new task. Note: the `files` edit tool with `replace_all` changed only the first of the three call sites. I edited the other two one at a time.'
  timestamp: 2026-10-09T16:59:53.352575+00:00
- actor: claude-code
  id: 01m4gspsh1d1de3ed5t1kytdgr
  text: |-
    ### implement — changed
    - evidence: 1 file — Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift. `swift test`: 1082 tests in 76 suites passed, 0 failures; only the accepted SwiftPM "missing creator for mutated node" warning. Finding EventLogTests.swift:95 duplication/duplication checked.
    - next: /review
  timestamp: 2026-10-09T16:59:54.785771+00:00
position_column: doing
position_ordinal: '80'
title: Split log lines only at \n so that U+2028 does not lose events
---
## What
`Sources/FoundationModelsKanban/Events/EventLog.swift:197-201` splits a log file with `split(whereSeparator: \.isNewline)`. `JSONEncoder` does not escape U+2028, U+2029 or U+0085, and `Character.isNewline` is true for them. Thus one JSON line becomes many pieces, replay skips each piece with a warning, and the event is lost after the next load. `signature(of:)` uses the same split, so `lastEventID` is also wrong.

- Split only on `"\n"` (and remove a `"\r"` at the end of a line, if the code accepts CRLF now). Use one helper for replay and for `signature(of:)`.
- Do a check for other `isNewline` splits on log data (`rg -n "isNewline" Sources`), for example in the watcher reload path.

## Acceptance Criteria
- [x] A task title and body with U+2028, U+2029 and U+0085 survive a commit plus a new load of the board, with the same text.
- [x] `signature(of:)` gives the correct last event id for such a file.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift`: regression test that writes an event whose value has the three characters, then replays the file and gets one event.
- [x] A round-trip test through `KanbanGraph`: `addTask` with such a title, then a new `KanbanGraph` on the same root reads the same title.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-09 11:56)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 3 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift:95` `duplication/duplication` — unicodeBreakTitleEvents repeats the body of firstAndLastTitleEvents. Both build the same two title events for steps 1 and 2, and they differ only by the literal title of step 2. A fix to one copy can drift out of sync with the other. Extract one helper that takes the title of step 2 as a parameter, and call it from both sites. Delete the copy the change added. Changing firstAndLastTitleEvents edits code outside this change, so report that edit as a separate task.
