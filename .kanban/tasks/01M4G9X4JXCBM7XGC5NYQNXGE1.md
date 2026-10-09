---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4h4ma17ggdkn05fk3s3nthm
  text: |-
    Research:
    - plan.md names the CLI in §6.7 (bullet "In the CLI"), §7.2 (the code comment of `KanbanGraph` "the tool, the CLI, a GUI, and tests use it", and the last bullet), §7.3 (sentence "Thus the CLI, a GUI, and a direct `execute` ..."), §8 (`kanban/ KanbanMain.swift (CLI)`, `swift-argument-parser for the CLI.`), §10 (items 1, 16, 17).
    - §11 has no text that names the CLI now (no CLI test, no `kanban` shell command). Nothing to remove there.
    - §8 lists no CLI test directory. Only the `kanban/` source line and the dependency line name the CLI.
    - README.md names the CLI in the first paragraph ("a `kanban` command-line tool") and in the `sh` block of four `kanban '...'` / `kanban watch '...'` commands.
    - `CIWorkflowTests.workflowLines` already reads a file from the repo root with `#filePath`. The new test shares that code through a new test helper, so that no copy of the root lookup is made.
    - The four filter documents agree with the schema sketch of plan.md §4.1 (`Board.tasks` is a `TaskConnection` with `edges`; `history` takes `filter` and `first`; `Change` has `txn`, `ops`, `actor`, `updates`; `NodeUpdate` has `id`, `type`, `kind`, `fields`).
  timestamp: 2026-10-09T20:10:47.719466+00:00
- actor: claude-code
  id: 01m4h4ryh3fng2w45g6cwt2pb1
  text: |-
    Implementation:
    - plan.md: removed the §6.7 bullet "In the CLI"; removed "the CLI" from the `KanbanGraph` code comment in §7.2 and removed the last §7.2 bullet; §7.3 now reads "Thus a GUI and a direct `execute` do no plan work, also when a `ToolContext` is bound around them" (only the CLI is removed, so the rule about a bound `ToolContext` stays); §8: removed the `kanban/ KanbanMain.swift (CLI)` line and the `swift-argument-parser` line; §10: item 1 has no CLI target, item 16 has no `kanban watch`, item 17 is now "**Tool.**". §11 had no CLI text, so it did not change.
    - README.md: the first paragraph names only the `KanbanGraph` engine and the `kanban` tool. The `sh` block is replaced by four ```graphql blocks, one for each filter document, with the same selection sets. One sentence tells that `KanbanGraph.subscribe` runs the subscription and that the `kanban` tool does not.
    - New test helper `Tests/FoundationModelsKanbanTests/RepositoryFile.swift` (`root`, `text(at:)`, `lines(at:)`). `CIWorkflowTests.workflowLines` now calls it, so the `#filePath` root lookup has one copy.
    - New `Tests/FoundationModelsKanbanTests/DocumentationTests.swift`: one parameterized test over `plan.md` and `README.md` for the pattern, and one parameterized test over the four filter documents that checks exact equality with the body of a ```graphql block.
    - Discovery: a raw string `#"...filter: "#bug..."#` does not compile, because `"#` ends the string. The examples use `##"..."##`.
    - TDD: RED run gave 6 issues (2 pattern cases, 4 block cases). GREEN run: 6 cases pass. Full `swift test`: 1096 tests in 80 suites pass, no compiler warning from the package.
  timestamp: 2026-10-09T20:13:19.779884+00:00
- actor: claude-code
  id: 01m4h4s1aqmt8b6x6rqdy281zq
  text: |-
    ### implement — changed
    - evidence: 5 files — plan.md, README.md, Tests/FoundationModelsKanbanTests/DocumentationTests.swift (new), Tests/FoundationModelsKanbanTests/RepositoryFile.swift (new), Tests/FoundationModelsKanbanTests/CIWorkflowTests.swift; `swift test` 1096 tests in 80 suites pass; `rg -n "\bCLI\b|kanban watch|kanban --schema|kanban '" plan.md README.md` gives no result; no file under Sources/ changed.
    - next: /review
  timestamp: 2026-10-09T20:13:22.647554+00:00
- actor: claude-code
  id: 01m4h4xytmtec4nvpqzr55qe9x
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD — 0 findings (attempted 7, failed 0). The validators reviewed 3 Swift files. README.md and plan.md have no validator, and .kanban/ is in .reviewignore. Manual checks: the commit message of 762ddfe is true for the diff. The acceptance rg gives no result. No file under Sources/ or Package.swift changed. §11 had no CLI text before this commit. README.md has the four graphql blocks with the same selection sets.
    - next: none — the task is in done.
  timestamp: 2026-10-09T20:16:03.924063+00:00
- actor: claude-code
  id: 01m4h4xzqfgmd65p06bnkx47xy
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 5 files
    - test: green — swift test, 1096 tests in 80 suites passed
    - commit: 762ddfe
    - review: clean — 0 findings
  timestamp: 2026-10-09T20:16:04.847567+00:00
depends_on:
- 01M4G9GQ28QA3Z7MYQG9JE3H3Z
position_column: done
position_ordinal: d880
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
- [x] `rg -n "\bCLI\b|kanban watch|kanban --schema|kanban '" plan.md README.md` gives no result.
- [x] `README.md` has the four filter documents above, each in a ```graphql code block.
- [x] No code file changes.

## Tests
- [x] A test in `Tests/FoundationModelsKanbanTests/` (for example `DocumentationTests.swift`) reads `plan.md` and `README.md` from the package root (use `#filePath` to find it) and checks that no line matches `\bCLI\b|kanban watch|kanban --schema|kanban '`.
- [x] The same test checks that `README.md` has the four filter documents in ```graphql code blocks.
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.