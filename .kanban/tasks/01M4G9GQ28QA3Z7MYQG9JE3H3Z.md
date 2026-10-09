---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4h44dwayhwyzhctqahgpptj
  text: 'Research: CLI references are only in Package.swift, Sources/kanban/KanbanMain.swift, Tests/.../CLI/ (2 files), and the doc comment of KanbanGraph.swift ("The tool, the CLI, a GUI..."). KanbanTool.swift, KanbanToolTests.swift and EventTests.swift have no CLI reference (checked with rg -i for cli, command-line, kanban watch, --schema). Coverage map of the 8 CLI tests: board name of an empty repo = KanbanGraphTests.queryOnEmptyRepo; variables JSON = KanbanToolTests.variablesReachDocument; GraphQL error does not throw = KanbanGraphTests.syntaxErrorDoesNotThrow; watch of a second process = SubscriptionTests "A log line that a different process appends sends one Change" and "close() ends each subscription stream"; EX_USAGE argument checks are CLI-only parse rules with no library behavior, so they go away with the CLI. Only-CLI behaviors to move: (1) schemaSDL has "type Task " (and the task asks for not empty + "type Query"); (2) an engine with the real git key reader on a directory outside a git repo throws BoardKeyError.gitFailed at the first call (the library tests only use a fake reader or BoardKey.read directly). Note: task ^m4wccvg-family "BoardKey: a board works in any folder" will change behavior (2) later.'
  timestamp: 2026-10-09T20:02:07.370162+00:00
- actor: claude-code
  id: 01m4h4awv70jrz36gwf6wndhwp
  text: 'Implementation landed. Correction to the research comment: the short id of "BoardKey: a board works in any folder, git is not required" is ^j47qcme. That task will change the new test BoardKeyTests.engineOutsideRepoThrows. Moved coverage: KanbanGraphTests.schemaSDLHasQueryAndTaskTypes (not empty, "type Query ", "type Task ") and BoardKeyTests.engineOutsideRepoThrows (engine with the git key reader throws BoardKeyError.gitFailed outside a git repo). Both new tests pass at once, because they move coverage of behavior that already exists; there is no production change to make them fail first. BoardKeyTests.isGitFailure is a shared private helper; directoryOutsideRepoThrows now uses it too. Discovery: swift-argument-parser stays in both Package.resolved files, because FoundationModelsExtras depends on it. `swift package resolve` (root and IntegrationTests) wrote no change; the two files have the same pins (57 root, 29 IntegrationTests, 0 differ). Deletions are not staged (git rm, then git reset on the paths).'
  timestamp: 2026-10-09T20:05:39.303394+00:00
- actor: claude-code
  id: 01m4h4azv4rn337d52mtxfrcz5
  text: |-
    ### implement — changed
    - evidence: deleted Sources/kanban/KanbanMain.swift, Tests/FoundationModelsKanbanTests/CLI/KanbanCLITests.swift, Tests/FoundationModelsKanbanTests/CLI/KanbanProcess.swift; changed Package.swift, Sources/FoundationModelsKanban/Tool/KanbanGraph.swift, Tests/FoundationModelsKanbanTests/Tool/KanbanGraphTests.swift, Tests/FoundationModelsKanbanTests/Identity/BoardKeyTests.swift. Package.resolved files: no change from swift package resolve, same pins. swift test: 1094 tests in 79 suites passed. swift build --build-tests: only the accepted "missing creator" warning. swift build --build-tests --package-path IntegrationTests: build complete, only accepted mlx warnings. Acceptance rg: no result.
    - next: /review
  timestamp: 2026-10-09T20:05:42.372035+00:00
- actor: claude-code
  id: 01m4h4gdskrfx8qv5n1z4t56z5
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 3 files deleted, 4 files changed
    - test: green — swift test, 1094 tests in 79 suites passed; IntegrationTests build complete
    - commit: 35d0872
    - review: clean — 0 findings
  timestamp: 2026-10-09T20:08:40.499362+00:00
position_column: done
position_ordinal: d780
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
- [x] `Sources/kanban/` and `Tests/FoundationModelsKanbanTests/CLI/` do not exist.
- [x] `Package.swift` has no executable product and no `swift-argument-parser` dependency.
- [x] `rg -n "\bCLI\b|swift-argument-parser|ArgumentParser|KanbanProcess|kanban watch|kanban --schema" Sources Tests Package.swift` gives no result.
- [x] `swift build --build-tests` shows only the accepted warnings.

## Tests
- [x] A library test checks that `KanbanGraph.schemaSDL` is not empty and has `type Query`, if no test does this now.
- [x] `swift test` passes.
- [x] `swift test --package-path IntegrationTests` still builds.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.