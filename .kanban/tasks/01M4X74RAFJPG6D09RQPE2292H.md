---
assignees:
- claude-code
position_column: todo
position_ordinal: '9980'
title: Add root query verbs and map createBoard and newBoard to initBoard
---
## What
divergence.md Q10 and Q11 (DECIDED: yes), N3, N4, and §11 "Q10", "Q11". This is work on the Swift package (S/ = Sources/FoundationModelsKanban/). Code: S/GraphQL/NameMatcher.swift and S/GraphQL/NameRewrite.swift.

Q10, root query verbs (N3): now `getTask`, `listTasks`, `getBoard`, `listColumns`, `search`, and `next` all fail, because step 4 (word order and verb synonyms) applies only to mutations. Add verbs at the root of a query:
- `get`, `show`, `read`, `fetch` + a noun → the singular field (for example `getTask` → `task`, `getBoard` → `board`, `showColumn` → `column`).
- `list`, `find`, `query` + a noun → the plural field (for example `listTasks` → `tasks`, `listColumns` → `columns`).
- `search` (and `searchTask`, `searchTasks`) → `searchTasks`.
- `next` (and `getNext`, `nextTask`) → `nextTask`.
- Where a root field does not exist for a noun (for example columns are on `board`), map to the field that gives that list if there is one clear target; else keep the normal no-match error.

Q11 (N4): `createBoard` and `newBoard` map to `initBoard`. There is no `addBoard`, so there is no conflict. Now the never-list stops `create → init`, and the verb synonyms map `new` to `add` (S/GraphQL/NameMatcher.swift:50,90), so `newBoard` gives `addBoard`, which does not exist. Change this so that, for the noun `Board`, `create` and `new` map to `init`. For other nouns, `create` and `new` still map to `add`.

## Acceptance Criteria
- [ ] `{ getTask(id: "<id>") { title } }` works as `task`.
- [ ] `{ listTasks { nodes { id } } }` works as `tasks`.
- [ ] `{ getBoard { name } }` works.
- [ ] `{ search(query: "x") { ... } }` works as `searchTasks`.
- [ ] `{ next { id } }` works as `nextTask`.
- [ ] `mutation { createBoard(...) }` and `mutation { newBoard(...) }` work as `initBoard`.
- [ ] `createTask` still maps to `addTask`.

## Tests
- [ ] A test for each verb group (`get`, `show`, `read`, `fetch`, `list`, `find`, `query`, `search`, `next`).
- [ ] Tests for `createBoard`, `newBoard`, and `createTask`.
- [ ] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.