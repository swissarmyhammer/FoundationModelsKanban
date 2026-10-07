---
depends_on:
- 01M4B3XHRVFA2YDCJC76MAFQR5
position_column: todo
position_ordinal: '9080'
title: 'Dependencies at read time: kanban:// URL markers'
---
## What
Calculate the dependencies of a task. The basis is plan.md §6.1 (Dependencies use the same model).
- `Sources/FoundationModelsKanban/Derived/DependencyMarkers.swift`: find each full `kanban://<board-key>/task/<ULID>` URL in a body. Only full task URLs are markers; short ids and other node URLs are plain text.
- Resolve: a marker whose key is the current key of the board resolves in this board (to a slot); all others are cross-board refs.
- `task.dependsOn` = resolve(dependsOn edges) ∪ resolve(markers in the current body), with no duplicates.
- Helper to remove a URL from a body (the `updateTask(dependsOn:)` mutation uses it later).

## Acceptance Criteria
- [ ] A task URL of this board in the body gives a same-board dependency.
- [ ] A task URL of a different board gives a cross-board dependency.
- [ ] A short id, a tag URL, or a column URL in the body gives no dependency.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Derived/DependencyMarkersTests.swift`.
- [ ] Run `swift test --filter DependencyMarkersTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.