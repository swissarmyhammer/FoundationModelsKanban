---
assignees:
- claude-code
position_column: todo
position_ordinal: 8b80
title: Make replay skip only a bad value, not the whole event line
---
## What
divergence.md S4 (§7, §11 bugs). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

One bad property makes replay drop the whole line. A value with the wrong kind makes the decode throw, and S/Events/Replay.swift:143-150 drops the full line. The plan says that replay never refuses a log, and that a schema change needs no upgrade step.

Change: decode each property of an event line by itself. When one value has the wrong kind (or cannot decode), skip only that value (log a warning), and apply all the other properties of the line. Drop the full line only when the envelope itself (for example the event id or the node ref) cannot decode.

## Acceptance Criteria
- [ ] A line with one bad value applies all its other values.
- [ ] A line with an envelope that cannot decode is dropped, as now.
- [ ] The unknown and new properties tests still pass.

## Tests
- [ ] A `set` line with a good `title` and a `column` that is a number: the title applies, the column does not change.
- [ ] A line with two bad values and one good value: the good value applies.
- [ ] A line with a bad envelope: the line is dropped and the load continues.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.