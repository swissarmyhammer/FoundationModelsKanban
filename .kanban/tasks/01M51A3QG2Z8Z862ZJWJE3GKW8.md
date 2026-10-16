---
assignees:
- claude-code
position_column: todo
position_ordinal: b880
title: Find why a full swift test run can hang at 0% CPU
---
## What
During the test step of ^x020t0g, one full `swift test` run made no progress for 30 minutes at 0% CPU, and its output was lost. The tester stopped the run. The next full run, with the same code, passed 1552 tests in 62 seconds. An earlier session also saw a test process that did not stop. A hang at 0% CPU can be a deadlock (for example a lock, a continuation that never resumes, or an FSEvents wait), not machine load.

Possible areas: the host FSEvents stream and router (S/Observe/FolderStreams.swift, ^swk9c8n), the WatcherBudget test trait, the serial gate in KanbanGraph, and git runs in Git.run.

## Change
- Run the full suite many times with output saved to a file, and with a time limit on the whole run. When a run hangs, take a sample of the process (`sample <pid>`) to see which threads wait and where.
- Fix the cause. Add a test that fails on the hang.

## Acceptance Criteria
- [ ] The cause of the hang is found and recorded on this card.
- [ ] The cause is fixed, or a new task records the fix.
- [ ] 10 full `swift test` runs in a row finish.

## Tests
- [ ] A test for the cause, in temporary fixture folders (never the `.kanban/` of this repo).
- [ ] `swift test` passes.