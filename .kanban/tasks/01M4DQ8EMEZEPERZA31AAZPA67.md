---
position_column: todo
position_ordinal: b580
title: 'Flaky: EventLogTests held-lock wait exceeds deadline tolerance under load'
---
## What
In a full root `swift test --skip-build` run on 2026-10-08 (during ^7j3aar6), the test "The wait for a released lock ends at its deadline while a different descriptor holds the lock" in `Tests/FoundationModelsKanbanTests/Events/EventLogTests.swift` failed:

`Expectation failed: waited < Self.heldLockWaitLimit + Self.deadlineTolerance` — `waited` was 3.21 s, the limit is 2.3 s (300 ms wait limit + 2 s tolerance).

The next two full runs passed with no code change. The failure is a timing flake under parallel load. No source change of ^7j3aar6 touches the root package.

## Acceptance Criteria
- [ ] Find why the bounded wait of `isLockReleased(of:within:)` can take more than 3 s under a parallel full-suite run.
- [ ] The test does not fail under a full parallel `swift test` run, and it still fails when the wait does not end at its deadline.

## Tests
- [ ] Run the full root `swift test` 5 times; expect all pass.