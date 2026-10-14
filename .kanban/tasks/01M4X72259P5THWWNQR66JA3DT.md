---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4y8g4szjkes0mc8g8y8ytct
  text: |-
    Research done.
    - The store and the read already accept a dependsOn URI to a different board (`RefResolver.storedRef(acceptingRemote: true)` gives `.remote`) and a body marker to any board. The task is blocked, and the URI shows in `unresolvedDependsOn`. Only the warning is missing.
    - `CommitSession.runReading` runs the call again after it loads the boards that the new edges and markers name (`dependencyRequests(of: work.graph)`). Thus in the last run, `WorkingCopy.otherBoards` has the resolution of each target board. Each run has a new `KanbanContext`, so a warning of an earlier run does not go into the response.
    - Plan: add `RelatedBoards.state(ofDependencyOn:)` (found / task missing / board not found / not known yet). `WorkingCopy.write(_:toTask:inBoard:at:)` gives a warning for each remote target of the written dependsOn list and of the markers of the written body. addTask and updateTask run through `BoardStore.runMutation` so that the field gives the warnings back, and the resolver adds them to `context.warnings`.
    - Codes: `DEPENDENCY_TASK_NOT_FOUND` (required) and `DEPENDENCY_BOARD_NOT_FOUND` (the optional warning; I add it, so that a typo in a key shows why). A board that cannot be read already has `BOARD_UNREADABLE`, so it gets no second warning.
    - The existing test `addTaskDependsOnRemoteTask` checks `response.hasSuffix("ready":false}}}")`. The new board-not-found warning adds `extensions` to that response, so that test needs an update.
  timestamp: 2026-10-14T22:28:33.215273+00:00
- actor: claude-code
  id: 01m4y8ynqy1fwcg4vp2yyrp5v3
  text: |-
    Implementation landed (TDD: 4 of 5 new tests failed first, only on the missing warning; then all passed).
    - `RelatedBoards.state(ofDependencyOn:)` and `DependencyTargetState` (found / missingTask / boardNotFound / unknown). A key that the run did not resolve yet gives `unknown`, so the first run of a call gives no warning; the run after the board load gives it. A board that cannot be read gives `unknown`, because it already has `BOARD_UNREADABLE`.
    - New `GraphQL/DependencyWarnings.swift`: codes `DEPENDENCY_TASK_NOT_FOUND` and `DEPENDENCY_BOARD_NOT_FOUND`. The targets are the remote refs of the written `dependsOn` list plus the remote markers of the written body, one time each. Same-board targets do not change.
    - `WorkingCopy.write` gives the warnings. addTask and updateTask use the new `KanbanContext.changeTask`, which runs `BoardStore.runMutation` and adds the warnings with the new `ResponseWarnings.add(contentsOf:)`. `BoardView.object(of:)` is shared with `BoardStore.changeNode`.
    - Doc comments of `RefResolver.remoteRef` and `dependencyRefs` state the decided behavior. The code of `remoteRef` did not need a change: it already accepts the URI.
    - Existing test `addTaskDependsOnRemoteTask` now reads `ready` from the data and checks the board-not-found warning, because the response now has `extensions`.
    - `swift test`: 1260 tests in 95 suites passed. Only the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-14T22:36:29.310038+00:00
- actor: claude-code
  id: 01m4y8yrr4zvppc67x351t1ffg
  text: |-
    ### implement — changed
    - evidence: 7 files — Sources/FoundationModelsKanban/CrossRepo/RelatedBoards.swift, Sources/FoundationModelsKanban/GraphQL/DependencyWarnings.swift (new), Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift, Sources/FoundationModelsKanban/GraphQL/ColumnActorMutations.swift, Sources/FoundationModelsKanban/GraphQL/ResponseWarnings.swift, Sources/FoundationModelsKanban/Identity/RefResolver.swift (doc only), Tests/FoundationModelsKanbanTests/CrossRepo/DependencyTargetWarningTests.swift (new), Tests/FoundationModelsKanbanTests/Mutations/AddUpdateTaskTests.swift; swift test 1260 passed, 0 failed
    - next: /review
  timestamp: 2026-10-14T22:36:32.388681+00:00
- actor: claude-code
  id: 01m4y9d2k27c0vkc3qs2yvqs5e
  text: |-
    ### finish iteration 1 — findings
    - implement: changed — 8 files
    - test: green — swift test, 1260 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: 7e32657
    - review: findings — Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift:182 (duplication/duplication), Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift:182 (reuse/reuse), Tests/FoundationModelsKanbanTests/CrossRepo/DependencyTargetWarningTests.swift:19 (reuse/reuse)
  timestamp: 2026-10-14T22:44:21.218710+00:00
