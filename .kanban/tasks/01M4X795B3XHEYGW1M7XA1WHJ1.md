---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m50vjv48f08apxdbx8ynkgj6
  text: |-
    Research done.
    - The old Rust skill (../swissarmyhammer/builtin/skills/kanban/SKILL.md) uses op-style JSON and includes partials (record-progress, step-record, card-report) that ../skills does not have. ../skills has only `_partials/sah-findings-are-requirements.md`. The skills are Stencil templates: the new skill must not have `{{`, `{%` or `{#` in a code block.
    - ../skills skills call code-mode verbs in ```js blocks (`tools.shell.execute`), so the new skill uses ```js blocks with `tools.kanban({ query, variables })`, each followed by a ```json block with the exact result.
    - No schema field gives the session actor. `addComment` with no `actor` gives `author` = the session actor, so the skill uses that comment to learn "me" before `assignTask`.
    - Warnings are `extensions.warnings: [{message, code}]`. Codes: PRIORITY_IS_POSITION, ORDINAL_IGNORED, REMOVED_PARAMETER, DEPENDENCY_TASK_NOT_FOUND, DEPENDENCY_BOARD_NOT_FOUND.
    - VirtualTag cases: READY, BLOCKED, CONFLICT, DELETED, DONE, HIGH, MEDIUM, LOW.
    - Design for a missing ../skills (CI): keep a full copy of the skill at Documentation/kanban/SKILL.md in this repo. The doc test runs the examples of that copy on a temporary git repo. A second test compares the copy with ../skills/skills/kanban/SKILL.md when that file exists; with no file, the test has nothing to compare and passes (no skip). The copy is outside Tests/ so that SwiftPM gives no "unhandled file" warning.
  timestamp: 2026-10-15T22:40:33.416934+00:00
- actor: claude-code
  id: 01m50wa7gs18q0x1s6g0ayhs13
  text: |-
    Implementation landed.
    - ../skills: new `skills/kanban/SKILL.md` (424 lines), committed local only as c6e735e (feat(skills): add the kanban skill for the Swift kanban). Only `skills/kanban/` was staged. Not pushed. The old Rust skill in ../swissarmyhammer is not changed.
    - This repo (not committed, the orchestrator commits): new `Documentation/kanban/SKILL.md` (the copy, the same bytes as the ../skills file), new `Tests/FoundationModelsKanbanTests/KanbanSkillTests.swift` (9 tests). Changed: `RepositoryFile.swift` (new `fencedBlocks(at:)` and `FencedBlock`; `codeBlocks` uses it), `ReadmeExamplesTests.swift` (`ExampleBoard` and `sortedJSON` are internal now, for reuse), `Multitool/CodeModeTests.swift` (new `run(_:with:)` that takes any tool).
    - Decision for a missing ../skills (CI): the copy at `Documentation/kanban/SKILL.md` is the file that the doc test runs. The test `copyIsSkillsRepoFile` compares the copy with `../skills/skills/kanban/SKILL.md` when that file exists; when it does not exist, the test has nothing to compare and passes (no skip). Rule for later edits: change both files together. The copy is outside `Tests/`, so SwiftPM gives no "unhandled file" warning.
    - The doc test runs each ```js block (a runCode script that calls `tools.kanban`) in skill order on one board in a temporary git repo (`ReadmeExamplesTests.ExampleBoard`), and compares the sorted JSON result with the ```json block after it. A recording wrapper of `KanbanTool` keeps each response, and a second test checks that no response has `extensions.rewrites` (the examples use the canonical names). Other tests: frontmatter keys, no `{"op":`, the virtual tag table equals `VirtualTag.allCases`, each BLOCKING line says "ordinary tag", no Stencil tag start in a code block.
    - I checked that the result test is not vacuous: a wrong expected value made it fail; then I put the correct value back.
    - Facts found: no schema field gives the session actor; an `addComment` with no `actor` gives it as `author`, so the skill uses that. `addTask` with no `assignees` assigns the session actor when the actor was on the board before the call, so `@me` lists those tasks too. Code blocks inside list items (indented fences) do not match the fence regex of `RepositoryFile`, so the process steps are `###` subsections.
    - Tool use note: one edit of the skill used a python script in the shell to move sections; all later edits used the file tools.
    - Validators: I read the generic rule bodies and the Swift rules of the dump in full; I skipped the per-language tool details for Dart, Go, Python, Rust, and TypeScript, because no file of those languages changed.
  timestamp: 2026-10-15T22:53:19.769174+00:00
- actor: claude-code
  id: 01m50waab4yg0zgx84r5gt87zf
  text: |-
    ### implement — changed
    - evidence: ../skills commit c6e735ee31334ad1d1d913cd7d6ce6459ca1f829 (skills/kanban/SKILL.md, 424 lines). This repo: 2 new files (Documentation/kanban/SKILL.md, Tests/FoundationModelsKanbanTests/KanbanSkillTests.swift), 3 changed files (Tests/FoundationModelsKanbanTests/RepositoryFile.swift, ReadmeExamplesTests.swift, Multitool/CodeModeTests.swift). `swift test --filter KanbanSkillTests`: 9 of 9 pass. Full `swift test`: 1539 tests in 122 suites pass, 0 failed, 0 skipped; `swift build --build-tests` shows only the accepted mlx Metal and "missing creator" warnings.
    - next: /review. The orchestrator commits this repo. Do not stage Package.resolved or .kanban/mcp.17281.log.
  timestamp: 2026-10-15T22:53:22.660997+00:00
- actor: claude-code
  id: 01m50wjjwt1qqmww7zrb3zwk7j
  text: |-
    ### test — green
    - evidence: swift build complete, only the SwiftPM "missing creator" warning. swift test: 1539 tests in 122 suites passed, 0 failed, 0 skipped. Suite "Kanban skill: the examples run against the Swift tool" passed. IntegrationTests (with the scratch path): 3 tests in 3 suites passed. cmp of Documentation/kanban/SKILL.md and skills/skills/kanban/SKILL.md: byte-equal. Load was about 87 to 90. No time limit failure. One full run only.
    - next: review
  timestamp: 2026-10-15T22:57:53.562458+00:00
- actor: claude-code
  id: 01m50wkc57hvcc5m8mbma1g3d4
  text: |-
    ### commit — changed
    - evidence: local commit of Documentation/kanban/SKILL.md, KanbanSkillTests.swift, RepositoryFile.swift, ReadmeExamplesTests.swift, CodeModeTests.swift, and the changed .kanban/tasks files. Package.resolved and .kanban/mcp.17281.log are not staged.
    - next: review
  timestamp: 2026-10-15T22:58:19.431616+00:00
depends_on:
- 01M4X6X6PS5P524DW45RBSSWN2
- 01M4X71FVFN9HYJ19VJ71VWV3B
- 01M4X71QQPKCEJ5490KD8R4C92
- 01M4X72259P5THWWNQR66JA3DT
- 01M4X7471GDT9W0J6PWBQTQ6H3
- 01M4X74RAFJPG6D09RQPE2292H
- 01M4X752F1NS2G82A6NY8NR5V3
- 01M4X75M84AR2XGXKRBC37B5B9
- 01M4X75W4D14M1WDAJYTJWB41H
- 01M4X77PG6CNGC9JZYCN9WJGTY
- 01M4X77ZET324X8HKM7HRJ0KK0
- 01M4X6XKP0Y832GDRHQ1MG22VF
position_column: doing
position_ordinal: '80'
title: Write a new kanban skill in ../skills for the Swift kanban
---
## What
The user: "make a revised version of the kanban skill and put it in ../skills. It needs to match the semantics of this new Swift kanban."

- Target file: `/Users/wballard/github/swissarmyhammer/skills/skills/kanban/SKILL.md` (a new folder). The repo `../skills` has skills such as `skills/commit/SKILL.md`. Copy its frontmatter style: `name`, `description`, `license`, `compatibility`, `metadata`. Do the work in that repo and commit it there.
- Source to revise: the old Rust skill `../swissarmyhammer/builtin/skills/kanban/SKILL.md` (202 lines, op-style JSON calls). Do not change the old file.
- The new skill uses the Swift tool: one function in code mode, `tools.kanban({ query, variables })`, with GraphQL documents (see plan.md §9 and §4 for the tool shape). It describes the DECIDED behavior in divergence.md. Where divergence.md differs from the Rust behavior or from plan.md, use divergence.md.
- Write the skill in ASD-STE100 Simplified Technical English. Keep it compact and example-driven. Use the canonical names in each example (the forgiving names are a safety net, not the way to teach).

The skill must cover at least:
- Get the next task: `nextTask` (board order and dependencies). There is no claim operation (M3: agents coordinate themselves). To take a task, assign yourself and move it. Each session has its own actor (M4), so `undo` stays in the session.
- Task refs and the board that they go to: a full `kanban://<board-key>/task/<id>` URI reaches any board; short forms (full ULID, 7-character short id, `^short`, `<type>/<id>` (R18), title slug (C3)) always name the current board or the `board:` board. A short form never reaches another board. A shared short id or title slug resolves to the first match (live before tombstone, lowest ULID); an ambiguous ULID prefix gives `AMBIGUOUS_ID` with the matching ids.
- Dependencies: `dependsOn` (input synonym `blockedBy`), cross-board URIs, task URLs in the body as markers, `blockedBy` (output), `unresolvedDependsOn`. A task URL in a code block, inline code, or a heading does not count. A missing target blocks the task and gives a warning.
- Virtual tags: READY, BLOCKED, CONFLICT, DELETED, DONE, HIGH, MEDIUM, LOW. There is no BLOCKING. `#BLOCKING` is an ordinary tag (C1).
- The filter DSL: `#tag`, `@actor`, `^id` (also `^<title-slug>` and `^^short`), `%column`, `~type`, URL atoms, and the operators.
- Priority is the position in the column: use `moveTask` with `before`/`after`. A `priority` input moves the task by the K15 table, with a warning.
- Read `extensions.warnings` after each call.
- Undo and redo with `txn` (the session actor).
- The board: one board for each worktree, at the worktree top, committed with the code (M6 final). Not in a git repo gives `NOT_A_REPO`. An old Rust `.kanban/` gives `INCOMPATIBLE_BOARD`; tell the user to remove it.
- The forgiving names: an agent can be "close enough", but the examples use the canonical names.

Each example in the skill must run against the Swift tool. Add a doc test in this Swift repo that reads the skill file and runs each GraphQL example through the package GraphQL engine (or `KanbanTool`), in the same way as the README example tests (T/ReadmeExamplesTests.swift, or the file that the task `^n1yhb0x` added). The test uses temporary fixture folders, never the `.kanban/` of this repo (it is a Rust board).

## Acceptance Criteria
- [x] `/Users/wballard/github/swissarmyhammer/skills/skills/kanban/SKILL.md` exists, with the same frontmatter style as `skills/commit/SKILL.md`, and is committed in `../skills`.
- [x] No op-style JSON call (`{"op": ...}`) remains in the skill.
- [x] No text names BLOCKING as a virtual tag.
- [x] Each GraphQL example runs and gives the shape that the skill shows.
- [x] A doc test or script in this Swift repo checks the examples.
- [x] The skill text is in ASD-STE100 Simplified Technical English.

## Tests
- [x] A doc test in T/ that extracts each GraphQL example from the skill and runs it on a temporary fixture board.
- [x] Tests use temporary fixture folders. Never use the `.kanban/` of this repo (it is a Rust board).
- [x] `swift test` passes.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.