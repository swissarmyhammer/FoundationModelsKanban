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
depends_on:
- 01M4B3XHRVFA2YDCJC76MAFQR5
- 01M4B3X08THVXHAJEQ4Z8PDB4H
position_column: doing
position_ordinal: '8180'
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