- actor: claude-code
  id: 01m4y9pqdvm1r6zzjcn42w9mxt
  text: |-
    Review findings fixed (iteration 2).
    - Findings 1 and 2 (duplication, reuse): new generic `KanbanContext.runMutation(named:on:_:)` in GraphQL/ColumnActorMutations.swift. It reads `clock()` and calls `BoardStore.runMutation` one time, and gives `(value, view)?`. `KanbanContext.changeNode` and `KanbanContext.changeTask` both call it. `changeTask` now only adds the warnings and reads the task object.
    - `BoardStore.changeNode(named:on:at:_:)` had no caller after this change (only `KanbanContext.changeNode` called it), so I deleted it as dead code. The doc links that named it now name `runMutation(named:on:_:)`.
    - Note: finding 1 says "Have changeNode and changeTask both call it" and also "Do not edit the existing changeNode copy". The dispatcher said that one shared helper that both call satisfies findings 1 and 2, so `KanbanContext.changeNode` changed only to call the helper.
    - Finding 3: deleted both test-side code constants (`taskNotFoundCode` and `boardNotFoundCode`) in DependencyTargetWarningTests.swift; the tests use `DependencyWarnings.*`. AddUpdateTaskTests.swift also read `DependencyTargetWarningTests.boardNotFoundCode`; it now reads `DependencyWarnings.boardNotFoundCode`.
    - Tool note: the `files` edit with `replace_all: true` changed only the first match. Check the count of replacements.
    - swift test: 1260 tests in 95 suites passed. Only the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-14T22:49:37.467751+00:00
- actor: claude-code
  id: 01m4y9psm08wfbvyr3rwjq4x92
  text: |-
    ### implement — changed
    - evidence: 4 files — Sources/FoundationModelsKanban/GraphQL/ColumnActorMutations.swift, Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift, Tests/FoundationModelsKanbanTests/CrossRepo/DependencyTargetWarningTests.swift, Tests/FoundationModelsKanbanTests/Mutations/AddUpdateTaskTests.swift; swift test 1260 passed, 0 failed; 3 of 3 findings checked
    - next: /review
  timestamp: 2026-10-14T22:49:39.712618+00:00
- actor: claude-code
  id: 01m4ya2c8b04afcdqn5mfzrv2b
  text: |-
    ### finish iteration 2 — clean
    - implement: changed — 4 files (3 findings fixed)
    - test: green — swift test, 1260 passed, 0 failed, 0 skipped; IntegrationTests 2 passed
    - commit: c3d16ac
    - review: clean — none
  timestamp: 2026-10-14T22:55:59.243375+00:00
depends_on:
- 01M4X6X6PS5P524DW45RBSSWN2
- 01M4X71QQPKCEJ5490KD8R4C92
position_column: done
position_ordinal: ec80
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

## Review Findings (2026-10-14 17:39)

> Scope: `review sha HEAD~1..HEAD` — reviewed the diffs only — lines this change added or modified. 8 file(s) reviewed, 4 not reviewed.

> 4 file(s) not reviewed — excluded by an ignore rule:
> - `.kanban/ (from .reviewignore)` — 4 file(s)

- [x] `Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift:182` `duplication/duplication` — The new `KanbanContext.changeTask` repeats the body of the existing `KanbanContext.changeNode`. Both read `clock()`, call `store.runMutation` with the same arguments, return `nil` when the board is not loaded, and return the object of the changed node. Only the warnings handling and the return type differ. If the mutation flow changes, both copies must change in step. Make one shared helper that takes the body and returns the changed value plus its view, with the clock and the `runMutation` call written once. Have `changeNode` and `changeTask` both call it. The warnings are then added only in `changeTask`. Do not edit the existing `changeNode` copy as part of this change; if it must change, report that as a separate task.
- [x] `Sources/FoundationModelsKanban/GraphQL/TaskMutations.swift:182` `reuse/reuse` — `KanbanContext.changeTask` repeats the body of `KanbanContext.changeNode` in ColumnActorMutations.swift: it reads `clock()`, calls `store.runMutation`, returns nil when the board is not loaded, and returns `view.object(of:)`. Only the body's return type (`TaskWrite`) and the added `warnings.add(contentsOf:)` call differ. The near-match was copied instead of generalized, so the mutation flow now lives in two places. Generalize the existing `KanbanContext.changeNode` so its body can return a result type `R` together with the object, or add a small generic helper that both `changeNode` and `changeTask` call. Keep the warnings hand-off as the only task-specific step in `changeTask`.
- [x] `Tests/FoundationModelsKanbanTests/CrossRepo/DependencyTargetWarningTests.swift:19` `reuse/reuse` — The test suite redeclares `boardNotFoundCode` with the same literal value as the production constant `DependencyWarnings.boardNotFoundCode`. The same drift risk applies. Delete the test-side constant and reference `DependencyWarnings.boardNotFoundCode` directly.
