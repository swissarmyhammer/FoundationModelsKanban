---
comments:
- actor: wballard
  id: 01m4brtes54m6nvbqn51dz64e9
  text: |-
    Research done. Discoveries:
    - No `LiveGraph` type exists yet. Plan: a `LiveGraph` struct in `Observe/LiveGraph.swift` that holds the `BoardLoader`, the `Graph`, the global event list, and the file signatures. A static `load(using:)` makes it; `apply(changedPaths:)` updates it.
    - `Graph ==` cannot compare an applied graph with a fresh load: slots are stable for the life of a graph, so a new file gets a slot at the end, and a removed file leaves an empty slot. Also, `Graph.update(with:)` can leave a stale `waiting` entry when a replaced node drops an unresolved edge (harmless: the later resolve finds no matching edge). The tests compare a slot-independent form: each node by ref, with each slot edge changed to the rank of its target ref.
    - The stage loop of `BoardLoader.load()` and of the apply is the same work. Plan: extract one shared stage helper in `BoardLoader`, so both use it. `EventMerge` becomes internal for the merge of the global list.
    - A changed path is mapped to its `LocalRef` with a new `EventLog.ref(ofFileAt:)` that reuses the private `ref(ofFile:type:)` of the directory listing.
    - The signature of a file is read before the file is read, so that a write between the two is seen as a change at the next check.
  timestamp: 2026-10-07T18:08:14.117156+00:00
- actor: wballard
  id: 01m4bs10sdkzwew98bafvfyp2g
  text: |-
    Implementation landed (TDD: the new suite failed first, because `LiveGraph` did not exist; the full-reload test was seen to fail with the reload switched off, then the switch was put back).
    - New `LiveGraph` (Observe/LiveGraph.swift): `load(using:)` reads the signatures first, then loads. `apply(changedPaths:)` maps the paths to refs, and does a full reload when `changed * fullReloadDivisor > recorded file count`. Otherwise it reads the changed files stage by stage into a copy of the graph, so that a read error changes nothing. Then it merges the kept and new events, records the new signatures, and returns the event ids that are new.
    - `BoardLoader.readStages(listingFilesWith:joiningInto:)` is the one shared stage loop. `load()` and the apply both call it. A file with no node removes its ref (a no-op in a fresh load).
    - `EventMerge` is now internal; its helpers are `private`.
    - `EventLog.ref(ofFileAt:)` reuses `ref(ofFile:type:)` and compares the board directory after `resolvingSymlinksInPath()` (`/var` and `/private/var`).
    - The watcher card ^4pvxwqn must filter paths by signature before it calls `apply`. `apply` does not skip a file with an equal signature.
  timestamp: 2026-10-07T18:11:49.165430+00:00
- actor: wballard
  id: 01m4bs12rmyq0h8nwg18t9pe2s
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/Observe/LiveGraph.swift (new), Sources/FoundationModelsKanban/Events/Loader.swift, Sources/FoundationModelsKanban/Events/EventLog.swift, Tests/FoundationModelsKanbanTests/Observe/LiveGraphApplyTests.swift (new). `swift test --filter LiveGraphApplyTests`: 7 tests passed. `swift test`: 566 tests in 35 suites passed, 0 compiler warnings. `periphery scan --retain-public -- --build-system native`: no unused code.
    - next: /review
  timestamp: 2026-10-07T18:11:51.188313+00:00
- actor: wballard
  id: 01m4bsaq936y6rbsanx744y5ep
  text: |-
    ### review — findings
    - evidence: review sha HEAD~1..HEAD; 1 finding (1 confirmed, 0 refuted) — Tests/FoundationModelsKanbanTests/Observe/LiveGraphApplyTests.swift:30 (reuse/reuse)
    - next: Remove the duplicate `write` helper. Use one shared test helper with `LoaderTests.append`. Then review again.
  timestamp: 2026-10-07T18:17:07.107092+00:00
- actor: wballard
  id: 01m4bsazb98rf3mkp60zza5qd8
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 4 files (Observe/LiveGraph.swift, Events/Loader.swift, Events/EventLog.swift, LiveGraphApplyTests.swift)
    - test: green — swift test, 566 passed, 0 warnings
    - commit: 7d61f08
    - review: findings — Tests/FoundationModelsKanbanTests/Observe/LiveGraphApplyTests.swift:30
  timestamp: 2026-10-07T18:17:15.369556+00:00
