---
assignees:
- claude-code
comments:
- actor: claude-code
  id: 01m4egf19zg6gzabxzbe7dsmr9
  text: |-
    Research done.
    - Peers: MetadataRegistry reads ci.yml through `#filePath` and line matching (no YAML library); Multitool uses a local `RepositoryFile` helper; Extras uses `FixtureSupport.FixtureFile`. This package has no such helper, so the test uses the MetadataRegistry approach: `#filePath`, split into lines, trim, compare.
    - `.github/workflows/ci.yml` already has the same `on:`, `concurrency:` and `jobs:` block as MetadataRegistry (one `ci:` job, two inputs). No change to `jobs:` is necessary.
    - The integration package runs `mlx-community/Qwen3.8-27B-mxfp4` through Extras `PooledModel` (IntegrationTests/Tests/FoundationModelsKanbanIntegrationTests/ModelVariablesTests.swift). The ci.yml comment still says "an MLX embedder"; update it.
    - No ARCHITECTURE.md and no swift-format config at the root. Existing tests use 4-space indent.
  timestamp: 2026-10-08T19:39:54.559876+00:00
- actor: claude-code
  id: 01m4egmrkeny18hrvvcn5e7sp4
  text: |-
    Implementation done.
    - RED: the first run expected `integration-metallib-glob: "*Cmlx*/mlx.metallib"`, which ci.yml does not have. 1 issue on `lines.contains(line)`, 3 other tests passed. Then the expected value was set to `"*Cmlx*/default.metallib"`: 4 tests, 6 cases, pass.
    - Mutation run: ci.yml was changed for one run (`uses: ...@v1`, `integration-package-path: Tests`, added `integration-gate-env: RUN_INTEGRATION`). 3 issues: the `uses:` line, the package path, and the other integration-* input. Then ci.yml was put back (`git diff` shows only the comment change).
    - `private static let requiredLines` compiles as `@Test(arguments:)`; Extras used internal, but private works.
    - ci.yml comment now names `mlx-community/Qwen3.8-27B-mxfp4`, Extras `PooledModel`, and `CIWorkflowTests`. `jobs:` block not changed. `ruby -ryaml` loads the file.
  timestamp: 2026-10-08T19:43:02.254974+00:00
- actor: claude-code
  id: 01m4egmtc48z832w0eb6aw4ks6
  text: |-
    ### implement — changed
    - evidence: 2 files — Tests/FoundationModelsKanbanTests/CIWorkflowTests.swift (new), .github/workflows/ci.yml (comment only). `swift build --build-tests` OK (only the accepted SwiftPM "missing creator" warning). `swift test --skip-build` 3 times: 1016 tests in 72 suites passed each time (about 13 s each). YAML loads with ruby.
    - next: /review
  timestamp: 2026-10-08T19:43:04.068817+00:00
- actor: claude-code
  id: 01m4egvj6j8vscbp3jx43ysw1g
  text: |-
    ### review — clean
    - evidence: review sha HEAD~1..HEAD (2cee34a). 0 findings, 0 confirmed, 1 refuted, 7 attempted, 0 failed. The review examined 2 files. An ignore rule excluded 4 .kanban files.
    - next: none. The task is in done.
  timestamp: 2026-10-08T19:46:45.074101+00:00
- actor: claude-code
  id: 01m4egvr74qbj2612r0e92w181
  text: |-
    ### finish iteration 1 — clean
    - implement: changed — Tests/FoundationModelsKanbanTests/CIWorkflowTests.swift (new), .github/workflows/ci.yml (comment)
    - test: green — swift test 3 runs, 1016 passed each (7.7 s, 7.7 s, 7.6 s); build warnings only the 2 accepted kinds
    - commit: 2cee34a
    - review: clean — 0 findings
  timestamp: 2026-10-08T19:46:51.236768+00:00
position_column: done
position_ordinal: c280
title: 'CIWorkflowTests: pin the CI delegation, the same as the sibling packages'
---
## What
A person asked on 2026-10-08 that CI is set up like the peer packages. Router, Extras, ACPAgent, MetadataRegistry and Multitool each have a `CIWorkflowTests` unit test that reads `.github/workflows/ci.yml` and pins the call to `swissarmyhammer/workflows/.github/workflows/swift-ci.yaml@main` and its inputs. FoundationModelsKanban has no such test.

- Add `Tests/FoundationModelsKanbanTests/CIWorkflowTests.swift`. Copy the pattern of the peers (read `../FoundationModelsMetadataRegistry/Tests/FoundationModelsMetadataRegistryTests/CIWorkflowTests.swift` and `../FoundationModelsMultitool/Tests/FoundationModelsMultitoolTests/CIWorkflowTests.swift`). Pin: the reusable workflow `uses:` line, `integration-package-path: IntegrationTests`, `integration-metallib-glob: "*Cmlx*/default.metallib"`, the triggers, and that no input sets an environment variable to select a suite. Add no new package dependency (parse the YAML the same way the peers do).
- Update the comment in `.github/workflows/ci.yml`: the integration package now runs a real Qwen 3.8 model (`mlx-community/Qwen3.8-27B-mxfp4`) through Extras `PooledModel`, which needs the metallib, and `CIWorkflowTests` pins the delegation. Keep the `jobs:` block the same unless a peer difference requires a change.

## Acceptance Criteria
- [x] `CIWorkflowTests` passes, and fails when an input or the `uses:` line in `ci.yml` changes.
- [x] `ci.yml` has the same `jobs:` structure as the peers.

## Tests
- [x] `Tests/FoundationModelsKanbanTests/CIWorkflowTests.swift`.
- [x] Run the full `swift test`; expect all pass.

## Workflow
- Use `/tdd` — write failing tests first, then implement to make them pass.