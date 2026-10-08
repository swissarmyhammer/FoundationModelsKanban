import Foundation
import Testing

@testable import FoundationModelsKanban

/// A test board for the tests of the derived fields and the filter: a graph with the default columns, and tasks,
/// actors, tags, columns, and comments that the tests add (plan.md §5.3, §6).
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

    /// The ULID text of the first test comment.
    static let firstComment = "01KT6WD0A15N7Q9S1T3V5W7X9Y"

    /// The ULID text of the second test comment.
    static let secondComment = "01KT6XE1B26P8R0T2V4W6X8Y0Z"

    /// The slug of the test actor.
    static let author = "claude-code"

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

    /// Gives a time some seconds after 1970-01-01T00:00:00Z.
    ///
    /// - Parameter seconds: The number of seconds.
    /// - Returns: The time.
    static func time(atSecond seconds: Int) -> DateTime {
        DateTime(Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    /// Gives a move of a task to a column, as replay records it.
    ///
    /// - Parameters:
    ///   - slug: The slug of the column.
    ///   - seconds: The time of the move, in seconds after 1970-01-01T00:00:00Z.
    /// - Returns: The move, with an unresolved edge to the column.
    static func move(toColumn slug: String, atSecond seconds: Int) -> ColumnMove {
        ColumnMove(at: time(atSecond: seconds), column: .unresolved(.local(.column(slug: slug))))
    }

    /// Gives the slot of a column.
    ///
    /// - Parameter slug: The slug of the column.
    /// - Returns: The slot.
    /// - Throws: An error when the graph never had the column.
    func slot(ofColumn slug: String) throws -> Int {
        try #require(graph.slot(for: .column(slug: slug)))
    }

    /// Adds an actor, or replaces the actor with the same slug.
    ///
    /// - Parameters:
    ///   - slug: The slug of the actor.
    ///   - name: The name of the actor.
    ///   - isDeleted: `true` when the actor is a tombstone.
    /// - Returns: The slot of the actor.
    @discardableResult
    mutating func addActor(withSlug slug: String, named name: String = "", isDeleted: Bool = false) -> Int {
        graph.update(with: .actor(ActorNode(slug: slug, fields: Self.fields(isDeleted: isDeleted), name: name)))
    }

    /// Adds a tag, or replaces the tag with the same slug.
    ///
    /// - Parameters:
    ///   - slug: The slug of the tag.
    ///   - target: The slug of the tag that a rename made this tag point to, or `nil` for a tag with no rename.
    ///   - isDeleted: `true` when the tag is a tombstone.
    mutating func addTag(withSlug slug: String, renamedTo target: String? = nil, isDeleted: Bool = false) {
        let renamedTo = target.map { targetSlug in EdgeTarget.unresolved(.local(.tag(slug: targetSlug))) }
        let tag = TagNode(slug: slug, fields: Self.fields(isDeleted: isDeleted), renamedTo: renamedTo)
        graph.update(with: .tag(tag))
    }

    /// Adds a comment, or replaces the comment with the same ULID.
    ///
    /// - Parameters:
    ///   - text: The ULID text of the comment.
    ///   - task: The ULID text of the task of the comment.
    ///   - author: The slug of the actor that wrote the comment.
    ///   - isDeleted: `true` when the comment is a tombstone.
    /// - Returns: The slot of the comment.
    /// - Throws: An error when a ULID text is not valid.
    @discardableResult
    mutating func addComment(
        withULID text: String,
        onTask task: String,
        byActor author: String = ReadinessFixture.author,
        isDeleted: Bool = false
    ) throws -> Int {
        let comment = CommentNode(
            id: try DependencyMarkersTests.ulid(of: text),
            fields: Self.fields(isDeleted: isDeleted),
            task: try Self.edge(toTask: task),
            author: .unresolved(.local(.actor(slug: author)))
        )
        return graph.update(with: .comment(comment))
    }

    /// Adds a column, or replaces the column with the same slug.
    ///
    /// - Parameters:
    ///   - slug: The slug of the column.
    ///   - name: The name of the column.
    ///   - order: The sort key of the column.
    ///   - isDeleted: `true` when the column is a tombstone.
    mutating func addColumn(withSlug slug: String, named name: String = "", order: Int, isDeleted: Bool = false) {
        let column = ColumnNode(slug: slug, fields: Self.fields(isDeleted: isDeleted), name: name, order: order)
        graph.update(with: .column(column))
    }

    /// Adds a task, or replaces the task with the same ULID.
    ///
    /// - Parameters:
    ///   - text: The ULID text of the task.
    ///   - column: The slug of the column of the task, or `nil` for a task with no column.
    ///   - tags: The slugs of the tags that the `tags` edges name.
    ///   - assignees: The slugs of the actors that the `assignees` edges name.
    ///   - dependencies: The ULID texts of the tasks of this board that the `dependsOn` edges name.
    ///   - remoteDependencies: The URIs of the tasks of other boards that the `dependsOn` edges name.
    ///   - moves: The moves of the task to a column, in event order.
    ///   - fields: The body and the time values of the task.
    ///   - title: The title of the task. The default is the empty title.
    /// - Returns: The slot of the task.
    /// - Throws: An error when a ULID text is not valid.
    @discardableResult
    mutating func addTask(
        withULID text: String,
        titled title: String = "",
        inColumn column: String? = ReadinessFixture.todo,
        taggedWith tags: [String] = [],
        assignedTo assignees: [String] = [],
        dependingOn dependencies: [String] = [],
        dependingOnRemote remoteDependencies: [NodeURI] = [],
        withMoves moves: [ColumnMove] = [],
        fields: NodeFields = ReadinessFixture.fields()
    ) throws -> Int {
        let localEdges = try dependencies.map(Self.edge(toTask:))
        let remoteEdges = remoteDependencies.map { uri in EdgeTarget.unresolved(.remote(uri)) }
        let task = TaskNode(
            id: try DependencyMarkersTests.ulid(of: text),
            fields: fields,
            title: title,
            column: column.map { slug in .unresolved(.local(.column(slug: slug))) },
            assignees: assignees.map { slug in .unresolved(.local(.actor(slug: slug))) },
            tags: tags.map { slug in .unresolved(.local(.tag(slug: slug))) },
            dependsOn: localEdges + remoteEdges,
            columnMoves: moves
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
