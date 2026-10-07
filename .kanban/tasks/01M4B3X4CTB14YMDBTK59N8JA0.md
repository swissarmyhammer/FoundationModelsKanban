---
depends_on:
- 01M4B3W5TJ921MJFG9AQ8B0QQR
position_column: todo
position_ordinal: 8c80
title: 'Body diff: apply with nearest match and conflict block'
---
## What
Apply a stored diff to a body during replay. The basis is plan.md §5.5.
- `Sources/FoundationModelsKanban/Body/DiffApply.swift`: apply each hunk in order. A hunk applies at its line number if its context and `-` lines match there. If not, find the nearest position where they match exactly (no fuzz).
- A hunk that cannot apply: insert a git-style conflict block at the hunk position: `<<<<<<< current` / the current lines / `=======` / the lines that the hunk wanted / `>>>>>>> <event id>`.
- Report whether the result has a conflict block (the `CONFLICT` virtual tag uses it later).
- The result depends only on the input, so all clones give the same text.

## Acceptance Criteria
- [ ] Two diffs made from the same base that change different lines both apply, in either order.
- [ ] Two diffs that change the same line give exactly one conflict block with the event id.
- [ ] The same inputs always give the same output.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Body/DiffApplyTests.swift`: exact apply, shifted apply, conflict, determinism.
- [ ] Run `swift test --filter DiffApplyTests`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.