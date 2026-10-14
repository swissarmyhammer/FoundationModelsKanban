---
assignees:
- claude-code
depends_on:
- 01M4X6X6PS5P524DW45RBSSWN2
- 01M4X71QQPKCEJ5490KD8R4C92
position_column: todo
position_ordinal: 8f80
title: Check cross-board dependsOn URIs and body task URLs on write, and warn for a missing task
---
## What
divergence.md Q3 as changed by P3 (DECIDED), X3, and §11 "Q3 (changed by P3)". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Problem (X3): in the same board, a URI to a missing task gives `NOT_FOUND`. A URI to a missing task on a different board is stored with no error and no sign. With X2, a typo blocks the task for good, and nothing shows why.

Decided behavior (final; P3 replaces the first rule of Q3):
- On write of `dependsOn` (addTask, updateTask) with a URI to a different board, and for each task URL (marker) in a written body, check the target:
  - The board is found and the task exists: store it, as now.
  - The board is found and the task is missing: accept and store the URI. It shows in `unresolvedDependsOn` (Q2) and blocks the task. The response gets a warning in `extensions.warnings` that names the URI and says that the task is missing on that board.
  - The board is not found: accept the URI, because the repo can be absent on this machine. It shows in `unresolvedDependsOn`. (A warning here is optional; if you add one, say that the board is not found.)
- Do the same check for body task URLs (markers) as for `dependsOn` edges.
- The rules for a target in the same board do not change.

Change the code: S/Identity/RefResolver.swift:303-312 (`remoteRef`) and S/GraphQL/TaskMutations.swift:198-200. Also check the task URLs in a body (markers).

## Acceptance Criteria
- [ ] `addTask(dependsOn: ["kanban://<found board>/task/<missing>"])` works, the task is BLOCKED, the URI is in `unresolvedDependsOn`, and the response has a warning.
- [ ] The same for a body that contains that URL.
- [ ] A URI to a board that is not found is accepted and is in `unresolvedDependsOn`.
- [ ] A URI to an existing task on another board works with no warning.

## Tests
- [ ] A `dependsOn` URI to a missing task on a found board.
- [ ] A `dependsOn` URI to a board that is not found.
- [ ] A body task URL to a missing task on a found board.
- [ ] The warning shows in `extensions.warnings`.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.