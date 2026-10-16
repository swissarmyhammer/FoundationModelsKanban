---
assignees:
- claude-code
depends_on:
- 01M52RKMDD8RJ7TNTQVE65466D
position_column: todo
position_ordinal: b580
title: Add checkLinks, and resolve an old board name at read time with a warning
---
## What
divergence.md M9 "checkLinks and repairLinks". A user must find links that use an old board name, and links that no board can resolve.

## Do
- `checkLinks(boards:)` (read only) reads the stored refs of the named boards: `dependsOn`, assignee URIs, task URLs in bodies, tombstone lines. Each link gets a class: **ok**, **old name** (with the current name), **dangling**, or **missing node**.
- An old-name link works at read time (readiness and reads use the board that has the old name now). The response gives a warning for it.
- `board(id:)` with an old name gives the board that has it now, with its current names.

## Acceptance Criteria
- [ ] Each of the four classes has a test.
- [ ] A task that depends on a task through an old board name is ready when that task is done, and the response warns.
- [ ] `board(id:)` with an old name gives the current board.
- [ ] Tests use temporary folders and temporary git repos only.