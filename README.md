# FoundationModelsKanban

FoundationModelsKanban is a kanban task graph for Swift. You read and change
the graph with GraphQL: one document goes in, and one `{data, errors}`
response comes out. The package moves the kanban function of the Rust
`swissarmyhammer` tool to Swift. It gives a `KanbanGraph` engine, a
FoundationModels `kanban` tool for in-process agents, and a `kanban`
command-line tool. Each board is an event log in the `.kanban/` directory of
its git repo. The port is not complete. See [plan.md](plan.md) for the design
and the port order.

## Run the tests

A package boundary separates the two test suites:

- `swift test` runs the unit suite. The unit tests need no model and no
  network.
- `swift test --package-path IntegrationTests` runs the integration suite in
  the nested [`IntegrationTests`](IntegrationTests) package. These tests use
  real external systems, for example a real git repo. A test that uses the
  on-device model needs a Mac with Apple Intelligence turned on.

The package structure selects the suite. No environment variable changes it.
The root `Package.swift` declares one test target, the unit suite, so a root
`swift test` cannot run an integration test. The integration target is only in
the nested package. CI runs the two suites through the shared `swift-ci`
workflow (see [`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

The nested package commits its own `Package.resolved`, with the same pins as
the root `Package.resolved`. When you change the root pins, copy them to
`IntegrationTests/Package.resolved`.

## Known build warnings

A clean `swift build --build-tests` shows two kinds of warnings. These
warnings are known, and the build check accepts them:

1. The SwiftPM warning
   `warning: missing creator for mutated node: (.../mlx-swift_Cmlx.bundle/Contents/MacOS)`.
2. The `-Wc++17-extensions` warnings from the Metal sources in
   `.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated/metal/`.

Both warnings come from a dependency chain:
`FoundationModelsMetadataRegistry` → `FoundationModelsExtras` → `mlx-swift`.
The `searchTasks` query uses `FoundationModelsMetadataRegistry`.

The root package cannot fix these warnings. SwiftPM does not let a root
package set the build settings of the targets of a dependency. Also, the
registry has no product without the MLX dependency. The fix must come from
the dependency chain or from SwiftPM.

These two warnings are the only accepted warnings. A warning from the
sources of this package, or a different warning from a dependency, still
fails the build check.
