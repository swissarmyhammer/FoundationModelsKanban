---
assignees:
- claude-code
depends_on:
- 01M4X6ZBTA66TCPVYM41QR0ACD
- 01M4X72R210B06MTDXZ4SXDCKE
position_column: todo
position_ordinal: a980
title: Cache readiness so that ready and nextTask do not walk the graph again on each call
---
## What
divergence.md §2 ("Performance"), §16 (Gap 3 of the "fully cached" rule), and K9 (the user kept this work). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

- Now `isReady` walks the dependency graph again for each task and for each done dependency (`S/Derived/Readiness.swift:147`). Nothing keeps the result. `ready`, the READY and BLOCKED virtual tags, the filters, and `nextTask` repeat this work on each call. On a large board this is slow.
- Keep the readiness of each task in memory, with the live graph of its board. Compute it one time when the board loads.
- Change it only when something that it depends on changes:
  - a write (the commit makes the working copy the live graph);
  - an apply of changed files from the file watcher;
  - a change of a related board that a cross-board dependency reads.
- After a change, compute again only the tasks that the change can affect: the changed tasks, and each task that depends on them, also across boards. A full compute is acceptable when the change is large (for example, a full reload).
- The result must always be the same as a full walk. This includes the rules for tombstones (ignored), unknown targets (they block), unresolved cross-board targets (they block), and cycles (each task in a cycle is blocked, also across boards, X8).

## Acceptance Criteria
- [ ] A read (`ready`, `#READY`, `#BLOCKED`, `nextTask`) does not walk the dependency graph when nothing changed since the last compute.
- [ ] After each kind of change (a write, a watcher apply, a change of a related board), the cached readiness is the same as a full walk.
- [ ] A cycle in one board and a cycle across boards still block each task in the cycle.

## Tests
- [ ] A property test: after a random sequence of writes, deletes, undeletes, dependency changes, and watcher applies, the cached readiness of each task equals a full walk.
- [ ] A test with a cross-board dependency: a change on the related board changes the readiness of the dependent task.
- [ ] A test that counts the graph walks: a second `nextTask` with no change between the calls does no walk.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.