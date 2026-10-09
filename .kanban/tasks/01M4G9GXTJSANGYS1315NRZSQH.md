---
assignees:
- claude-code
position_column: todo
position_ordinal: '8180'
title: Board URI parse and case-insensitive board key host
---
## What
Two defects in board identity (plan.md §3.2).

1. `Sources/FoundationModelsKanban/Identity/NodeURI.swift:79-87` (`refSegmentCount`): when the last segment is `board`, the URI is the board URI `kanban://<board-key>/board`, also when the segment before it is a node type name. Now `kanban://local/tag/board` parses as key `local` + ref `tag/board`, and `kanban://github.com/acme/task/board` throws `invalidULID`. Fix: test for the board form first.
2. `NodeURI.swift:32-34` and `Identity/BoardKey.swift:58`: the key compare is case-sensitive, and the host of an input URI is not made lowercase. `kanban://GitHub.com/o/r/task/<id>` to the current board becomes a remote ref. Fix: when a URI is parsed, normalize the host segment of the key to lowercase, with the same rule as `BoardKey(remoteURL:)`. The path keeps its case.
- Update plan.md §3.2 to say that the host part of a key ignores case.

## Acceptance Criteria
- [ ] `NodeURI` parses `kanban://local/tag/board` and `kanban://github.com/acme/task/board` as board URIs with the full key.
- [ ] A `dependsOn` URI with `GitHub.com` to a task of the current board is stored as a local ref (`task/<ULID>`).
- [ ] The cycle check (rule 6) finds a cycle when one edge uses the uppercase host.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/Identity/NodeURITests.swift`: board URIs whose repo name is `task`, `tag`, `column`, `actor`, `comment`; mixed-case host.
- [ ] A mutation test (in `Tests/FoundationModelsKanbanTests/Mutations/`): `updateTask(dependsOn:)` with an uppercase host stores a local ref and the task is not blocked when the target is done.
- [ ] `swift test --filter NodeURI` and `swift test` pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.