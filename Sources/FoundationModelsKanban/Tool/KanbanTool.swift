import FoundationModels
import FoundationModelsExtras

/// The `kanban` tool of FoundationModels: one GraphQL document goes in, and one `{data, errors}` response comes out
/// (plan.md §7.1, §7.2).
///
/// The tool is a thin layer over a ``KanbanGraph`` that the host makes. The host can give the same engine to other
/// clients, for example a GUI that subscribes, so that all clients in one process share one live graph and one serial
/// gate.
///
/// The tool does not run a subscription. When the selected operation is a `subscription`, the tool gives the error
/// `SUBSCRIPTION_NOT_IN_TOOL`, and the agent then polls `board { history(since:) }`.
///
/// The tool is a ``GraphQLEndpointTool`` (KANBAN-5, EXTRAS-9 rule 1): its one endpoint is the engine that it runs on,
/// so a host gives a client the `kanban` endpoint over the same live graph and the same serial gate.
public struct KanbanTool: GraphQLEndpointTool {
    /// The example query of the description. A test runs it, so that it cannot go out of date (plan.md §7.1).
    static let exampleQuery = """
        { board { name nextTask { id shortId title } tasks(filter: "#bug") { edges { node { id title } } } } }
        """

    /// The history example of the description: the newest changes of the tasks. The filter keeps the updates whose
    /// node matches it: `~task` keeps the task updates, and `^id` keeps the updates of one node. A test runs it.
    static let historyExample = """
        { board { history(filter: "~task", first: 5) { txn ops updates { id type kind } } } }
        """

    /// The timeline example of the description (divergence.md §23): the newest entries of the history of one task,
    /// with the columns of each move and the change of each field. A test runs it.
    static let timelineExample = """
        { board { tasks(first: 1) { nodes { timeline(first: 5) { kind at from { name } to { name } \
        field { name before after } } } } } }
        """

    /// The example of the stored local ref form `<type>/<id>` in the description (divergence.md R18). The log stores
    /// each ref to a node of the same board in this form, and the resolver accepts it as a ref.
    static let storedLocalRefExample = "column/todo"

    /// The example of the title slug of a task as a ref in the description (divergence.md Q25, C3): the slug of the
    /// title `Fix login bug`.
    static let titleSlugRefExample = "fix-login-bug"

    /// The skill of the trigger of ``columnTriggerExample``.
    static let columnTriggerSkill = "triage"

    /// The column trigger example of the description (divergence.md §22): it writes the trigger and `next` into the
    /// frontmatter of the body of the column `todo`. A test runs it.
    static let columnTriggerExample = """
        mutation { updateColumn(input: { id: "todo", trigger: "\(columnTriggerSkill)", next: false }) { trigger next } }
        """

    /// What the agent does in place of a subscription, for the `SUBSCRIPTION_NOT_IN_TOOL` error: it reads the
    /// changes again with the history query (EXTRAS-9 rule 10).
    static let subscriptionHint = "Use board { history(since: <txn>) } to get the changes after a known transaction."

    /// The name of the tool.
    public let name = "kanban"

