import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the tags of a task at read time: the union of the tag edges and the body markers, and the rename redirect
/// (plan.md §6.1, §6.2, and §5.3 step 5).
@Suite("Tag resolve")
struct TagResolveTests {
    /// The time of each test node.
    static let time = DateTime(Date(timeIntervalSince1970: .zero))

    /// The ULID text of the test task.
    static let taskULID = "01KT6R6HR3KJT6JVNDRAJV8V4T"

    /// The body and the time values of a live test node.
    static let liveFields = NodeFields(created: time, updated: time)

    /// The body and the time values of a tombstoned test node.
    static let deletedFields = NodeFields(created: time, updated: time, deleted: time)

    /// The tags of a rename cycle from a merge: `bug` → `defect` → `issue` → `defect`.
    static let cycleTags = [
        tag(named: "bug", renamedTo: "defect"),
        tag(named: "defect", renamedTo: "issue"),
        tag(named: "issue", renamedTo: "defect"),
    ]

    /// Gives the unresolved edge to a tag, as replay gives it.
    ///
    /// - Parameter slug: The slug of the tag.
    /// - Returns: The edge.
    static func edge(toTag slug: String) -> EdgeTarget {
        .unresolved(.local(.tag(slug: slug)))
    }

    /// Gives a test tag.
    ///
    /// - Parameters:
    ///   - slug: The slug of the tag.
    ///   - target: The slug of the tag that a rename made this tag point to, or `nil`.
    ///   - isDeleted: `true` when the tag is a tombstone.
    /// - Returns: The tag, as a node.
    static func tag(named slug: String, renamedTo target: String? = nil, isDeleted: Bool = false) -> Node {
        let fields = isDeleted ? deletedFields : liveFields
        return .tag(TagNode(slug: slug, fields: fields, renamedTo: target.map(edge(toTag:))))
    }

    /// Puts nodes into a new graph.
    ///
    /// - Parameter nodes: The nodes, in insert order.
    /// - Returns: The graph.
    static func graph(with nodes: [Node]) -> Graph {
        var graph = Graph()
        for node in nodes {
            graph.update(with: node)
        }
        return graph
    }

    /// Puts tags and one task into a graph, and gives the slugs of the tags of the task.
    ///
    /// - Parameters:
    ///   - tags: The tag nodes.
    ///   - body: The body of the task.
    ///   - tagEdges: The slugs of the `tags` edges of the task.
    /// - Returns: The slugs of the tags of the task, in result order.
    /// - Throws: An error when the test ULID is not valid.
    static func taskTags(with tags: [Node], body: String = "", tagEdges: [String] = []) throws -> [String] {
        var graph = Self.graph(with: tags)
        let id = try #require(ULID(ulidString: taskULID))
        let fields = NodeFields(body: body, created: time, updated: time)
        let task = TaskNode(id: id, fields: fields, tags: tagEdges.map(edge(toTag:)))
        let slot = graph.update(with: .task(task))
        let stored = try #require(graph.node(at: slot)?.state as? TaskNode)
        return slugs(at: graph.tagSlots(of: stored), in: graph)
    }

    /// Puts tags into a graph, and gives the slugs of the tags of the board.
    ///
    /// - Parameter tags: The tag nodes.
    /// - Returns: The slugs of the tags of the board, in result order.
    static func boardTags(with tags: [Node]) -> [String] {
        let graph = Self.graph(with: tags)
        return slugs(at: graph.boardTagSlots, in: graph)
    }

    /// Gives the slugs of the tags in some slots.
    ///
    /// - Parameters:
    ///   - slots: The slots of the tags.
    ///   - graph: The graph that holds the tags.
    /// - Returns: The slugs. A slot that holds no tag gives no slug.
    static func slugs(at slots: [Int], in graph: Graph) -> [String] {
        slots.compactMap { slot in
            (graph.node(at: slot)?.state as? TagNode)?.slug
        }
    }

    // MARK: - Union

    @Test("A marker in the body gives its tag")
    func markerGivesTag() throws {
        #expect(try Self.taskTags(with: [Self.tag(named: "bug")], body: "Fix the #bug now") == ["bug"])
    }

