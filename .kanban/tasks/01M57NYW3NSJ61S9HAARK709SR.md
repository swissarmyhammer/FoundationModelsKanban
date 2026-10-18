---
assignees:
- claude-code
position_column: todo
position_ordinal: b980
title: Stop the tests that leave their TemporaryDirectory folder on the disk
---
## What
After a full `swift test`, about 96 folders `EventLogTests-<UUID>` stay in `/tmp/fmk-tests/<run id>/TemporaryDirectory/` (3 runs on 2026-10-18: 288 folders). The old location `$TMPDIR/FoundationModelsKanbanTests` holds 771 such folders, so the leak is older than ^wphkeqk. Each folder holds a board fixture (`.kanban/board.jsonl`, `.kanban/columns/todo.jsonl`, `.kanban/tasks/01M3ZYPDG00040000000000009.jsonl`, `.gitignore`, `.gitattributes`).

## Possible cause (not checked)
Some tests use a `TemporaryDirectory` with no binding, for example `KanbanGraphTests.writeFixture(inRepoAt: TemporaryDirectory().url)` (AddUpdateTaskTests), `Self.makeTool(inRepoAt: TemporaryDirectory().url)` (KanbanToolTests). Swift can release the value just after `.url` is read. Then `deinit` removes the empty folder, and the fixture write makes the folder again (`withIntermediateDirectories: true`), and nothing removes it.

## Acceptance
- [ ] Find each test that leaves a folder (list the folders after a full run, and map the fixture to the test).
- [ ] Each test removes its own folder at the end.
- [ ] After a full `swift test`, `/tmp/fmk-tests` is empty.