- actor: wballard
  id: 01m4bsecc4f92jesgwh79jpbet
  text: |-
    Fix of the reuse/reuse finding. The same cause is removed from all of the fixture section of LiveGraphApplyTests.swift.
    - `LoaderTests.append` now gives the `Event` (`@discardableResult`). The existing callers do not change. The `write` copy is deleted.
    - `ReplayTests.titlePatch(setting:of:)` gets an optional `ref` (the default is the test task). `writeTitle` now uses it with `LoaderTests.append`, so it does not make its own title patch. `writeTitle` is `@discardableResult`, so the `_ =` uses are gone.
    - The local `writeTask(_:dependingOn:atStep:in:)` was a near-copy of `LoaderTests.writeTask`. It is deleted, and the tests call `LoaderTests.writeTask`. That task also has a remote `dependsOn` edge, so the edge checks now use `dependsOn.first` (the same form as `LoaderTests.joinGivesTargetSlots`).
    - `.unresolved(.local(target))` is changed to the existing `ReplayTests.edge(to:)`.
    - Kept: `writeBoard` (a filter on `LoaderTests.writeBoard`), `load` (makes a `LiveGraph`; no other helper does), `canonicalNodes`, `expectEqualToFreshLoad`, and `task(_:in:)` (it uses `LoaderTests.node`). ReadinessFixture, QueryFixture, TaskQueryFixture, and EventLogTests have no helper that does this work.
    - The dump of the validator rules is 750K characters, so I used the rule list that the caller gave.
  timestamp: 2026-10-07T18:19:07.012752+00:00
- actor: wballard
  id: 01m4bsedxcadpzkrnct868f7ma
  text: |-
    ### implement — changed
    - evidence: 3 files — Tests/FoundationModelsKanbanTests/Observe/LiveGraphApplyTests.swift, Tests/FoundationModelsKanbanTests/Events/LoaderTests.swift, Tests/FoundationModelsKanbanTests/Events/ReplayTests.swift. `swift test`: 566 tests in 35 suites passed, 0 compiler warnings.
    - next: /review
  timestamp: 2026-10-07T18:19:08.588939+00:00
- actor: wballard
  id: 01m4bsgx8jx8a84dps6599y9pn
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (3d06cf0). 3 files reviewed, 7 validator runs, 0 findings, 0 failed. All earlier review items are checked.
    - next: none. The task is in done.
  timestamp: 2026-10-07T18:20:29.842089+00:00
- actor: wballard
  id: 01m4bsh387xhhsqmpa5pdq9hew
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 3 files (LiveGraphApplyTests.swift, LoaderTests.swift, ReplayTests.swift); 1/1 findings checked
    - test: green — swift test, 566 passed, 0 warnings
    - commit: 3d06cf0
    - review: clean — 0 findings
  timestamp: 2026-10-07T18:20:35.975831+00:00
depends_on:
- 01M4B3XHRVFA2YDCJC76MAFQR5
- 01M4B3X08THVXHAJEQ4Z8PDB4H
position_column: done
position_ordinal: 9a80
title: 'Live graph: apply changed files to the graph'
---
## What
Update a loaded `Graph` from a list of changed log files. The commit check and the watcher both use this. The basis is plan.md §5.6 (Apply a batch, Large changes, A line that does not parse).
- `Sources/FoundationModelsKanban/Observe/LiveGraph.swift`: `apply(changedPaths:)` on a board graph, with the loader work queue and the stage order (board, actors, columns, tags, tasks, comments).
  - Changed file: read and fold the node again from the start; replace the state in its slot.
  - New file: make a new slot; resolve waiting edges to it.
  - Removed file: remove the node; edges to it become unresolved.
- After the stages: join again, update the global event list (add new event ids, remove gone ids), and record the new file signatures. Return the new event ids, so that a caller can make `Change` values.
- More than half of the files of the board changed: do a full reload with the loader.

## Acceptance Criteria
- [x] After each case (changed, new, removed file, many files), the graph equals a fresh load of the same files.
- [x] A new file resolves an edge that pointed to it; a removed file makes the edge unresolved.
- [x] A line that does not parse is skipped, and the other lines still apply.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Observe/LiveGraphApplyTests.swift`: change files on disk directly, call `apply`, compare with a fresh load.
- [x] Run `swift test --filter LiveGraphApplyTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.

## Review Findings (2026-10-07 13:12)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 4 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Tests/FoundationModelsKanbanTests/Observe/LiveGraphApplyTests.swift:30` `reuse/reuse` — The `write` function reimplements functionality already present in `LoaderTests.append` with only a return-value difference. A near-match should be extended or generalized rather than duplicated across test files. Extend `LoaderTests.append` to return the Event (existing callers can ignore it), or extract a shared test helper that both test suites can reuse. This keeps one canonical implementation.
