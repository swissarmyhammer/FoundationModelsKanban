import Foundation
import GraphQL
import Testing

@testable import FoundationModelsKanban

/// A test board for the filter queries: a ``ReadinessFixture`` with a board node, and the calls through the public
/// schema that read the selected tasks (plan.md §6, §6.3).
///
/// A test compares the ULID texts of the tasks that a query returns, in the order of the response.
struct TaskQueryFixture {
    /// The selection of a `tasks` query that ``QueryResolverTests/TasksResponse`` reads.
    private static let connectionSelection = "{ totalCount edges { node { id } } pageInfo { hasNextPage endCursor } }"

    /// The `data` part of a response to a `nextTask` query: `{ board { nextTask { id } } }`.
    private struct NextTaskResponse: Decodable {
        /// The `data` object.
        struct DataObject: Decodable {
            /// The `board` object.
            let board: BoardObject
        }

        /// The `board` object.
        struct BoardObject: Decodable {
            /// The next task, or `nil` when no task is next.
            let nextTask: TaskID?
        }

        /// The `data` object.
        let data: DataObject
    }

    /// A task in a response: its `id`.
    private struct TaskID: Decodable {
        /// The full URI of the task.
        let id: String
    }

    /// The board: the default columns and the nodes that a test adds.
    var board = ReadinessFixture()

    /// Makes a board with the default columns and a board node.
    init() {
        let boardNode = BoardNode(fields: ReadinessFixture.fields(), name: QueryFixture.boardName)
        board.graph.update(with: .board(boardNode))
    }

    /// Makes a context that reads the board, with a fixed clock.
    private var context: KanbanContext {
        KanbanContext(
            store: BoardStore.fixture(of: board.graph, inBoard: DependencyMarkersTests.boardKey),
            clock: { DependencyMarkersTests.time }
        )
    }

    /// Runs one GraphQL document against the board through the public schema.
    ///
    /// - Parameter document: The GraphQL document.
    /// - Returns: The response as JSON text.
    /// - Throws: An error that is not a GraphQL error.
    func respond(to document: String) async throws -> String {
        try await PublicSchema().respond(to: document, context: context)
    }

    /// Runs one document, and gives the ``KanbanError`` of its first GraphQL error.
    ///
    /// - Parameter document: The GraphQL document.
    /// - Returns: The error that a resolver threw.
    /// - Throws: An error when the response has no error, or when its first error did not come from a
    ///   ``KanbanError``.
    func kanbanError(of document: String) async throws -> KanbanError {
        let result = try await PublicSchema().execute(request: document, context: context)
        return try #require(result.errors.first?.originalError as? KanbanError)
    }

    /// Reads `Board.tasks` with some arguments.
    ///
    /// - Parameter arguments: The text of the arguments, for example `filter: "#bug"`.
    /// - Returns: The ULID texts of the tasks of the first page, in the order of the response.
    /// - Throws: An error when the response is not the expected JSON.
    func taskULIDs(selectedBy arguments: String) async throws -> [String] {
        let response = try await respond(to: "{ board { tasks(\(arguments)) \(Self.connectionSelection) } }")
        let decoded = try JSONDecoder().decode(QueryResolverTests.TasksResponse.self, from: Data(response.utf8))
        return decoded.data.board.tasks.edges.map { edge in Self.ulidText(ofID: edge.node.id) }
    }

    /// Reads `Board.nextTask`.
    ///
    /// - Parameter filter: The filter, or `nil` for a call with no filter.
    /// - Returns: The ULID text of the next task, or `nil` when no task is next.
    /// - Throws: An error when the response is not the expected JSON.
    func nextTaskULID(withFilter filter: String? = nil) async throws -> String? {
        let arguments = filter.map { text in #"(filter: "\#(text)")"# } ?? ""
        let response = try await respond(to: "{ board { nextTask\(arguments) { id } } }")
        let next = try JSONDecoder().decode(NextTaskResponse.self, from: Data(response.utf8)).data.board.nextTask
        return next.map { task in Self.ulidText(ofID: task.id) }
    }

    /// Gives the ULID text of a task in a response.
    ///
    /// - Parameter id: The full URI of the task.
    /// - Returns: The ULID text: the URI after the `task/` part.
    private static func ulidText(ofID id: String) -> String {
        String(id.dropFirst(QueryFixture.id(ofTask: "").count))
    }
}
