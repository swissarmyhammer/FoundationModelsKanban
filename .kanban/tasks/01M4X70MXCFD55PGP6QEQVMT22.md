---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4y0fv24xfx3yrkff7ks2n06
  text: |-
    Research done.
    - EventStamp (S/Tool/Commit.swift) mints txn from the source, then each event id is max(minted, last.successor). The floor is only the txn of this call. Nothing reads the ids of the log.
    - LiveGraph (S/Observe/LiveGraph.swift) keeps `events` sorted by id. install() runs for each commit (adopt) and each watcher/commit-check reload (reload). A full reload replaces self via load().
    - CommitSession.runReading makes `EventStamp(actingAs:mintingFrom:)` per run. Related boards get the stamp of the main working copy: Schema.relatedTarget -> session.makeWorkingCopy(stampedBy: work.stamp), then WorkingCopy.runField(on:) sets field.stamp = stamp. So a floor set when the related working copy is made is lost; the floor must be raised again in runField(on:).
    - Plan: LiveGraph.largestEventID (never decreases; set on load, install, full reload). EventStamp init takes a floor for the txn; EventStamp gets a mutating continue-after-floor. WorkingCopy keeps the floor of its board and raises the stamp in init and in runField(on:).
  timestamp: 2026-10-14T20:08:34.628416+00:00
- actor: claude-code
  id: 01m4y18bcmd3qagjkep93g3ndt
  text: |-
    Implementation landed (TDD: each new test failed first for the id-order reason, then passed).
    - LiveGraph.largestEventID: set on load, raised in install() (each commit and each watcher/commit-check reload), kept across a full reload. It never goes down.
    - EventStamp.init(actingAs:mintingFrom:after:): the txn is after the largest id. EventStamp.advance(past:) raises the floor of later event ids.
    - WorkingCopy.init(...after:) and runField(on:) advance the stamp past the largest id of the board that the field writes (related boards too).
    - CommitSession.makeStamp (private) and makeWorkingCopy pass live.largestEventID. KanbanGraph.eventBoard passes it too.
    - New tests: Tests/FoundationModelsKanbanTests/Tool/EventIDOrderTests.swift (same millisecond, clock moves back, undo after target, related-board field, watcher apply of a union merge then a call that commits in one run). MergeTests: extracted unionMerge(_:into:) so the new test reuses the union-merge loop.
    - What did not work: a ScriptedULIDSource with an exact id count crashed (index out of range) because a GraphQL call takes more ids than txn + events. A settable TestClock source replaced it.
    - swift test: 1228 tests in 91 suites passed; only the accepted mlx "missing creator" warning.
  timestamp: 2026-10-14T20:21:57.780063+00:00
- actor: claude-code
  id: 01m4y18dtczpjdtenmjazccpd8
  text: |-
    ### implement — changed
    - evidence: 6 files — Sources/FoundationModelsKanban/Observe/LiveGraph.swift, Sources/FoundationModelsKanban/Tool/Commit.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Tests/FoundationModelsKanbanTests/Tool/EventIDOrderTests.swift (new), Tests/FoundationModelsKanbanTests/Design/MergeTests.swift, Tests/FoundationModelsKanbanTests/GraphQL/QueryFixture.swift; swift test 1228/1228 pass
    - next: /review
  timestamp: 2026-10-14T20:22:00.268295+00:00
- actor: claude-code
  id: 01m4y1sfyejmdskyqm1ejw0cvg
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 6 files
    - test: green — swift test, 1228 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: f452c4c
    - review: findings — Tests/FoundationModelsKanbanTests/Tool/EventIDOrderTests.swift:241
  timestamp: 2026-10-14T20:31:19.502502+00:00
- actor: claude-code
  id: 01m4y238f7cksmn553hqhagcbn
  text: |-
    Review finding EventIDOrderTests.swift:241 reuse/reuse is fixed (TDD: the two new tests did not compile first because the API was missing, then passed).
    - SequenceNumberGenerator now has init(startingAt:step:) with wrapping add, and the static `descending` sequence (UInt64.max, then one smaller each time).
    - FixedULIDSource.init(at:generator:) takes the generator; the default sequence goes up as before.
    - DescendingNumberGenerator and DescendingULIDSource are deleted. DescendingULIDSource was a near-copy of FixedULIDSource too, so the same cause is removed from the whole file. EventIDOrderTests.descendingIDs replaces the two identical call-site lines.
    - New tests in ShortIDTests: the descending source gives ULIDs in reverse sort order, and the descending sequence starts at UInt64.max and goes down by one.
    - swift test: 1230 tests in 91 suites passed; the only compiler warning is the accepted mlx "missing creator" warning.
  timestamp: 2026-10-14T20:36:39.527600+00:00
- actor: claude-code
  id: 01m4y23a5j92a1dy5atcf9ff97
  text: |-
    ### implement — changed
    - evidence: 3 files — Sources/FoundationModelsKanban/Identity/ULIDSource.swift, Tests/FoundationModelsKanbanTests/Tool/EventIDOrderTests.swift, Tests/FoundationModelsKanbanTests/Identity/ShortIDTests.swift; swift test 1230/1230 pass
    - next: /review
  timestamp: 2026-10-14T20:36:41.266095+00:00
- actor: claude-code
  id: 01m4y2errpy78159yc9d3cff21
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 3 files (1 finding fixed, 2 new tests)
    - test: green — swift test, 1230 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: 1bb8632
    - review: clean — none
  timestamp: 2026-10-14T20:42:56.662766+00:00
position_column: done
position_ordinal: e780
title: Make event ids increase from one call to the next
---
## What
divergence.md S3 (§7, §11 bugs) and the M6 final decision in §16. This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Event ids are in order inside one call, but not from one call to the next. Each call starts from a new random ULID (S/Tool/Commit.swift:31-37,62-66). Two calls in the same millisecond, or a clock that moves back, can put a later `set` before an earlier one. They can also put an undo before its target.

Why this is important now: each worktree has its own board on its own branch, and boards join when the branches merge (union merge of the log lines). The replay order after a union merge is the order of the event ids. Thus the merge of worktree boards needs ids that increase.

Change: start each call after the largest event id in the log of each board that the call writes (keep the largest id in memory, and update it on each commit and on each watcher reload). The first id of a call is greater than every id that the board already has, also when the clock moves back or two calls run in the same millisecond.

## Acceptance Criteria
- [ ] Two calls in the same millisecond give ids in call order.
- [ ] When the clock moves back, the next call still gives ids greater than the largest id in the log.
- [ ] An undo always has an id greater than its target.
- [ ] Ids from events that the watcher loads (from another process or a merge) also count as the largest id.

## Tests
- [ ] A test with a fixed clock (same millisecond for two calls) and a clock that moves back.
- [ ] A test that an undo id is greater than the target id.
- [ ] A test with a union merge of two board copies, then a new call: its ids are greater than all merged ids.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-14 15:25)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 6 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsKanbanTests/Tool/EventIDOrderTests.swift:241` `reuse/reuse` — DescendingNumberGenerator is a near-copy of the existing SequenceNumberGenerator. Two generators that differ only in direction duplicate the same RandomNumberGenerator logic. Extend the existing generator with a direction or start parameter instead. Reuse SequenceNumberGenerator and give it a descending option, or pass the starting value and step as parameters. Delete DescendingNumberGenerator.
