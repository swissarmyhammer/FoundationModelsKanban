import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the in-memory graph: the node table with stable slots, the join of edges, copy-on-write, and the remove of a
/// node (plan.md §3.1, §3.3, §5.3, §5.6).
@Suite("Graph store")
struct GraphTests {
    /// The time of each test node.
    static let time = DateTime(Date(timeIntervalSince1970: .zero))

    /// The fields of each test node: an empty body and no tombstone.
    static let fields = NodeFields(created: time, updated: time)

    /// The fields of a test node after a change to its body.
    static let changedFields = NodeFields(body: "changed", created: time, updated: time)

    /// The ULID text of the test task.
    static let taskULID = "01KT6R6HR3KJT6JVNDRAJV8V4T"

    /// The ULID text of a second test task.
    static let otherTaskULID = "01KT6R7Q0ZB4X1N9C2D3E4F5G6"

    /// The ULID text of the test comment.
    static let commentULID = "01KT6SAMJAJ40XVQ9Y7JRAJ9VG"

    /// The board key of a different board.
    static let otherBoardKey = "github.com/swissarmyhammer/swissarmyhammer"

    /// The slug of the test column.
    static let columnSlug = "doing"

    /// The ref of the test column.
    static let columnRef = LocalRef.column(slug: columnSlug)

    /// The test column.
    static let column = ColumnNode(slug: columnSlug, fields: fields)

    /// The test actor.
    static let actor = ActorNode(slug: "claude-code", fields: fields)

    /// The test tag.
    static let tag = TagNode(slug: "bug", fields: fields)

    /// Gives the ULID of a ULID text.
    ///
    /// - Parameter text: The ULID text.
    /// - Returns: The ULID.
    /// - Throws: An error when the text is not a ULID.
    static func ulid(of text: String) throws -> ULID {
        try #require(ULID(ulidString: text))
    }

    /// Gives an edge that is not resolved yet: the stored local ref of its target.
    ///
    /// - Parameter ref: The local ref of the target.
    /// - Returns: The unresolved edge.
    static func edge(to ref: LocalRef) -> EdgeTarget {
        .unresolved(.local(ref))
    }

    /// Gives a test task in the test column.
    ///
    /// - Parameters:
    ///   - text: The ULID text of the task.
    ///   - fields: The fields of the task.
    /// - Returns: The task, with an unresolved edge to the test column.
    /// - Throws: An error when the text is not a ULID.
    static func task(withULID text: String = taskULID, fields: NodeFields = fields) throws -> TaskNode {
        TaskNode(id: try ulid(of: text), fields: fields, column: edge(to: columnRef))
    }

    // MARK: - Slots

    @Test("A new node gets a slot, and the graph finds the node by its ref and by its slot")
    func newNodeGetsSlot() {
        var graph = Graph()
        let slot = graph.update(with: .column(Self.column))
        #expect(graph.slot(for: Self.columnRef) == slot)
        #expect(graph.node(at: slot) == .column(Self.column))
    }

    @Test("Two nodes get two different slots")
    func twoNodesGetTwoSlots() {
        var graph = Graph()
        let columnSlot = graph.update(with: .column(Self.column))
        let actorSlot = graph.update(with: .actor(Self.actor))
        #expect(columnSlot != actorSlot)
    }

    @Test("The graph gives no slot for a ref that it does not have")
    func unknownRefHasNoSlot() {
        let graph = Graph()
        #expect(graph.slot(for: Self.columnRef) == nil)
    }

    // MARK: - Join

    @Test("An edge to a node in the graph resolves to the slot of that node")
    func edgeToKnownNodeResolves() throws {
        var graph = Graph()
        let columnSlot = graph.update(with: .column(Self.column))
        let taskSlot = graph.update(with: .task(try Self.task()))
        var expected = try Self.task()
        expected.column = .slot(columnSlot)
        #expect(graph.node(at: taskSlot) == .task(expected))
    }

