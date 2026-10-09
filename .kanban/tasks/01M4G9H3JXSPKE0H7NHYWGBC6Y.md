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