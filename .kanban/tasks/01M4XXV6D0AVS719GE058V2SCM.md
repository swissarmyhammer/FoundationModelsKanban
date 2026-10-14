---
assignees:
- claude-code
depends_on:
- 01M4X707X79HZ4TJARR3PRJNB4
- 01M4X72ZMQ49D1DTVKFGZ2MXWZ
position_column: todo
position_ordinal: ab80
title: Keep the result of a path board ref in memory, so a repeated path ref runs no git
---
## What
divergence.md §16 Gap 1 (the rule: a read runs no `git`). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Found during ^3prjnb4. `KanbanGraph.resolution(of:current:)` sends a path ref that the scan index does not have to `BoardLocator.resolution(ofFolderAt:...)`. That function runs `git rev-parse --show-toplevel` (the top reader) and the key read on each call. The card ^gz2mxwz puts a board that a path reached into the key index, so a later ref to that board hits the index. But these cases still run `git` on each call:
- a path to a folder that is not in a git repo (the call gives `NOT_A_REPO`);
- a path to a repo whose key read fails.

Change:
- Keep the result of a path ref (the board, `notARepo`, or a failed key read) in the host, in memory.
- Forget the result when a file watcher sees a change of that folder (a new `.git`, a changed git config), the same as the scan cache of ^3prjnb4 (`ScanCache`, `ScanChange`).

## Acceptance Criteria
- [ ] A second call with the same path ref to a folder that is not in a git repo runs no `git`.
- [ ] A second call with the same path ref to a repo whose key read fails runs no `git`.
- [ ] After `git init` in that folder, the next call with the path ref finds the board.

## Tests
- [ ] A git-call counter stays the same over many calls with the same path ref.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.