    @Test("An edge to a node that comes later resolves when that node comes")
    func edgeResolvesWhenTargetComes() throws {
        var graph = Graph()
        let taskSlot = graph.update(with: .task(try Self.task()))
        #expect(graph.node(at: taskSlot) == .task(try Self.task()))
        let columnSlot = graph.update(with: .column(Self.column))
        var expected = try Self.task()
        expected.column = .slot(columnSlot)
        #expect(graph.node(at: taskSlot) == .task(expected))
    }

    @Test("Each stored edge of a task, a comment, and a tag resolves")
    func eachEdgeKindResolves() throws {
        var graph = Graph()
        let otherTaskID = try Self.ulid(of: Self.otherTaskULID)
        var task = try Self.task()
        task.assignees = [Self.edge(to: .actor(slug: Self.actor.slug))]
        task.tags = [Self.edge(to: .tag(slug: Self.tag.slug))]
        task.dependsOn = [Self.edge(to: .task(otherTaskID))]
        task.columnMoves = [ColumnMove(at: Self.time, column: Self.edge(to: Self.columnRef))]
        let comment = CommentNode(
            id: try Self.ulid(of: Self.commentULID),
            fields: Self.fields,
            task: Self.edge(to: .task(task.id)),
            author: Self.edge(to: .actor(slug: Self.actor.slug))
        )
        let renamedTag = TagNode(slug: "defect", fields: Self.fields, renamedTo: Self.edge(to: .tag(slug: "bug")))

        let taskSlot = graph.update(with: .task(task))
        let commentSlot = graph.update(with: .comment(comment))
        let renamedSlot = graph.update(with: .tag(renamedTag))
        let columnSlot = graph.update(with: .column(Self.column))
        let actorSlot = graph.update(with: .actor(Self.actor))
        let tagSlot = graph.update(with: .tag(Self.tag))
        let otherTaskSlot = graph.update(with: .task(try Self.task(withULID: Self.otherTaskULID)))

        var expectedTask = task
        expectedTask.column = .slot(columnSlot)
        expectedTask.assignees = [.slot(actorSlot)]
        expectedTask.tags = [.slot(tagSlot)]
        expectedTask.dependsOn = [.slot(otherTaskSlot)]
        expectedTask.columnMoves = [ColumnMove(at: Self.time, column: .slot(columnSlot))]
        var expectedComment = comment
        expectedComment.task = .slot(taskSlot)
        expectedComment.author = .slot(actorSlot)
        var expectedTag = renamedTag
        expectedTag.renamedTo = .slot(tagSlot)

        #expect(graph.node(at: taskSlot) == .task(expectedTask))
        #expect(graph.node(at: commentSlot) == .comment(expectedComment))
        #expect(graph.node(at: renamedSlot) == .tag(expectedTag))
    }

    @Test("A dependsOn edge to a task in a different board stays unresolved")
    func remoteEdgeStaysUnresolved() throws {
        var graph = Graph()
        let remoteTaskID = try Self.ulid(of: Self.taskULID)
        let remote = StoredRef.remote(NodeURI(boardKey: Self.otherBoardKey, ref: .task(remoteTaskID)))
        var task = try Self.task(withULID: Self.otherTaskULID)
        task.dependsOn = [.unresolved(remote)]
        graph.update(with: .task(try Self.task()))
        let slot = graph.update(with: .task(task))
        let stored = try #require(graph.node(at: slot))
        #expect(stored.edges.contains(.unresolved(remote)))
    }

    // MARK: - Replace

    @Test("A replace of one node keeps its slot, and the edges of the other nodes stay correct")
    func replaceKeepsSlotAndEdges() throws {
        var graph = Graph()
        let columnSlot = graph.update(with: .column(Self.column))
        let taskSlot = graph.update(with: .task(try Self.task()))
        let comment = CommentNode(
            id: try Self.ulid(of: Self.commentULID),
            fields: Self.fields,
            task: Self.edge(to: .task(try Self.ulid(of: Self.taskULID)))
        )
        let commentSlot = graph.update(with: .comment(comment))

        let changedColumn = ColumnNode(slug: Self.columnSlug, fields: Self.changedFields)
        #expect(graph.update(with: .column(changedColumn)) == columnSlot)
        #expect(graph.update(with: .task(try Self.task(fields: Self.changedFields))) == taskSlot)

        var expectedTask = try Self.task(fields: Self.changedFields)
        expectedTask.column = .slot(columnSlot)
        var expectedComment = comment
        expectedComment.task = .slot(taskSlot)
        #expect(graph.node(at: columnSlot) == .column(changedColumn))
        #expect(graph.node(at: taskSlot) == .task(expectedTask))
        #expect(graph.node(at: commentSlot) == .comment(expectedComment))
    }

