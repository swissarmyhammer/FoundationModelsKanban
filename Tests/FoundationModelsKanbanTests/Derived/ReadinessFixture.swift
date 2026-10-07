import Foundation
import Testing

@testable import FoundationModelsKanban

/// A test board for the readiness and virtual tag tests: a graph with the default columns, and tasks that the tests
/// add (plan.md §6).
///
/// The time, the board keys, and the ULID, URL, and URI helpers are the ones of ``DependencyMarkersTests``.
struct ReadinessFixture {
    /// The slug of the first column.
    static let todo = "todo"

    /// The slug of a column between the first column and the terminal column.
    static let doing = "doing"

    /// The slug of the terminal column of the default columns.
    static let done = "done"

    /// The slugs of the default columns of `initBoard`. The order of a column is its index (plan.md §6).
    static let defaultColumns = [todo, doing, "review", done]

    /// The ULID text of the first test task.
    static let first = "01KT6R6HR3KJT6JVNDRAJV8V4T"

    /// The ULID text of the second test task.
    static let second = "01KT6R7Q0ZB4X1N9C2D3E4F5G6"

    /// The ULID text of the third test task.
    static let third = "01KT6SAMJAJ40XVQ9Y7JRAJ9VG"

    /// The ULID text of the fourth test task.
    static let fourth = "01KT6TB8XW3N5P7Q9R1S3T5V7X"

    /// The ULID text of a task that the graph does not have.
    static let ghost = "01KT6VC9YZ4M6N8P0Q2R4S6T8W"

    /// The graph of the board.
    var graph = Graph()

    /// Makes a board with the default columns.
    init() {
        for (order, slug) in Self.defaultColumns.enumerated() {
            addColumn(withSlug: slug, order: order)
        }
    }

    /// Gives the unresolved edge to a task of this board, as replay gives it.
    ///
    /// - Parameter text: The ULID text of the task.
    /// - Returns: The edge.
    /// - Throws: An error when the text is not a ULID.
    static func edge(toTask text: String) throws -> EdgeTarget {
        .unresolved(.local(.task(try DependencyMarkersTests.ulid(of: text))))
    }

    /// Gives the body and the time values of a test node.
    ///
    /// - Parameters:
    ///   - body: The body of the node.
    ///   - isDeleted: `true` when the node is a tombstone.
    ///   - hasConflict: `true` when the body has a conflict block.
    /// - Returns: The fields.
    static func fields(body: String = "", isDeleted: Bool = false, hasConflict: Bool = false) -> NodeFields {
        let time = DependencyMarkersTests.time
        return NodeFields(
            body: body,
            created: time,
            updated: time,
            deleted: isDeleted ? time : nil,
            hasConflict: hasConflict
        )
    }

    /// Adds a column, or replaces the column with the same slug.
    ///
    /// - Parameters:
    ///   - slug: The slug of the column.
    ///   - order: The sort key of the column.
    ///   - isDeleted: `true` when the column is a tombstone.
    mutating func addColumn(withSlug slug: String, order: Int, isDeleted: Bool = false) {
        graph.update(with: .column(ColumnNode(slug: slug, fields: Self.fields(isDeleted: isDeleted), order: order)))
    }

    /// Adds a task, or replaces the task with the same ULID.
    ///
    /// - Parameters:
    ///   - text: The ULID text of the task.
    ///   - column: The slug of the column of the task, or `nil` for a task with no column.
    ///   - dependencies: The ULID texts of the tasks of this board that the `dependsOn` edges name.
    ///   - remoteDependencies: The URIs of the tasks of other boards that the `dependsOn` edges name.
    ///   - fields: The body and the time values of the task.
    /// - Returns: The slot of the task.
    /// - Throws: An error when a ULID text is not valid.
    @discardableResult
    mutating func addTask(
        withULID text: String,
        inColumn column: String? = ReadinessFixture.todo,
        dependingOn dependencies: [String] = [],
        dependingOnRemote remoteDependencies: [NodeURI] = [],
        fields: NodeFields = ReadinessFixture.fields()
    ) throws -> Int {
        let localEdges = try dependencies.map(Self.edge(toTask:))
        let remoteEdges = remoteDependencies.map { uri in EdgeTarget.unresolved(.remote(uri)) }
        let task = TaskNode(
            id: try DependencyMarkersTests.ulid(of: text),
            fields: fields,
            column: column.map { slug in .unresolved(.local(.column(slug: slug))) },
            dependsOn: localEdges + remoteEdges
        )
        return graph.update(with: .task(task))
    }

    /// Gives the slot of a task.
    ///
    /// - Parameter text: The ULID text of the task.
    /// - Returns: The slot.
    /// - Throws: An error when the text is not a ULID, or when the graph never had the task.
    func slot(ofTask text: String) throws -> Int {
        try #require(graph.slot(for: .task(try DependencyMarkersTests.ulid(of: text))))
    }

    /// Gives the readiness of the tasks of the board.
    var readiness: Readiness {
        Readiness(of: graph, inBoard: DependencyMarkersTests.boardKey)
    }
}
