---
position_column: todo
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
- [ ] `swift build` succeeds with zero warnings.
- [ ] `swift test` runs one Swift Testing test and passes.
- [ ] `swift run kanban --help` prints usage.

## Tests
- [ ] `Tests/FoundationModelsKanbanTests/ScaffoldTests.swift`: one `@Test` that imports the library.
- [ ] Run `swift build && swift test`; expect 0 failures and 0 warnings.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.