---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4y2pd2t8v48n4azgzt5r1g3
  text: |-
    Research done.
    - NodeLog (Events/Replay.swift) reads each line with Event(parsing:). PatchInput.init(from:) (Events/PatchInput.swift) throws on one bad value: a ref property that is not text (refMismatch), a bad ref text (invalidRef), a time property in set (timeProperty), a bad add/remove member, a delete or edit of the wrong shape. The throw drops the full line.
    - Event(parsing:) must stay strict: EventTests asserts the strict errors, and the GraphQL patch mutation decodes PatchInput too.
    - Plan: add a PatchValuePolicy (refuse | skip). The default is refuse. Replay decodes with skip: each set value, each add/remove member, each unset name, delete, and edit decode one at a time; a bad one is logged and left out. The envelope (id, txn, ops, at, actor, boards, undoes, query, node, type) stays strict, so a bad envelope still drops the line.
    - CodingUserInfoKey(rawValue:) is failable on this SDK, so the policy goes through a @TaskLocal (a computed var), not through decoder.userInfo.
  timestamp: 2026-10-14T20:47:06.842697+00:00
- actor: claude-code
  id: 01m4y34x9dz9ewdp4hb1b3asy6
  text: |-
    Implementation landed (TDD: 5 of 6 new tests failed first, the bad-envelope test passed first because it pins the behavior that stays).
    - PatchInput.swift: new PatchValuePolicy (refuse | skip, @TaskLocal current, default refuse). PatchInput.init(from:) reads each value by itself through a private PartReader: each set value (with the time-property and ref-kind check), each unset name, each add/remove member, delete, and edit. With skip, a bad value is logged ("Replay skips a patch value that does not decode", metadata node/value/error) and left out. New StoredRef.init(ofProperty:from:) is shared by PatchValue and the member read.
    - Event.swift: Event(parsing:policy:) with default .refuse, so EventTests and the GraphQL patch mutation keep the strict errors.
    - Replay.swift: ParsedLine uses Event(parsing: text, policy: .skip). Docs updated.
    - Tests: Tests/FoundationModelsKanbanTests/Events/ReplayBadValueTests.swift (.watcherBudget, TemporaryDirectory fixtures, BoardLoader).
    Dead end: closures written as `() throws(EventError) in ...` passed to the generic `() throws -> Value?` reader crash swift-frontend in IRGen (Xcode toolchain for macOS 27). Plain `throws` closures with `throw EventError.x` compile.
    Strict-mode note: a non-string unset entry now throws EventError.malformed, and a non-list add/remove value throws refMismatch (before, both were a DecodingError mapped to malformed).
  timestamp: 2026-10-14T20:55:02.189525+00:00
- actor: claude-code
  id: 01m4y34z217h9mgmbgnmvcrz0d
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/Events/PatchInput.swift, Sources/FoundationModelsKanban/Events/Event.swift, Sources/FoundationModelsKanban/Events/Replay.swift, Tests/FoundationModelsKanbanTests/Events/ReplayBadValueTests.swift (new). swift test: 1236 tests in 92 suites passed; only the accepted SwiftPM "missing creator" warning.
    - next: /review
  timestamp: 2026-10-14T20:55:04.001967+00:00
- actor: claude-code
  id: 01m4y3jxcv6p5yrn6ecpcwa0qn
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 4 files
    - test: green — swift test, 1236 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: 164c743
    - review: clean — none
  timestamp: 2026-10-14T21:02:41.051219+00:00
position_column: done
position_ordinal: e880
title: Make replay skip only a bad value, not the whole event line
---
## What
divergence.md S4 (§7, §11 bugs). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

One bad property makes replay drop the whole line. A value with the wrong kind makes the decode throw, and S/Events/Replay.swift:143-150 drops the full line. The plan says that replay never refuses a log, and that a schema change needs no upgrade step.

Change: decode each property of an event line by itself. When one value has the wrong kind (or cannot decode), skip only that value (log a warning), and apply all the other properties of the line. Drop the full line only when the envelope itself (for example the event id or the node ref) cannot decode.

## Acceptance Criteria
- [x] A line with one bad value applies all its other values.
- [x] A line with an envelope that cannot decode is dropped, as now.
- [x] The unknown and new properties tests still pass.

## Tests
- [x] A `set` line with a good `title` and a `column` that is a number: the title applies, the column does not change.
- [x] A line with two bad values and one good value: the good value applies.
- [x] A line with a bad envelope: the line is dropped and the load continues.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.