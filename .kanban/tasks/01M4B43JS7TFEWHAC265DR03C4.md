---
depends_on:
- 01M4B406Z7RVSBJKKJ8KJW0CY2
- 01M4B40CFSF002B4DKM3T8J6GV
- 01M4B4B57JFX8HA0B45MMDQ1SQ
- 01M4B41VDXZ3NKEG4554PVXWQN
position_column: todo
position_ordinal: a980
title: Merge, portability, and replay property tests
---
## What
The tests in plan.md §11 that check the whole design, not one feature.
- `Tests/FoundationModelsKanbanTests/Design/ReplayPropertyTests.swift`: random sequences of public mutations; a fresh load of the logs gives the same projection as the live graph after the writes. Each public mutation writes only `patch` events with only the properties that change.
- `Design/MergeTests.swift`: simulate `union` merges of two branches (concatenate the lines of both sides):
  - two branches add different tags to one task → both tags;
  - one branch renames `bug` to `defect` while the other adds `bug` to a task → after the merge, the task shows `defect`;
  - two branches change different lines of one body → both changes; the same line → one conflict block, `#CONFLICT`, and a `body` update removes it;
  - broken merged states (half of a dependency cycle on each side; a column deleted on one side while a task moves into it on the other; a rename cycle) replay without error and show as plan.md §5.3 says.
- `Design/PortabilityTests.swift`: no log line holds the key of its own board; change the `origin` (and, in a second test, the directory name): the log files do not change, each `id` has the new key, and all edges resolve. A full URI with the current key in the input is stored as a local ref.
- `Design/SchemaChangeTests.swift`: a log with an unknown property replays; a new property on an old node gives its default value.

## Acceptance Criteria
- [ ] The property test runs at least 200 random sequences with a fixed seed and passes.
- [ ] Each merge case gives the result that plan.md §5.3, §5.5, and §6.2 describe.
- [ ] The repo move changes no log file and keeps all edges.

## Tests
- [ ] The four test files above.
- [ ] Run `swift test --filter Design`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.