    @Test("An edge and a marker to one tag give the tag one time")
    func edgeAndMarkerGiveTagOneTime() throws {
        let tags = try Self.taskTags(with: [Self.tag(named: "bug")], body: "#Bug and #bug", tagEdges: ["bug"])
        #expect(tags == ["bug"])
    }

    @Test("The edges come first, then the markers, in text order")
    func edgesComeBeforeMarkers() throws {
        let nodes = [Self.tag(named: "bug"), Self.tag(named: "login"), Self.tag(named: "ui")]
        let tags = try Self.taskTags(with: nodes, body: "#login and #bug", tagEdges: ["ui"])
        #expect(tags == ["ui", "login", "bug"])
    }

    @Test("A marker or an edge to a tag that the graph does not have gives no tag")
    func unknownTagGivesNoTag() throws {
        #expect(try Self.taskTags(with: [], body: "#ghost", tagEdges: ["phantom"]).isEmpty)
    }

    // MARK: - Redirect

    @Test("After a rename, an edge and a marker to the old tag both show the new tag")
    func redirectCoversEdgeAndMarker() throws {
        let nodes = [Self.tag(named: "bug", renamedTo: "defect"), Self.tag(named: "defect")]
        #expect(try Self.taskTags(with: nodes, tagEdges: ["bug"]) == ["defect"])
        #expect(try Self.taskTags(with: nodes, body: "#bug") == ["defect"])
        #expect(try Self.taskTags(with: nodes, body: "#bug #defect", tagEdges: ["bug"]) == ["defect"])
    }

    @Test("A chain of renames is followed to its end")
    func chainIsFollowed() throws {
        let nodes = [
            Self.tag(named: "bug", renamedTo: "defect"),
            Self.tag(named: "defect", renamedTo: "issue"),
            Self.tag(named: "issue"),
        ]
        #expect(try Self.taskTags(with: nodes, body: "#bug", tagEdges: ["defect"]) == ["issue"])
    }

    @Test("A rename cycle stops at the first slug that repeats, and uses that tag")
    func cycleStopsAtFirstRepeat() throws {
        #expect(try Self.taskTags(with: Self.cycleTags, tagEdges: ["bug"]) == ["defect"])
        #expect(try Self.taskTags(with: Self.cycleTags, body: "#issue") == ["issue"])
    }

    @Test("The rename target of a tag in a cycle is the tag itself")
    func renameTargetOfCycleMember() throws {
        let graph = Self.graph(with: Self.cycleTags)
        let issue = try #require(graph.slot(for: .tag(slug: "issue")))
        #expect(graph.renameTarget(ofTagAt: issue) == issue)
    }

    // MARK: - Tombstone

    @Test("A resolve that ends at a tombstone drops the tag")
    func tombstoneDropsTag() throws {
        let nodes = [Self.tag(named: "bug", renamedTo: "defect"), Self.tag(named: "defect", isDeleted: true)]
        #expect(try Self.taskTags(with: nodes, body: "#bug #defect", tagEdges: ["bug", "defect"]).isEmpty)
    }

    @Test("A tombstone in the middle of a chain is followed to the live end")
    func tombstoneInChainIsFollowed() throws {
        let nodes = [Self.tag(named: "bug", renamedTo: "defect", isDeleted: true), Self.tag(named: "defect")]
        #expect(try Self.taskTags(with: nodes, tagEdges: ["bug"]) == ["defect"])
    }

    @Test("A rename to a tag that the graph does not have drops the tag")
    func renameToMissingTagDropsTag() throws {
        #expect(try Self.taskTags(with: [Self.tag(named: "bug", renamedTo: "defect")], body: "#bug").isEmpty)
    }

    // MARK: - Board tags

    @Test("The board lists the live tags with no rename")
    func boardListsLiveTags() {
        let nodes = [
            Self.tag(named: "bug", renamedTo: "defect"),
            Self.tag(named: "defect"),
            Self.tag(named: "old", isDeleted: true),
            Self.tag(named: "ui"),
        ]
        #expect(Self.boardTags(with: nodes) == ["defect", "ui"])
    }

    @Test("The board lists the tags where a rename cycle stops")
    func boardListsCycleStops() {
        #expect(Self.boardTags(with: Self.cycleTags) == ["defect", "issue"])
    }
}
