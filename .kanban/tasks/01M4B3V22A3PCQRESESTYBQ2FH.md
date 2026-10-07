---
comments:
- actor: wballard
  id: 01m4b4j6p38613q24jzmct7dve
  text: |-
    Research done.
    - The repo has only plan.md and .kanban/. There is no Package.swift.
    - Toolchain: Apple Swift 6.4, target arm64-apple-macosx27.0.
    - ../FoundationModelsCodeContext/Package.swift: named constants for package names (`loggingPackage = "swift-log"`), swift-log `from: "1.15.1"`, siblings by git URL.
    - Siblings (Extras, ACPClient) use swift-argument-parser `from: "1.8.0"`. ACPAgent names it `argumentParserPackage`.
    - EditorKit and AgentViewKit set `swiftLanguageModes: [.v6]` at the package level. Swift 6 mode gives complete strict concurrency checks.
    - ACPClient puts `@main` in a small executable target that calls an `AsyncParsableCommand`.
  timestamp: 2026-10-07T12:14:12.163171+00:00
- actor: wballard
  id: 01m4b4qb74ff9rbw055w16vnwa
  text: |-
    Implementation landed.
    - A Swift target must have one source file or more, so the library cannot be fully empty. The library holds one file, `Log.swift`: `public enum Log` with `Log.kanban`, a swift-log `Logger` with the label `FoundationModelsKanban`. It follows the `Log` pattern of FoundationModelsCodeContext. It gives swift-log a real use, and it gives the scaffold test a real assertion.
    - The CLI is `@main struct KanbanMain: ParsableCommand` with only a `CommandConfiguration`. The default `run()` prints the usage. Step 17 adds the arguments. It is sync now; make it `AsyncParsableCommand` when `execute` comes.
    - `swiftLanguageModes: [.v6]` is set at the package level, as EditorKit and AgentViewKit do.
    - Resolved versions: swift-log 1.16.0, swift-argument-parser 1.8.2. `Package.resolved` is new and not in `.gitignore`.
    - TDD: RED was `swift test` with "cannot find 'Log' in scope". GREEN after `Log.swift`.
  timestamp: 2026-10-07T12:17:00.644439+00:00
- actor: wballard
  id: 01m4b4qcxef22d7wgvy7kgktax
  text: |-
    ### implement — changed
    - evidence: 6 files — Package.swift, Sources/FoundationModelsKanban/Log.swift, Sources/kanban/KanbanMain.swift, Tests/FoundationModelsKanbanTests/ScaffoldTests.swift, README.md, .gitignore (plus generated Package.resolved). Clean `swift build --build-tests`: 0 warnings. `swift test`: 1 test in 1 suite passed, 0 failures. `swift run kanban --help`: prints OVERVIEW and USAGE.
    - next: /review
  timestamp: 2026-10-07T12:17:02.382118+00:00
- actor: wballard
  id: 01m4b4rpa09bmbxrfqak8gvvkh
  text: |-
    ### commit - changed
    - evidence: local commit made, subject "feat: add the Swift package scaffold"
    - next: review
  timestamp: 2026-10-07T12:17:44.768787+00:00
- actor: wballard
  id: 01m4b4v1zrwh8fc3njshf1acvm
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD — 0 findings (0 confirmed, 0 refuted, 7 attempted, 0 failed). The engine reviewed 4 files. No validator matched .gitignore, Package.resolved, or README.md. The .reviewignore file excluded the .kanban/ files.
    - next: The task is in done. No more work is necessary.
  timestamp: 2026-10-07T12:19:02.264267+00:00
- actor: wballard
  id: 01m4b4vbadcm8w79392v08dxak
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 6 files (Package.swift, Log.swift, KanbanMain.swift, ScaffoldTests.swift, README.md, .gitignore)
    - test: green — swift test, 1 passed, 0 warnings
    - commit: 3274bbc
    - review: clean — 0 findings
  timestamp: 2026-10-07T12:19:11.821707+00:00
position_column: done
position_ordinal: '80'
title: Package scaffold
---
## What
Make the Swift package. The basis is plan.md §8 and §10 step 1.
- Create `Package.swift` with swift-tools 6.2 and `.macOS("27.0")`, the same conventions as `../FoundationModelsCodeContext/Package.swift` (named constants for package names, siblings by URL).
- Library target `FoundationModelsKanban` in `Sources/FoundationModelsKanban/`, executable target `kanban` in `Sources/kanban/KanbanMain.swift`, test target `FoundationModelsKanbanTests` in `Tests/FoundationModelsKanbanTests/`.
- Add dependencies that all later steps need now: swift-log, swift-argument-parser. Other dependencies come with their tasks.
- Swift 6 language mode, strict concurrency.
- `README.md` with one paragraph and a pointer to `plan.md`. A root `.gitignore` for `.build/`, `.sah/`, `.shell/`, `.claude/`.

## Acceptance Criteria
- [x] `swift build` succeeds with zero warnings.
- [x] `swift test` runs one Swift Testing test and passes.
- [x] `swift run kanban --help` prints usage.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/ScaffoldTests.swift`: one `@Test` that imports the library.
- [x] Run `swift build && swift test`; expect 0 failures and 0 warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.