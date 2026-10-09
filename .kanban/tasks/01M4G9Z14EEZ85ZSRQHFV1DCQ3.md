---
assignees:
- claude-code
depends_on:
- 01M4G9M4WCVGV3X1JAQJ47QCME
position_column: todo
position_ordinal: '9780'
title: BoardLocator finds boards in folders that are not git repos
---
## What
The owner decided that git is not required. The task ^j47qcme gives a board key to a folder that is not a git repo. But `repos(in:)` in `Sources/FoundationModelsKanban/CrossRepo/BoardLocator.swift` (about lines 77-93) accepts a directory only when it has a `.git` entry. Thus the locator does not find a related board in a folder that is not a git repo.

- `repos(in:)`: a directory is a candidate when it has a `.git` entry OR a `.kanban/board.jsonl` file.
- Find the other `Git.run` callers (`rg -n "Git.run" Sources`). Make each one work when the folder is not a git repo: skip the git step, or use the `local/<folder-name>` rule of ^j47qcme. Do not throw `gitFailed` for a folder that is not a git repo.
- Update plan.md: §6.6, §12 items 13 and 26. Say that the locator finds a board in a folder with `.kanban/board.jsonl` and no `.git`.

## Acceptance Criteria
- [ ] The locator finds a related board in a sibling folder that has `.kanban/board.jsonl` and no `.git`.
- [ ] A sibling folder with no `.git` and no `.kanban/board.jsonl` is not a candidate.
- [ ] No `Git.run` caller throws for a board in a folder that is not a git repo.
- [ ] Each existing locator test still passes.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/CrossRepo/BoardLocatorTests.swift`: a sibling board with no `.git`, and a sibling folder with no `.git` and no board.
- [ ] A test that runs a cross-board query from a board in a plain temp folder to a sibling board in a plain temp folder.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.