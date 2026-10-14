---
assignees:
- claude-code
position_column: todo
position_ordinal: '9780'
title: Add alias tables for each input type and the synonym table, and forgive the Rust names
---
## What
divergence.md Q9, Q14, E5 (final "forgive all"), K16, N2, tables 4.2 and 4.3, and §11 "Q8–Q15". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/). Code: S/GraphQL/NameMatcher.swift, S/GraphQL/NameRewrite.swift, and the alias table at S/GraphQL/Schema.swift:1002-1013.

Principle from the user: be VERY FORGIVING. When a name that an agent can send has only one possible meaning in that position, accept it. Refuse a name only when it can mean two different fields (`AMBIGUOUS_NAME`) or when it means no field. Tables 4.2 and 4.3 are the minimum, not the full list.

Mechanism changes:
- N2/Q9: move the aliases to a table for each input type (and each field argument list). Keep a global table only for names that are safe everywhere. Remove the global `task_id → id` (it sends the task ref to the comment `id` on `updateComment`/`deleteComment`). Also move the global aliases `assignee → assignees` and `status` (S/GraphQL/Schema.swift:1008-1009) to the tables for each input type, because on `assignTask`/`unassignTask` `assignee` maps to `actor`.
- The matcher order stays: exact, case and style fold, singular/plural, word order and verb synonyms (mutations), alias table, one-letter edit (names of 4+ letters).

Synonym table (4.3) to add (agent sends → where → maps to):
- `name`, `subject`, `summary` → task inputs → `title`
- `notes`, `details`, `message`, `comment`, `text`, `description` → all inputs → `body`
- `state`, `status`, `lane`, `col`, `columnId`, `column_id`, `to`, `toColumn` → `addTask`, `moveTask` → `column`
- `before_id`, `beforeId`, `beforeTask` / `after_id`, `afterId`, `afterTask` → `moveTask` → `before` / `after`
- `assignee`, `actorId`, `actor_id`, `user`, `who` → `assignTask`, `unassignTask` → `actor`
- `assignTo`, `owner`, `owners` → task inputs → `assignees`
- `author`, `user` → `addComment` → `actor`
- `task_id`, `taskId` → `addComment` → `task` (alias for this type only)
- `task`, `ref`, `uri`, `key`, `<type>Id`, `<type>_id` → inputs for that node type → `id`
- `dependencies`, `dependency`, `depends`, `deps`, `blockers`, `prerequisites`, `blockedBy` (Q14) → task inputs → `dependsOn`
- `labels`, `label` → task inputs → `tags`
- `tag`, `old`, `oldName` / `name`, `new`, `newName` → `renameTag` → `from` / `to`
- `top_k`, `topK`, `limit`, `page_size`, `count`, `size` → `tasks`, `searchTasks`, `history` → `first`
- `cursor` → `tasks` → `after`
- `transaction`, `txnId`, `txn_id`, `id` → `undo`, `redo` → `txn`
- `path`, `board`, `key`, `repo` → `board(id:)` → `id`
- `removeAssignee` → mutation → `unassignTask`
- `created_at`, `updated_at`, `count`, `total` → selection → `created`, `updated`, `totalCount`
- (Root query verbs, `createBoard`/`newBoard`, and `priority` are separate tasks.)

E5 rows (forgive all; added to 4.3):
- Column operations (get, update, delete column) map `column` to `id`.
- `updateTask` with `column` also moves the task to that column (at the end), in the same transaction. (Rust ignores this key; Swift does the move.)
- `updateComment` and `deleteComment` accept `task_id` and `task`. Swift checks that the comment is on that task, and gives `NOT_FOUND` if not (K16).

Rust names that fail today (table 4.2), each must work after this task: `assignee` on assign/unassign; `before_id`/`after_id` on `moveTask`; `task` for `id` on task operations and `Board.task`; `col` on `addTask`/`moveTask`; `column` for `id` on column operations; `task_id`/`taskId` on `addComment`; `task_id` and `task` on `updateComment`/`deleteComment` (with `id` also sent, as Rust does); `page_size`/`top_k` on `tasks`/`searchTasks`; `remove_assignee`; `column` on `updateTask`.

Note: `variables` rewrite (Q8) is a separate task that uses these tables.

## Acceptance Criteria
- [ ] Each row of table 4.2 works in the document text.
- [ ] Each row of table 4.3 (in this task) works in the document text.
- [ ] `updateComment(input: {id: <comment>, task_id: <task>, body: "x"})` works; with a different task it gives `NOT_FOUND`.
- [ ] `updateTask(input: {id: <task>, column: "doing"})` moves the task to the end of `doing` in the same transaction.
- [ ] No global alias sends `task_id` to `id`.
- [ ] A name that can mean two fields still gives `AMBIGUOUS_NAME`.

## Tests
- [ ] A test for each row of table 4.2.
- [ ] A test for each row of table 4.3 in this task.
- [ ] Tests for the three E5 rows (column ops `column`→`id`, `updateTask` with `column`, comment ops with `task_id`/`task` and the `NOT_FOUND` check).
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.