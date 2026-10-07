# FoundationModelsKanban

FoundationModelsKanban is a kanban task graph for Swift. You read and change
the graph with GraphQL: one document goes in, and one `{data, errors}`
response comes out. The package moves the kanban function of the Rust
`swissarmyhammer` tool to Swift. It gives a `KanbanGraph` engine, a
FoundationModels `kanban` tool for in-process agents, and a `kanban`
command-line tool. Each board is an event log in the `.kanban/` directory of
its git repo. The port is not complete. See [plan.md](plan.md) for the design
and the port order.

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
