---
assignees:
- claude-code
depends_on:
- 01M4G9Z14EEZ85ZSRQHFV1DCQ3
position_column: todo
position_ordinal: '9480'
title: 'board: path argument accepts any folder path'
---
## What
plan.md §6.6: "To use a different copy, the agent gives its path in the `board` argument." Now `Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift:251-257` and `:274-276` resolve a path only when the scan found that copy. Also only a value that starts with `/` or `~` is a path, so `../x` is not a path.

- Treat a `board` value as a path when it starts with `/`, `~`, `./` or `../`. Resolve a relative path from the `root` of the `KanbanGraph`.
- A path to any folder resolves, also when the scan did not find it. The key of that board comes from `BoardKey.read` (with the no-git rule of the earlier task).
- A path to a folder that does not exist gives `NOT_FOUND`.
- Update plan.md §6.6.

## Acceptance Criteria
- [ ] `board: "/tmp/x/other"` (outside the scan places) reads and changes the board in that folder.
- [ ] `board: "../sibling"` resolves from `root`.
- [ ] A path that does not exist gives `NOT_FOUND`.

## Tests
- [ ] Tests in `Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift` and a mutation test with `board:` set to a path.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.