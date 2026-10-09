---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4h7wytttdyba371es5xbmcx
  text: |-
    Research done.
    - Public API: `KanbanGraph(root:actor:locator:embedder:)`, `execute(query:variables:operationName:)` (JSON text, sorted keys), `subscribe(query:variables:operationName:)` (AsyncThrowingStream<String, Error>), `close()`, `KanbanTool(graph:)`.
    - `DefaultColumn.all` (MutationResolvers.swift): todo (To Do), doing (Doing), review (Review), done (Done).
    - `.kanban/` layout in EventLog.swift: board.jsonl, columns/, actors/, tags/, tasks/, comments/, .gitattributes (`*.jsonl merge=union`), .gitignore (`.lock`), .lock.
    - Assignees must name a live actor, so the README mutation adds actor `alice` in the same document before `addTask`.
    - Reuse: RepositoryFile (README via #filePath), DocumentationTests filter blocks, CodeModeTests.run (MultiTool runCode), SubscriptionTests.events/allEvents, KanbanGraphTests.object, NameRewriteTests.errors/data, TemporaryDirectory.
    - Plan: README Swift blocks hold each GraphQL document as a multi-line string literal; the test extracts those literals and each ```graphql block, and runs them on a board in a temp folder `my-project` with no .git (key local/my-project). Responses with no minted ids are checked with exact equality against ```json blocks of the README.
  timestamp: 2026-10-09T21:07:56.890642+00:00
- actor: claude-code
  id: 01m4h86kprd3yx3q1az76599k9
  text: |-
    Implementation landed.
    - README: new "Get started" section (6 items, ASD-STE100). The old "Examples" section is now "Filters" and keeps the four ```graphql blocks.
    - Choices: the folder of the examples is `my-project`, so the key is `local/my-project`. `assignees` must name a live actor, so the example 2 mutation adds actor `alice` in the same document. Example 5 triggers the subscription with a second `#bug` task (no id needed). `history(filter: "^01jabcd")` on a board with no such short id gives `{"data":{"board":{"history":[]}}}` and no error.
    - Each GraphQL document of a Swift block is a multi-line string literal; the test extracts the literals and holds set equality with the documents it runs. ```json blocks are exact-equality checks for the stable responses (columns, addTask, code mode result).
    - Shared helpers: `RepositoryFile.codeBlocks(of:at:)` + `CodeLanguage` (DocumentationTests now uses it); the four filter documents are named constants on DocumentationTests; `CodeModeTests.run` is now internal for reuse.
    - RED: 8 issues (README missing blocks). GREEN: 15 tests in 2 suites. Full `swift test`: 1129 tests in 81 suites passed. Build warnings: only the accepted SwiftPM "missing creator" warning.
  timestamp: 2026-10-09T21:13:13.176602+00:00
- actor: claude-code
  id: 01m4h86nyt8npr38kh7ym802hh
  text: |-
    ### implement — changed
    - evidence: 5 files — README.md, Tests/FoundationModelsKanbanTests/ReadmeExamplesTests.swift (new), Tests/FoundationModelsKanbanTests/DocumentationTests.swift, Tests/FoundationModelsKanbanTests/RepositoryFile.swift, Tests/FoundationModelsKanbanTests/Multitool/CodeModeTests.swift; `swift test --filter "ReadmeExamples|Documentation"` 15 tests passed; `swift test` 1129 tests in 81 suites passed; only the accepted "missing creator" warning.
    - next: /review
  timestamp: 2026-10-09T21:13:15.482106+00:00
- actor: claude-code
  id: 01m4h8dj643wv4cq8pt0bb6qaq
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 5 files
    - test: green — swift test, 1129 tests in 81 suites passed
    - commit: 2b23d72
    - review: clean — 0 findings
  timestamp: 2026-10-09T21:17:00.996394+00:00
depends_on:
- 01M4G9GQ28QA3Z7MYQG9JE3H3Z
- 01M4G9M4WCVGV3X1JAQJ47QCME
- 01M4G9X4JXCBM7XGC5NYQNXGE1
position_column: done
position_ordinal: dc80
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
- [x] `README.md` has a "Get started" section with the six items above, and no `kanban` shell commands.
- [x] Examples 2 and 5 use the four filter documents as Swift `execute` and `subscribe` calls.
- [x] `ReadmeExamplesTests` reads `README.md` from the package root (use `#filePath` to find it), extracts each ```graphql code block, and runs each one against a temporary board with no `.git`. Each response has no `errors`.
- [x] The README says where `.kanban/` goes and what files it holds.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/ReadmeExamplesTests.swift` runs the examples and checks the responses (no `errors`, expected task title).
- [x] `ReadmeExamplesTests` runs each ```graphql code block of `README.md` (a `subscription` document with `subscribe`, other documents with `execute`) and checks that no response has `errors`.
- [x] `swift test --filter ReadmeExamples` and `swift test` pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.