    // MARK: - Copy-on-write

    @Test("A change to a copy of the graph does not change the original")
    func copyChangeLeavesOriginal() throws {
        var graph = Graph()
        let columnSlot = graph.update(with: .column(Self.column))
        let taskSlot = graph.update(with: .task(try Self.task()))
        let original = graph

        var copy = graph
        copy.update(with: .column(ColumnNode(slug: Self.columnSlug, fields: Self.changedFields)))
        copy.remove(nodeAt: .task(try Self.ulid(of: Self.taskULID)))
        copy.update(with: .actor(Self.actor))

        var expectedTask = try Self.task()
        expectedTask.column = .slot(columnSlot)
        #expect(graph.node(at: columnSlot) == .column(Self.column))
        #expect(graph.node(at: taskSlot) == .task(expectedTask))
        #expect(graph.slot(for: .actor(slug: Self.actor.slug)) == nil)
        #expect(original.node(at: taskSlot) == .task(expectedTask))
        #expect(copy.node(at: taskSlot) == nil)
    }

    // MARK: - Remove

    @Test("A remove makes the edges to the node unresolved, and a later insert resolves them again")
    func removeThenInsertResolvesAgain() throws {
        var graph = Graph()
        let columnSlot = graph.update(with: .column(Self.column))
        let taskSlot = graph.update(with: .task(try Self.task()))

        graph.remove(nodeAt: Self.columnRef)
        #expect(graph.node(at: columnSlot) == nil)
        #expect(graph.slot(for: Self.columnRef) == columnSlot)
        #expect(graph.node(at: taskSlot) == .task(try Self.task()))

        #expect(graph.update(with: .column(Self.column)) == columnSlot)
        var expectedTask = try Self.task()
        expectedTask.column = .slot(columnSlot)
        #expect(graph.node(at: taskSlot) == .task(expectedTask))
    }

    @Test("A remove of a ref that the graph does not have changes nothing")
    func removeOfUnknownRefChangesNothing() throws {
        var graph = Graph()
        let columnSlot = graph.update(with: .column(Self.column))
        graph.remove(nodeAt: .task(try Self.ulid(of: Self.taskULID)))
        #expect(graph.node(at: columnSlot) == .column(Self.column))
        #expect(graph.slot(for: .task(try Self.ulid(of: Self.taskULID))) == nil)
    }

    // MARK: - Tombstone

    @Test("A node with a deleted time is a tombstone, and a node without one is not")
    func deletedTimeMakesTombstone() {
        let tombstone = NodeFields(created: Self.time, updated: Self.time, deleted: Self.time)
        #expect(tombstone.isDeleted)
        #expect(!Self.fields.isDeleted)
    }

    @Test("Each node gives the local ref of its slot")
    func nodesGiveTheirRefs() throws {
        let taskID = try Self.ulid(of: Self.taskULID)
        let commentID = try Self.ulid(of: Self.commentULID)
        let nodes: [Node] = [
            .board(BoardNode(fields: Self.fields)),
            .column(Self.column),
            .actor(Self.actor),
            .tag(Self.tag),
            .task(try Self.task()),
            .comment(CommentNode(id: commentID, fields: Self.fields)),
        ]
        let refs: [LocalRef] = [
            .board, Self.columnRef, .actor(slug: Self.actor.slug), .tag(slug: Self.tag.slug), .task(taskID),
            .comment(commentID),
        ]
        #expect(nodes.map(\.ref) == refs)
    }
}
