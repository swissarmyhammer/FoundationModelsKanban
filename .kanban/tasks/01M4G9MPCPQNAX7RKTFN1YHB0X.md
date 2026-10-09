---
assignees:
- claude-code
depends_on:
- 01M4G9GQ28QA3Z7MYQG9JE3H3Z
- 01M4G9M4WCVGV3X1JAQJ47QCME
- 01M4G9X4JXCBM7XGC5NYQNXGE1
position_column: todo
position_ordinal: '9580'
title: 'Examples: Get started in the README, with tests that run each example'
---
## What
The owner said there are no examples: a reader cannot see how to set up a board in a folder, or where the `.kanban/` directory goes. After the CLI is removed, the Swift API is the only way to use the package.

Write a "Get started" section in `README.md` (ASD-STE100 Simplified Technical English) with these examples:
1. **Open a board in a folder.** `KanbanGraph(root: URL(filePath: "/path/to/folder"), actor: nil)`. Say that the board is at `<root>/.kanban/`, that the folder does not need to be a git repo, and that the first mutation makes the board with the default columns (`todo`, `doing`, `review`, `done` — use the real values from `DefaultColumn.all`).
2. **Add and list tasks.** `execute(query:variables:operationName:)` with an `addTask` mutation with variables, then a `tasks(filter:)` query. Show the JSON response.
3. **Give the tool to a model.** `KanbanTool(graph:)` in a `LanguageModelSession(tools:)`.
4. **Code mode.** A Multitool script that calls `tools.kanban({ query, variables })` (the same shape as the step 18 test in `Tests/FoundationModelsKanbanTests/Multitool/`).
5. **Watch changes.** `subscribe(query:...)` with `changes(filter:)`, and `close()`.
6. **The layout of `.kanban/`.** The tree from plan.md §5.2, and a note that the files go in git with the `union` merge driver.

The task ^yqnxge1 keeps these four filter documents in `README.md` as plain ```graphql code blocks. Use them in the examples:
- In example 2, show Swift `execute` calls with `{ tasks(filter: "#bug && @alice") { … } }`, `{ history(filter: "~column", first: 5) { … } }`, and `{ history(filter: "^01jabcd") { … } }`.
- In example 5, show a Swift `subscribe` call with `subscription { changes(filter: "#bug || ~comment") { … } }`.

Keep the examples correct: add `Tests/FoundationModelsKanbanTests/ReadmeExamplesTests.swift`. It runs examples 1, 2, 4 and 5 with the same code as the README, in a temporary folder with no `.git`. Example 3 needs a model, so only check that it compiles (build a `LanguageModelSession` with the tool, do not call `respond`).

## Acceptance Criteria
- [ ] `README.md` has a "Get started" section with the six items above, and no `kanban` shell commands.
- [ ] Examples 2 and 5 use the four filter documents as Swift `execute` and `subscribe` calls.
- [ ] `ReadmeExamplesTests` reads `README.md` from the package root (use `#filePath` to find it), extracts each ```graphql code block, and runs each one against a temporary board with no `.git`. Each response has no `errors`.
- [ ] The README says where `.kanban/` goes and what files it holds.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/ReadmeExamplesTests.swift` runs the examples and checks the responses (no `errors`, expected task title).
- [ ] `ReadmeExamplesTests` runs each ```graphql code block of `README.md` (a `subscription` document with `subscribe`, other documents with `execute`) and checks that no response has `errors`.
- [ ] `swift test --filter ReadmeExamples` and `swift test` pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.