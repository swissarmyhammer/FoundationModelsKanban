import FoundationModels
import GraphQL

/// The `kanban` tool of FoundationModels: one GraphQL document goes in, and one `{data, errors}` response comes out
/// (plan.md §7.1, §7.2).
///
/// The tool is a thin layer over a ``KanbanGraph`` that the host makes. The host can give the same engine to other
/// clients, for example a GUI that subscribes, so that all clients in one process share one live graph and one serial
/// gate.
///
/// The tool does not run a subscription. A `subscription` document gives the error `SUBSCRIPTION_NOT_IN_TOOL`, and
/// the agent then polls `board { history(since:) }`.
public struct KanbanTool: Tool {
    /// The example query of the description. A test runs it, so that it cannot go out of date (plan.md §7.1).
    static let exampleQuery = """
        { board { name nextTask { id shortId title } tasks(filter: "#bug") { edges { node { id title } } } } }
        """

    /// The name of the tool.
    public let name = "kanban"

    /// The short description of the tool: its purpose, the root fields, and one example query. The description does
    /// not hold the schema. The agent learns the schema with introspection (plan.md §12 item 10).
    public let description = """
        Reads and changes the kanban task graph of this repo with GraphQL. Send one GraphQL document in query. \
        The root query fields are board, boards, node, and nodes. Mutations, for example addTask and moveTask, \
        change the board. To learn the schema, query __schema or __type. Send the variables as a JSON object, \
        or as a string that holds a JSON object. Example: \(KanbanTool.exampleQuery)
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
    /// error `INVALID_VARIABLES`, and a subscription gives the error `SUBSCRIPTION_NOT_IN_TOOL`. In both cases the
    /// engine runs nothing.
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
            operationName: arguments.operationName
        )
    }

    /// Tells if the operation to run is a subscription.
    ///
    /// - Parameters:
    ///   - query: The GraphQL document.
    ///   - operationName: The name of the operation to run, or `nil` to look at each operation of the document.
    /// - Returns: `true` when a subscription of the document has the name, or when the name is `nil` and the
    ///   document has a subscription. A document that does not parse gives `false`, so that the engine reports the
    ///   syntax error.
    private static func selectsSubscription(_ query: String, named operationName: String?) -> Bool {
        guard let document = try? parse(source: query) else {
            return false
        }
        return document.definitions.contains { definition in
            guard let operation = definition as? OperationDefinition, operation.operation == .subscription else {
                return false
            }
            return operationName == nil || operation.name?.value == operationName
        }
    }
}
