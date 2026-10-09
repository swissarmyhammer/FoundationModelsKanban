import FoundationModels
import FoundationModelsExtras
import GraphQL

/// The `kanban` tool of FoundationModels: one GraphQL document goes in, and one `{data, errors}` response comes out
/// (plan.md §7.1, §7.2).
///
/// The tool is a thin layer over a ``KanbanGraph`` that the host makes. The host can give the same engine to other
/// clients, for example a GUI that subscribes, so that all clients in one process share one live graph and one serial
/// gate.
///
/// The tool does not run a subscription. When the selected operation is a `subscription`, the tool gives the error
/// `SUBSCRIPTION_NOT_IN_TOOL`, and the agent then polls `board { history(since:) }`.
public struct KanbanTool: Tool {
    /// The example query of the description. A test runs it, so that it cannot go out of date (plan.md §7.1).
    static let exampleQuery = """
        { board { name nextTask { id shortId title } tasks(filter: "#bug") { edges { node { id title } } } } }
        """

    /// The history example of the description: the newest changes of the tasks. The filter keeps the updates whose
    /// node matches it: `~task` keeps the task updates, and `^id` keeps the updates of one node. A test runs it.
    static let historyExample = """
        { board { history(filter: "~task", first: 5) { txn ops updates { id type kind } } } }
        """

    /// The name of the tool.
    public let name = "kanban"

    /// The short description of the tool: its purpose, the root fields, one example query, and one example of the
    /// history filter. The description does not hold the schema. The agent learns the schema with introspection
    /// (plan.md §12 item 10).
    public let description = """
        Reads and changes the kanban task graph of this repo with GraphQL. Send one GraphQL document in query. \
        The root query fields are board, boards, node, and nodes. Mutations, for example addTask and moveTask, \
        change the board. To learn the schema, query __schema or __type. Send the variables as a JSON object, \
        or as a string that holds a JSON object. Example: \(KanbanTool.exampleQuery) \
        To see the changes, query board history. Its filter keeps the updates whose node matches: ~task for a node \
        type, ^id for one node. Example: \(KanbanTool.historyExample)
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

    /// Runs the document of the arguments against the engine.
    ///
    /// A GraphQL error does not throw: the response has it in `errors`. Variables that are not a JSON object give the
    /// error `INVALID_VARIABLES`, and a selected subscription gives the error `SUBSCRIPTION_NOT_IN_TOOL`. In both cases
    /// the engine runs nothing.
    ///
    /// When a host runs the call with a ``ToolContext``, the engine posts the ACP agent plan of each board whose
    /// tasks the call changed to that context (plan.md §7.3). The model does not get the plan.
    ///
    /// - Parameter arguments: The decoded arguments of the call.
    /// - Returns: The GraphQL response (`{data, errors}`) as JSON text with sorted keys.
    /// - Throws: An I/O fault of the engine, as ``KanbanGraph/execute(query:variables:operationName:)`` tells.
    public func call(arguments: KanbanArguments) async throws -> String {
        if let received = arguments.variablesError {
            return try KanbanError.invalidVariables(received: received).responseJSON()
        }
        if Self.selectsSubscription(arguments.query, named: arguments.operationName) {
            return try KanbanError.subscriptionNotInTool.responseJSON()
        }
        return try await graph.execute(
            query: arguments.query,
            variables: arguments.variables,
            operationName: arguments.operationName,
            postingPlansTo: ToolContext.current
        )
    }

    /// Tells if the operation to run is a subscription.
    ///
    /// The tool selects the operation with the same rule as the engine: the operation that has the name, or the one
    /// operation of the document when the name is `nil`. When the tool cannot select an operation, the engine gives
    /// the error, for example "Must provide operation name" for a document with two operations and no name.
    ///
    /// - Parameters:
    ///   - query: The GraphQL document.
    ///   - operationName: The name of the operation to run, or `nil` when the call sent no name.
    /// - Returns: `true` when the selected operation is a subscription. A document that does not parse, and a
    ///   document whose operation the tool cannot select, give `false`, so that the engine reports the error.
    private static func selectsSubscription(_ query: String, named operationName: String?) -> Bool {
        guard let document = try? parse(source: query) else {
            return false
        }
        let operations = document.definitions.compactMap { definition in definition as? OperationDefinition }
        let selected: OperationDefinition? =
            if let operationName {
                operations.first { operation in operation.name?.value == operationName }
            } else {
                operations.count == 1 ? operations.first : nil
            }
        return selected?.operation == .subscription
    }
}
