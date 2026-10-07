# FoundationModelsKanban

FoundationModelsKanban is a kanban task graph for Swift. You read and change
the graph with GraphQL: one document goes in, and one `{data, errors}`
response comes out. The package moves the kanban function of the Rust
`swissarmyhammer` tool to Swift. It gives a `KanbanGraph` engine, a
FoundationModels `kanban` tool for in-process agents, and a `kanban`
command-line tool. Each board is an event log in the `.kanban/` directory of
its git repo. The port is not complete. See [plan.md](plan.md) for the design
and the port order.
