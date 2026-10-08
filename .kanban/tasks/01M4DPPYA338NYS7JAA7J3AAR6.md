---
comments:
- actor: wballard
  id: 01m4dpswnaxvd6r86fv7s395tw
  text: |-
    Research:
    - Siblings (Ranker, MetadataRegistry, Multitool) put a nested `IntegrationTests/Package.swift` with `.package(path: "..")`, one test target `<Root>IntegrationTests` at `Tests/<Root>IntegrationTests`, and a `private let` constant for the root name. MetadataRegistry and Multitool name the package `<Root>IntegrationTests`.
    - Siblings do NOT commit `IntegrationTests/Package.resolved`: each sibling `.gitignore` has a `Package.resolved` line. This repo commits its root `Package.resolved`, so only the nested file gets a new ignore line.
    - Each sibling `ci.yml` has the same skeleton: `name: CI`, on push to main / pull_request / workflow_dispatch, `concurrency: ci-${{ github.ref }}`, one job `ci` that `uses: swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main` with `integration-package-path: IntegrationTests`. Each sibling also gives `integration-metallib-glob`, because its integration suite loads an MLX model. The kanban smoke test and the ^qjfsmrp model test (SystemLanguageModel) load no MLX model, so this repo does not give that input.
    - Multitool and MetadataRegistry pin `ci.yml` with a root `CIWorkflowTests`; Ranker does not. The card does not ask for it.
    - `KanbanGraph(root:actor:)` on a git repo with no `.kanban/` gives an empty board with the name of the repo directory.
  timestamp: 2026-10-08T12:11:27.275+00:00
- actor: wballard
  id: 01m4dq8wbmtjqbmxa24ajf45aa
  text: |-
    Implementation notes:
    - TDD: the smoke test first expected the board name "Kanban" and failed on the assertion (actual `{"data":{"board":{"name":"smoke-repo"}}}`). The expected response then took the name from `repoName`, and the test passed.
    - DISCOVERY: a fresh resolution of `IntegrationTests/` got the newest `main` of FoundationModelsMetadataRegistry (858f5da), FoundationModelsRanker (6156346) and FoundationModelsExtras (2c37a78). The ROOT sources do not compile against them: `Sources/FoundationModelsKanban/Search/TaskSearch.swift: cannot find type 'TextEmbedding' in scope`. The root builds only because its committed `Package.resolved` pins older revisions. Thus `IntegrationTests/Package.resolved` pins the same revisions as the root file, and it is committed (the root `.gitignore` does not ignore it). This differs from the siblings, which ignore `Package.resolved`. Without it, the CI integration job would fail.
    - Correction of the research comment: `ci.yml` now also gives `integration-metallib-glob: "*Cmlx*/default.metallib"`, so its `jobs` block is the same as the MetadataRegistry `ci.yml`. MLX is in the dependency graph, and the Cmlx `default.metallib` exists in the nested build, so the copy step finds it.
    - No root `CIWorkflowTests` was added (Ranker has none; the card does not ask for it).
    - Root run 1 of 3 had one failure in a test this change does not touch: EventLogTests "The wait for a released lock ends at its deadline while a different descriptor holds the lock" (waited 3.21 s, limit 2.3 s). Runs 2 and 3 passed with no change. Recorded as ^aazpa67.
  timestamp: 2026-10-08T12:19:38.484166+00:00
- actor: wballard
  id: 01m4dq8z9w40j0rm8k9388rp4n
  text: |-
    ### implement — changed
    - evidence: new IntegrationTests/Package.swift, IntegrationTests/Package.resolved, IntegrationTests/Tests/FoundationModelsKanbanIntegrationTests/BoardSmokeTests.swift, IntegrationTests/Tests/FoundationModelsKanbanIntegrationTests/Support/TemporaryGitRepo.swift, .github/workflows/ci.yml; changed README.md. Root: `swift build --build-tests` OK (only the accepted missing-creator warning); `swift test --skip-build` x3: run 1 = 961 tests, 1 issue (flaky EventLogTests lock-deadline test, ^aazpa67), runs 2 and 3 = 961 tests passed; no integration suite in the root runs. IntegrationTests: `swift build --build-tests && swift test` = 1 test passed (only accepted warnings). `ruby -ryaml` parses ci.yml.
    - next: /review
  timestamp: 2026-10-08T12:19:41.500278+00:00
- actor: wballard
  id: 01m4dqk77b854tbec7chm571de
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (87fed58). 0 findings, 0 confirmed, 0 refuted. 7 validator runs, 0 failed. 4 files reviewed. Not reviewed: 6 .kanban/ files (.reviewignore); IntegrationTests/Package.resolved and README.md (no validator matches).
    - next: none. The task is in done.
  timestamp: 2026-10-08T12:25:17.291617+00:00
- actor: wballard
  id: 01m4dqkfj5dkmpcf8hq3h79vmp
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — 6 files (IntegrationTests/Package.swift, IntegrationTests/Package.resolved, BoardSmokeTests.swift, TemporaryGitRepo.swift, .github/workflows/ci.yml, README.md)
    - test: green — root swift test 3 runs, 961 passed each (8.3 s, 9.1 s, 9.6 s); IntegrationTests 1 passed; build warnings only the 2 accepted kinds
    - commit: 87fed58
    - review: clean — 0 findings
  timestamp: 2026-10-08T12:25:25.829873+00:00
position_column: done
position_ordinal: b780
title: IntegrationTests package and CI, the same as the sibling packages
---
## What
A person decided this for ^qjfsmrp. A test against the real on-device model goes in a nested `IntegrationTests/` package, as the `test-partitioning` validator requires. The repo also gets the same shared CI setup as its sibling packages. FoundationModelsKanban has no `.github/workflows/` now.

- Copy the pattern of the siblings. Read `../FoundationModelsMultitool/IntegrationTests/` (Package.swift, Package.resolved, Tests/) and `../FoundationModelsMultitool/.github/workflows/ci.yml`. Also read one more sibling, for example `../FoundationModelsRanker/.github/workflows/ci.yml` and `../FoundationModelsRanker/IntegrationTests/`. Read the shared reusable workflows in `../workflows/.github/workflows/`. Use the same names, the same layout and the same reusable workflow calls. Do not invent a new layout.
- `IntegrationTests/Package.swift`: a separate package that depends on the root package by path (`..`), with its own test target.
- `IntegrationTests/Tests/...`: one smoke test that makes a `KanbanGraph` in a temporary git repo and runs `{ board { name } }`. Thus the package builds and runs on its own. The real-model test of ^qjfsmrp goes in this package later.
- `.github/workflows/ci.yml`: the same as the siblings (unit tests of the root package, the integration package, and the other shared jobs).
- README.md: a short section that tells how to run the integration tests, in ASD-STE100.

## Acceptance Criteria
- [x] `cd IntegrationTests && swift build --build-tests && swift test` passes.
- [x] `.github/workflows/ci.yml` has the same structure and reusable workflow calls as the sibling `ci.yml` files. Only the package names change.
- [x] The root `swift test` does not build or run the IntegrationTests package.

## Tests
- [x] The smoke test in `IntegrationTests/Tests/`.
- [x] Run `swift test` in the root (expect all pass) and `swift test` in `IntegrationTests/` (expect all pass).

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.