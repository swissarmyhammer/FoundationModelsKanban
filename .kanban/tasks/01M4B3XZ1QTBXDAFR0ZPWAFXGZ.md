---
comments:
- actor: wballard
  id: 01m4bfwgsf940vvd8374asc44q
  text: |-
    Research done. Findings:
    - Graph edges are `EdgeTarget` (`.slot(Int)` or `.unresolved(StoredRef)`). A cross-board ref stays `.unresolved(.remote(NodeURI))`. A same-board ref with no live node stays `.unresolved(.local(ref))`.
    - `StoredRef(uri:inBoard:)` already gives local or remote from a URI and the current key. `NodeURI(parsing:)` accepts a case-insensitive scheme and a lowercase ULID.
    - `TaskNode.dependsOn` holds the resolved edges after `Graph.update(with:)`. The graph `resolve` is private and mutating, so the read-time resolve of a marker uses `slot(for:)` and `node(at:)`.
    - `OrderedSet` (swift-collections) is in the target, for a union with no duplicates.
    - Plan: `Derived/DependencyMarkers.swift` with `DependencyMarker` (uri + range), `DependencyMarkers.all(in:)`, `DependencyMarkers.removing(markersOf:from:)`, and `Graph.dependencies(of:inBoard:)`.
  timestamp: 2026-10-07T15:32:04.527891+00:00
- actor: wballard
  id: 01m4bg28tbjsf3z4hc9a6vd59j
  text: |-
    Implementation landed (TDD: RED was a compile failure because `DependencyMarkers` did not exist; GREEN 11/11).
    - `DependencyMarkers.all(in:)`: finds `kanban://` (case-insensitive) text. The URL ends at whitespace or a Markdown or quote delimiter. Sentence punctuation at the end is not part of the URL. The text must parse as a `NodeURI` to a task.
    - `DependencyMarkers.removing(markersOf:from:)`: uses the Rust `remove_tag` tidy rules. A line with no marker stays the same, byte for byte. An edited line loses its trailing whitespace. An emptied last line with no line break also removes the line break before it. CRLF is kept, because `lineRange(for:)` keeps the line break of each line.
    - `Graph.dependencies(of:inBoard:)`: the edges first, then the markers, with no duplicates (`OrderedSet`). A same-board marker gives `.slot` when the task is live, else `.unresolved(.local)`. A marker of a different board gives `.unresolved(.remote)`.
    - Known limit: a URL inside a Markdown code block is still a marker. The plan does not tell to skip code blocks.
    - Periphery reports nothing in the new files. It reports 4 assign-only properties in the existing `GraphQL/Errors.swift`, which this task did not change.
  timestamp: 2026-10-07T15:35:12.971882+00:00
- actor: wballard
  id: 01m4bg2ahv5bjv67ca39yys91x
  text: |-
    ### implement — changed
    - evidence: 2 files — Sources/FoundationModelsKanban/Derived/DependencyMarkers.swift, Tests/FoundationModelsKanbanTests/Derived/DependencyMarkersTests.swift. `swift test --filter DependencyMarkersTests`: 11 tests in 1 suite pass. `swift test`: 313 tests in 19 suites pass, with no compiler warnings. `periphery scan --retain-public -- --build-system native`: no reports in the new files.
    - next: /review
  timestamp: 2026-10-07T15:35:14.747289+00:00
depends_on:
- 01M4B3XHRVFA2YDCJC76MAFQR5
position_column: doing
position_ordinal: '80'
title: 'Dependencies at read time: kanban:// URL markers'
---
## What
Calculate the dependencies of a task. The basis is plan.md §6.1 (Dependencies use the same model).
- `Sources/FoundationModelsKanban/Derived/DependencyMarkers.swift`: find each full `kanban://<board-key>/task/<ULID>` URL in a body. Only full task URLs are markers; short ids and other node URLs are plain text.
- Resolve: a marker whose key is the current key of the board resolves in this board (to a slot); all others are cross-board refs.
- `task.dependsOn` = resolve(dependsOn edges) ∪ resolve(markers in the current body), with no duplicates.
- Helper to remove a URL from a body (the `updateTask(dependsOn:)` mutation uses it later).

## Acceptance Criteria
- [x] A task URL of this board in the body gives a same-board dependency.
- [x] A task URL of a different board gives a cross-board dependency.
- [x] A short id, a tag URL, or a column URL in the body gives no dependency.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/Derived/DependencyMarkersTests.swift`.
- [x] Run `swift test --filter DependencyMarkersTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.