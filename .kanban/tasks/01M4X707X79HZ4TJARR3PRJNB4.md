---
assignees:
- claude-code
depends_on:
- 01M4X6ZBTA66TCPVYM41QR0ACD
position_column: todo
position_ordinal: '8880'
title: Keep a "board not found" result in memory and run no git on reads
---
## What
divergence.md §16 Gap 1 and X10 (K9 keeps it as work). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/).

Now a board ref or a `dependsOn` URI that names no known board starts a new scan on each call (S/Tool/KanbanGraph.swift:720). The "not found" result lasts for one call only (S/Tool/Commit.swift:409). The scan runs `git` in each repo that it finds, and git runs again on each call for repos whose key read failed (S/CrossRepo/BoardLocator.swift:174-193). With P3, a URI with a typo is stored, so each call that reaches that task runs the scan again. This breaks the user rule: a read (a query, `nextTask`, a filter, search) reads no file and runs no `git`. It uses only memory.

Change:
- Keep the "not found" result for a board key (and the failed key reads) in the host, in memory.
- Scan again only when a watcher sees a new folder (or a new `.kanban/`, or a changed git remote) in a scan place. Then clear the cached "not found" results.
- A read never runs `git` and never scans.

## Acceptance Criteria
- [ ] A second call that reaches the same unknown key runs no scan and no `git`.
- [ ] When a new repo with that key appears in a scan place, the watcher clears the cache and the next call finds the board.
- [ ] Reads run no `git` (check with a git-call counter or test hook).

## Tests
- [ ] Two calls that reach an unknown key: the scan runs one time.
- [ ] A new repo folder in a scan place: the next call resolves the key.
- [ ] A counter of git runs stays the same over many read calls.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.