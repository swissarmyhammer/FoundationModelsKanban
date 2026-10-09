---
assignees:
- claude-code
position_column: todo
position_ordinal: '80'
title: Remove the kanban CLI from the code
---
## What
The owner decided to remove the `kanban` command-line tool. The library (`KanbanGraph`, `KanbanTool`) is the only public surface. This task changes only the code and the tests. The task "Remove the CLI from plan.md and README.md" changes the documents.

- Delete `Sources/kanban/KanbanMain.swift` and the directory `Sources/kanban/`.
- `Package.swift`: remove `cliName`, the `.executable` product, the `.executableTarget`, the `argumentParserPackage` constant, and the `swift-argument-parser` dependency. Remove the comments that name the CLI.
- Update `Package.resolved` and `IntegrationTests/Package.resolved` (run `swift package resolve`). Keep the two files with the same pins.
- Delete `Tests/FoundationModelsKanbanTests/CLI/KanbanCLITests.swift`, `Tests/FoundationModelsKanbanTests/CLI/KanbanProcess.swift`, and each other file in `Tests/FoundationModelsKanbanTests/CLI/`. Before the delete, find each behavior that only a CLI test covers (for example, `--schema` prints the SDL). Move that check to a library test, for example `KanbanGraph.schemaSDL` in `Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift`.
- Remove the doc comments that name the CLI in `Sources/FoundationModelsKanban/Tool/KanbanGraph.swift` and `Sources/FoundationModelsKanban/Tool/KanbanTool.swift`.
- Remove the CLI references in the test files, for example `Tests/.../Tool/KanbanGraphTests.swift`, `Tests/.../Tool/KanbanToolTests.swift`, `Tests/.../Events/EventTests.swift`.
- Do not change `plan.md` or `README.md` in this task.

## Acceptance Criteria
- [ ] `Sources/kanban/` and `Tests/FoundationModelsKanbanTests/CLI/` do not exist.
- [ ] `Package.swift` has no executable product and no `swift-argument-parser` dependency.
- [ ] `rg -n "\bCLI\b|swift-argument-parser|ArgumentParser|KanbanProcess|kanban watch|kanban --schema" Sources Tests Package.swift` gives no result.
- [ ] `swift build --build-tests` shows only the accepted warnings.

## Tests
- [ ] A library test checks that `KanbanGraph.schemaSDL` is not empty and has `type Query`, if no test does this now.
- [ ] `swift test` passes.
- [ ] `swift test --package-path IntegrationTests` still builds.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.