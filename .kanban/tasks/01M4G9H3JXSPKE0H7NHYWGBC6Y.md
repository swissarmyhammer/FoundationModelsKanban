---
assignees:
- claude-code
position_column: todo
position_ordinal: '8280'
title: Split log lines only at \n so that U+2028 does not lose events
---
## What
`Sources/FoundationModelsKanban/Events/EventLog.swift:197-201` splits a log file with `split(whereSeparator: \.isNewline)`. `JSONEncoder` does not escape U+2028, U+2029 or U+0085, and `Character.isNewline` is true for them. Thus one JSON line becomes many pieces, replay skips each piece with a warning, and the event is lost after the next load. `signature(of:)` uses the same split, so `lastEventID` is also wrong.

- Split only on `"\n"` (and remove a `"\r"` at the end of a line, if the code accepts CRLF now). Use one helper for replay and for `signature(of:)`.
- Do a check for other `isNewline` splits on log data (`rg -n "isNewline" Sources`), for example in the watcher reload path.

## Acceptance Criteria
- [ ] A task title and body with U+2028, U+2029 and U+0085 survive a commit plus a new load of the board, with the same text.
- [ ] `signature(of:)` gives the correct last event id for such a file.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift`: regression test that writes an event whose value has the three characters, then replays the file and gets one event.
- [ ] A round-trip test through `KanbanGraph`: `addTask` with such a title, then a new `KanbanGraph` on the same root reads the same title.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.