    /// The short description of the tool: its purpose, the root fields, one example query, one example of the
    /// history filter, the timeline of one task (divergence.md §23), the dependencies between repos (divergence.md
    /// R17), the ref forms (divergence.md R18, Q25, C3, E4), the version check of `updateTask` (divergence.md §18),
    /// the warnings, the transaction of the response (divergence.md §19), the list mutations (divergence.md §20),
    /// `rejectTask` (divergence.md §21), the column trigger (divergence.md §22), and the board place. The description
    /// does not hold the schema. The agent learns the schema with introspection (plan.md §12 item 10).
    public let description = """
        Reads and changes the kanban task graph of this repo with GraphQL. Send one GraphQL document in query. \
        The root query fields are board, boards, node, nodes, and checkLinks. Mutations, for example addTask and \
        moveTask, change the board. Each mutation takes one required input object: verbNoun(input: { ... }), for \
        example initBoard(input: {}) or undoChange(input: { txn: <id> }). To learn the schema, query __schema or \
        __type. Send the variables as a JSON object, or as a string that holds a JSON object. Example: \
        \(KanbanTool.exampleQuery) \
        To see the changes, query board history. Its filter keeps the updates whose node matches: ~task for a node \
        type, ^id for one node. Example: \(KanbanTool.historyExample) \
        To see the history of one task, query Task.timeline: each column move, field change, and comment change, \
        newest first, with the actor and the txn. Page with first and after. Example: \
        \(KanbanTool.timelineExample) \
        A task can depend on a task in a different repo: put the full \(SchemaDescription.taskURIForm) URI in \
        dependsOn, or put that task URL in the body. A short ref, for example ^short, or the stored form type/id, \
        for example \(KanbanTool.storedLocalRefExample) or task/^short, names a node of the board that the call \
        changes: the current board, or the board that the board field or a full id URI names. A task ref can also \
        be the title slug of a task, for example \(KanbanTool.titleSlugRefExample); a ULID or a short id wins over \
        a title slug, and in node(id:) each other slug wins over it. When two tasks share a short id or a title \
        slug, the call uses the first and gives a warning. A filter takes ^id, ^^short, or ^<title slug>, and \
        matches each task that has it. Task.unresolvedDependsOn shows each dependency that no loaded board has. \
        checkLinks gives the class of each stored link: \
        \(LinkStatus.allCases.map(\.rawValue).joined(separator: ", ")). A link with an old board name still works, \
        and the response gives the warning \(OldBoardName.warningCode). The repairLinks mutation rewrites each \
        \(LinkStatus.oldName.rawValue) link to the current name; repairLinks(input: { dryRun: true }) only lists the \
        changes. Each node has a version. To change a task only when no other change came first, give its version as \
        ifVersion to updateTask; a different version gives STALE_WRITE with the current version, and the call writes \
        nothing. Read the warnings in extensions.warnings. The response of a call that writes gives its transaction \
        in extensions.txn; give it as txn to undoChange to reverse the call. To change many tasks in one \
        transaction, give a list of ids as id to moveTasks, deleteTasks, or undeleteTasks. To send a task back with a \
        comment to the agent, use rejectTask(input: { id, comment }): one transaction adds the comment and moves the \
        task, by default to the column before its column. \
        The trigger of a column is YAML frontmatter at the top of the column body: trigger is the skill that runs \
        when a task enters the column, and next tells if the task then moves to the next column. Give trigger and \
        next to addColumn or updateColumn, and read Column.trigger and Column.next. Example: \
        \(KanbanTool.columnTriggerExample) \
        The board is in .kanban at the top of a git worktree. \
        Outside git, the board is in the nearest folder up that has a .kanban folder, else in the working directory, \
        and its key is its board ID. The collectBoards mutation combines other .kanban folders, for example a board \
        in a subfolder (warning \(SubfolderBoard.warningCode)), into one target board: \
        collectBoards(input: { sources: [...] }); undoChange does not reverse it. A .kanban folder of the old Rust \
        kanban gives INCOMPATIBLE_BOARD. \
        boards leaves out a related repo with a Rust .kanban folder and gives the warning INCOMPATIBLE_BOARD.
        """

    /// The schema of the arguments: ``KanbanArguments/generationSchema``.
    public var parameters: GenerationSchema {
        KanbanArguments.generationSchema
    }

    /// The engine that runs each document.
    private let graph: KanbanGraph

    /// Makes the tool over an engine that the caller made.
    ///
    /// - Parameter graph: The engine. The tool does not close it.
    public init(graph: KanbanGraph) {
        self.graph = graph
    }

    /// The endpoints of the tool: the one engine that the tool runs on. The engine is an actor, so each copy of the
    /// tool gives the same instance, with the same serial gate.
    public var graphQLEndpoints: [any GraphQLEndpoint] {
        [graph]
    }

    /// Runs the document of the arguments against the engine.
    ///
    /// A GraphQL error does not throw: the response has it in `errors`. Variables that are not a JSON object give the
    /// error `INVALID_VARIABLES`, and a selected subscription gives the error `SUBSCRIPTION_NOT_IN_TOOL`. In both cases
    /// the engine runs nothing.
    ///
    /// When a host runs the call with a ``ToolContext``, the engine posts the ACP agent plan of each board whose
    /// tasks the call changed to that context (plan.md §7.3). The model does not get the plan.
    ///
    /// The output is the response of the engine as it is, so the agent sees each warning of the call in
    /// `extensions.warnings` (plan.md §4.4).
    ///
    /// The model has no client, so the call has no viewer: it reaches each board, the same as before the endpoint.
    ///
    /// - Parameter arguments: The decoded arguments of the call.
    /// - Returns: The GraphQL response (`{data, errors}`) as JSON text with sorted keys.
    /// - Throws: An I/O fault of the engine, as ``KanbanGraph/execute(query:variables:operationName:)`` tells.
    public func call(arguments: KanbanArguments) async throws -> String {
        let context = ToolContext.current
        return try await GraphQLTool.answer(arguments.request, subscriptionHint: Self.subscriptionHint) {
            query, variables, operationName in
            try await graph.execute(
                query: query,
                variables: variables,
                operationName: operationName,
                viewer: nil,
                postingPlansTo: context
            )
        }
    }
}
