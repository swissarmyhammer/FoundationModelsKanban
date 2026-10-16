---
assignees:
- claude-code
position_column: todo
position_ordinal: b980
title: Stop the engine of a replaced repo from reading the files of the new repo at the same path
---
## What
Found during ^0nkvw6d. This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

When a user moves a repo away and makes a new repo at the same path, the host loads a new engine for the new folder identity. The old engine stays in `KanbanHost.engines` until the host closes. Its `root` is still the old path, and its file watcher (FSEvents, by path) stays on that path. Thus the old engine can apply the log files of the new repo to its old live graph, and its commit path writes to `<path>/.kanban/` of the new repo when a different view still holds the old engine.

^0nkvw6d makes each session view replace the engine of the path, and drop the changes of the old engine (`BoardChanges.identity`). The old engine itself still runs.

## Change
- Decide what the host does with the engine of a folder identity that is not at its path any more: close it and remove it from the table, or move its root to the new path of the old folder.
- A view that still holds the old engine must not write to the new repo.

## Acceptance Criteria
- [ ] After a repo is replaced at the same path, no engine applies or writes the files of the new repo except the engine of the new folder identity.

## Tests
- [ ] A test replaces the repo of a path ref, writes to the new board, and checks that the old engine does not apply the new log files.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.