import ArgumentParser

/// The `kanban` command-line tool.
///
/// This step of the port (plan.md §10, step 1) gives only the command and its
/// usage text. With no argument, the command prints the usage. Step 17 adds
/// the GraphQL document argument, `--variables`, `watch`, and `--schema`
/// (plan.md §7.2).
@main
struct KanbanMain: ParsableCommand {
    /// The command name and the usage text of the tool.
    static let configuration = CommandConfiguration(
        commandName: "kanban",
        abstract: "Read and change the kanban board of the current repo with GraphQL."
    )
}
