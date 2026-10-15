---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m5087c5vsqwm6cr8tpmcrs0s
  text: |-
    ### finish iteration 1 — stuck
    - implement: not run. This task asks for a decision by a person: should `Query.boards` stop the whole call when a sibling repo has a Rust `.kanban`, or skip that sibling and give a warning?
    - next: the user decides. Then record the decision in divergence.md and run /finish on this task again.
  timestamp: 2026-10-15T17:02:14.715453+00:00
depends_on:
- 01M4X6YRT3543TS3S5K6RGZMCJ
position_column: todo
position_ordinal: aa80
title: Decide how Query.boards treats a sibling repo with a Rust .kanban
---
## What
After ^6rgzmcj, each board load checks for Rust files (divergence.md Q6). `Query.boards` loads each copy that the scan finds (`KanbanGraph.loadEachCopy`). The default scan looks in the parent folder of the repo. When one sibling repo has a Rust `.kanban/`, the whole `boards` call now stops with `INCOMPATIBLE_BOARD`. Many repos of the user still have Rust boards, so `boards` can fail in normal use.

Q6 says: an incompatible related board stops the call. It does not say if a board that the call only lists (and does not name) is a "related board that Swift opens".

## Decision needed
- Option A: keep the current behavior (any incompatible copy stops `boards`).
- Option B: `boards` lists an incompatible copy without loading it (for example with a flag or a warning), and only a call that names the board stops with `INCOMPATIBLE_BOARD`.

## Acceptance Criteria
- [ ] A person records the decision in divergence.md.
- [ ] The code and the tests follow the decision. Tests use temporary fixture folders only.