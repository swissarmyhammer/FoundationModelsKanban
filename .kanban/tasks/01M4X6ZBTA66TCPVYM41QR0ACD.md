---
assignees:
- claude-code
depends_on:
- 01M4X6X6PS5P524DW45RBSSWN2
- 01M4X6XKP0Y832GDRHQ1MG22VF
- 01M4X6YD33YTSBBTG8VZFWTRZR
- 01M4X6YRT3543TS3S5K6RGZMCJ
position_column: todo
position_ordinal: '8480'
title: 'Add KanbanHost: one engine per board for each process, and a session view for each working directory'
---
## What
divergence.md §16 (M1, M2, Gap 2, L1, L6, X13, and the hard rules of the user). One ACP agent process runs many sessions at the same time. Each session has its own working directory. Now each session makes its own `KanbanGraph`, so N sessions load the same board N times, with N watchers, N search indexes, and N serial gates (M1). A write in one session reaches another session only after FSEvents reports it (M2). This is work on the Swift package (S/ = Sources/FoundationModelsKanban/). The wiring in the ACP agent repo is a separate change (not in this task).

The user: "We really don't want one process loading up the same board multiple times, and we really want each session to know and work on its default board from its cwd." "it's really important to me that each board, its file watchers — are only loaded once per process." "it's also important to me that the boards are fully cached in memory." "I want the board to be in memory all the time with write through — and file watch detection to allow manual poking of files."

Hard rules (the design must make a second load impossible, not only unlikely):
- One host for each process: `KanbanHost.shared` (a public actor) is the only way to get a host. There is no public `init`.
- One identity for each board: the host keys each board by the file identity (device and inode) of the folder that holds `.kanban/`, not by its path text. A symlink, `/tmp` against `/private/tmp`, a `..` in the path, or a different letter case on APFS gives the same board.
- One engine for current and related boards: one table of engines in the host. Remove the split between the current session (`loadState`) and `relatedBoards` in S/Tool/KanbanGraph.swift:74,84. A board that is the current board of one session and a related board of another session is the same engine.
- One watcher for each board: the engine owns the watcher. The watcher starts and stops only with the engine. This includes the watcher on the repo folder before `.kanban/` exists (X13).
- Load once under concurrency: two sessions that open the same board at the same time wait for one load. The host stores the load task in its table before the first `await`.
- Fully cached: a loaded board stays in memory until the host closes. It does not unload when its last session closes. A read (a query, `nextTask`, a filter, search) reads no file and runs no `git`. The file watcher is the only way that changes from outside the process reach memory.
- Write through: a write goes to the log files and to memory in the same commit (as now, S/Tool/Commit.swift:525-552). Keep the signature compare under the lock (S/Tool/Commit.swift:537-540).
- Each engine has one live graph, one watcher, one serial gate, one search index, and one change feed. The host also keeps the board locator and the scan index, one time for the process.
- Locks across boards: a call that writes more than one board takes the gates of those boards in a fixed order (by file identity or by path), so two sessions cannot deadlock.

Session API:
- `host.session(workingDirectory:actor:)` returns a `KanbanGraph` view for one session. The view has its own actor and its own default board (the board of its working directory). A call that names no board goes to that board.
- The public API of the view does not change: `execute`, `subscribe`, `close`, and `KanbanTool.init(graph:)`. `close()` of a view releases its references only. It does not stop an engine.
- A write in one session goes to the shared engine, so each other session sees it at once.
- `host.session(...)` does these steps before it returns (Gap 2: detect and load at session start, and wait):
  1. `git rev-parse --show-toplevel` in the working directory gives the worktree top. Not in a git repo: no board, and each kanban call gives `NOT_A_REPO` (see the task "Put the board only in a git repo").
  2. A repo with no commit gets the empty first commit (M8).
  3. The key: the `origin` remote, else `local/<root commit>` (M7).
  4. The host finds the engine of `<worktree top>/.kanban/` by file identity, or makes it (one watcher).
  5. The host loads the board (the logs, the graph, the event list, and the keyword index) if it is not loaded yet, and waits. A second session on the same board waits for the same load.
- A board that cannot load (for example `INCOMPATIBLE_BOARD`, Q6) makes `host.session` fail with that error.
- Related boards still load when a call first reaches them, and then stay in memory.
- L1: after `git rev-parse --show-toplevel` gives the folder, run the key read (with M8), the watcher start, and the file load at the same time. The log does not store the key, so the load does not need it.
- L6: the host must not hold its actor during a load. It keeps a load task for each board in its table, and the load runs outside the actor. Sessions on different boards load at the same time.
- Keep `KanbanGraph.init(root:actor:locator:embedder:)` only if the tests need it; it must not make a second engine for a board that the host has.

## Acceptance Criteria
- [ ] `KanbanHost.shared` exists and there is no public `init`.
- [ ] Many sessions on the same repo, on a symlink to it, and on a sibling repo that the first repo reaches as a related board give exactly one engine and one watcher for each board.
- [ ] Two sessions that start at the same time load the board one time.
- [ ] The board is loaded when `host.session` returns.
- [ ] A Rust board makes `host.session` fail with `INCOMPATIBLE_BOARD`.
- [ ] A write in session A shows in a read of session B at once, with no wait for FSEvents.
- [ ] `close()` of one view does not stop the board for another view, and the board stays loaded after the last view closes.
- [ ] A read runs no `git` and reads no file.
- [ ] Two sessions with different actors: `undo` with no argument in session B does not reverse the work of session A.
- [ ] Two boards load at the same time; the key read and the file load overlap.

## Tests
- [ ] Many sessions on one repo, a symlink, and a sibling related repo: one engine and one watcher for each board.
- [ ] Two sessions at the same time: one load.
- [ ] The board is loaded when `host.session` returns.
- [ ] A Rust board makes `host.session` fail.
- [ ] Two boards load at the same time; the key read and the file load overlap (use the worker observer or a test hook).
- [ ] Two worktrees are two engines with the same key.
- [ ] A git merge of two worktree branches gives the union of both boards.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.