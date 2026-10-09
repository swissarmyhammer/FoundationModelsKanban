---
assignees:
- claude-code
depends_on:
- 01M4G9GQ28QA3Z7MYQG9JE3H3Z
position_column: todo
position_ordinal: '9680'
title: Remove the CLI from plan.md and README.md
---
## What
The task "Remove the kanban CLI from the code" (^9je3h3z) removes the `kanban` command-line tool from the code. This task removes the CLI from the documents. Do not change the code in this task.

- `plan.md`: remove the CLI from these places:
  - §6.7.
  - §7.2: the last bullet.
  - §7.3: the sentence that starts "Thus the CLI…".
  - §8 (package layout): `Sources/kanban/`, the CLI tests, and the `swift-argument-parser` dependency.
  - §10: items 1, 16 and 17.
  - §11.
- `README.md`: remove the `kanban ...` shell examples and each text that names the CLI.
- In `README.md`, KEEP these four filter example GraphQL documents. Write each one as a plain ```graphql code block, without the `kanban '…'` shell wrapper. The task ^n1yhb0x uses these documents.
  1. `{ tasks(filter: "#bug && @alice") { … } }`
  2. `{ history(filter: "~column", first: 5) { … } }`
  3. `{ history(filter: "^01jabcd") { … } }`
  4. `subscription { changes(filter: "#bug || ~comment") { … } }`
- Keep the selection sets of the four documents as they are now in the README. Each document must be a complete GraphQL document that the schema accepts.

## Acceptance Criteria
- [ ] `rg -n "\bCLI\b|kanban watch|kanban --schema|kanban '" plan.md README.md` gives no result.
- [ ] `README.md` has the four filter documents above, each in a ```graphql code block.
- [ ] No code file changes.

## Tests
- [ ] A test in `Tests/FoundationModelsKanbanTests/` (for example `DocumentationTests.swift`) reads `plan.md` and `README.md` from the package root (use `#filePath` to find it) and checks that no line matches `\bCLI\b|kanban watch|kanban --schema|kanban '`.
- [ ] The same test checks that `README.md` has the four filter documents in ```graphql code blocks.
- [ ] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.