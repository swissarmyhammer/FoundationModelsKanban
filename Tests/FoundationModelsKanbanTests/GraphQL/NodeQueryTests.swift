import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the direct access to a node by its id, and the read rules for tombstones (plan.md §3.3 rule 3, §4.1). Each
/// test runs a GraphQL document against the board of ``QueryFixture``, and compares the response JSON.
@Suite("Node queries")
struct NodeQueryTests {
    /// One node of the fixture board, and the forms of its id.
    struct NodeCase: Sendable, CustomTestStringConvertible {
        /// The GraphQL type name of the node.
        let typeName: String

        /// The text of the local ref of the node, for example `column/doing`.
        let ref: String

        /// A short form of the id of the node.
        let shortForm: String

        /// The full URI of the node, as the GraphQL `ID` shows it.
        var id: String {
            QueryFixture.id(of: ref)
        }

        /// The name of the case in the test output.
        var testDescription: String {
            typeName
        }
    }

    /// One node of each of the six node types of the fixture board.
    static let nodeCases = [
        NodeCase(typeName: GraphQLTypeName.board, ref: "board", shortForm: DependencyMarkersTests.boardKey),
        NodeCase(
            typeName: GraphQLTypeName.column,
            ref: "column/\(ReadinessFixture.doing)",
            shortForm: ReadinessFixture.doing
        ),
        NodeCase(
            typeName: GraphQLTypeName.actor,
            ref: "actor/\(ReadinessFixture.author)",
            shortForm: QueryFixture.actorName
        ),
        NodeCase(typeName: GraphQLTypeName.tag, ref: "tag/\(QueryFixture.tagSlug)", shortForm: QueryFixture.tagSlug),
        NodeCase(
            typeName: GraphQLTypeName.task,
            ref: "task/\(ReadinessFixture.first)",
            shortForm: QueryFixture.sigilRef(of: ReadinessFixture.first)
        ),
        NodeCase(
            typeName: GraphQLTypeName.comment,
            ref: "comment/\(ReadinessFixture.firstComment)",
            shortForm: ShortID(ofULIDString: ReadinessFixture.firstComment).value
        ),
    ]

    /// A ULID prefix of the third task only.
    static let thirdTaskPrefix = "01KT6S"

    /// A ULID prefix of each task and of the comment of the fixture board.
    static let sharedPrefix = "01KT6"

    /// A slug that no node of the fixture board has.
    static let unknownSlug = "no-such-node"

    /// The time of a delete, as the `deleted` field shows it.
    static let deletedTime = DependencyMarkersTests.time.rfc3339

    /// Gives the response of `node(id:)` that selects the type name and the id of the node.
    ///
    /// - Parameters:
    ///   - reference: The id to send.
    ///   - fixture: The board.
    /// - Returns: The response as JSON text.
    /// - Throws: An error that is not a GraphQL error.
    static func typeAndID(of reference: String, in fixture: QueryFixture) async throws -> String {
        try await fixture.respond(to: #"{ node(id: "\#(reference)") { __typename id } }"#)
    }

    /// Gives the expected response of `node(id:)` for a node of the board.
    ///
    /// - Parameter node: The node.
    /// - Returns: The response as JSON text.
    static func expectedTypeAndID(of node: NodeCase) -> String {
        #"{"data":{"node":{"__typename":"\#(node.typeName)","id":"\#(node.id)"}}}"#
    }

    /// Gives the ids as the items of a GraphQL list value.
    ///
    /// - Parameter references: The ids.
    /// - Returns: The quoted ids, for example `"a","b"`.
    static func quotedList(of references: [String]) -> String {
        references.map { reference in #""\#(reference)""# }.joined(separator: ",")
    }

    /// Gives the response of `nodes(ids:)` that selects the id of each node.
    ///
    /// - Parameters:
    ///   - references: The ids to send, in order.
    ///   - fixture: The board.
    /// - Returns: The response as JSON text.
    /// - Throws: An error that is not a GraphQL error.
    static func ids(ofNodes references: [String], in fixture: QueryFixture) async throws -> String {
        try await fixture.respond(to: "{ nodes(ids: [\(quotedList(of: references))]) { id } }")
    }

    /// Gives the expected response of `nodes(ids:)` that selects the id of each node.
    ///
    /// - Parameter ids: The full URIs of the nodes, in the order of the list.
    /// - Returns: The response as JSON text.
    static func expectedIDs(_ ids: [String]) -> String {
        let items = ids.map { id in #"{"id":"\#(id)"}"# }.joined(separator: ",")
        return #"{"data":{"nodes":[\#(items)]}}"#
    }

    @Test("node(id:) returns each of the six node types by its full URI", arguments: nodeCases)
    func nodeByFullURI(node: NodeCase) async throws {
        let response = try await Self.typeAndID(of: node.id, in: QueryFixture())
        #expect(response == Self.expectedTypeAndID(of: node))
    }

    @Test("node(id:) returns each of the six node types by a short form", arguments: nodeCases)
    func nodeByShortForm(node: NodeCase) async throws {
        let response = try await Self.typeAndID(of: node.shortForm, in: QueryFixture())
        #expect(response == Self.expectedTypeAndID(of: node))
    }

    @Test("node(id:) gives the fields of the node type through an inline fragment")
    func nodeGivesTheFieldsOfItsType() async throws {
        let response = try await QueryFixture().respond(
            to: #"{ node(id: "\#(ReadinessFixture.first)") { id ... on Task { title deleted } } }"#
        )
        let expected = #"{"data":{"node":{"id":"\#(QueryFixture.id(ofTask: ReadinessFixture.first))","#
            + #""title":"\#(QueryFixture.firstTitle)","deleted":null}}}"#
        #expect(response == expected)
    }

    @Test("A ULID prefix of one node gives that node")
    func uniquePrefixGivesTheNode() async throws {
        let response = try await Self.typeAndID(of: Self.thirdTaskPrefix, in: QueryFixture())
        let third = NodeCase(typeName: GraphQLTypeName.task, ref: "task/\(ReadinessFixture.third)", shortForm: "")
        #expect(response == Self.expectedTypeAndID(of: third))
    }

    @Test("A ULID prefix of a task and a comment gives null and an AMBIGUOUS_ID error")
    func prefixOfTaskAndCommentIsAmbiguous() async throws {
        let response = try await Self.typeAndID(of: Self.sharedPrefix, in: QueryFixture())
        #expect(response.hasPrefix(#"{"data":{"node":null},"errors":["#))
        #expect(response.contains(#""path":["node"]"#))
        #expect(response.contains(ShortID(ofULIDString: ReadinessFixture.firstComment).value))
    }

    @Test("node(id:) with an id that names no node returns null")
    func unknownNodeIsNull() async throws {
        let response = try await Self.typeAndID(of: ReadinessFixture.ghost, in: QueryFixture())
        #expect(response == #"{"data":{"node":null}}"#)
    }

    @Test("node(id:) with the URI of a node of a different board returns null")
    func nodeOfDifferentBoardIsNull() async throws {
        let uri = DependencyMarkersTests.url(ofTask: ReadinessFixture.first, inBoard: "local/other")
        let response = try await Self.typeAndID(of: uri, in: QueryFixture())
        #expect(response == #"{"data":{"node":null}}"#)
    }

    @Test("The schema gives nodes(ids:) a nullable list with no null item")
    func nodesFieldType() throws {
        #expect(try PublicSchema().sdl.contains("nodes(ids: [ID!]!): [Node!]\n"))
    }

    @Test("nodes(ids:) drops an unknown id from the list")
    func nodesDropsUnknownID() async throws {
        let ids = [ReadinessFixture.first, ReadinessFixture.ghost]
        let response = try await Self.ids(ofNodes: ids, in: QueryFixture())
        #expect(response == Self.expectedIDs([QueryFixture.id(ofTask: ReadinessFixture.first)]))
    }

    @Test("nodes(ids:) with no id that names a node returns an empty list")
    func nodesWithOnlyUnknownIDsIsEmpty() async throws {
        let ids = [ReadinessFixture.ghost, Self.unknownSlug]
        let response = try await Self.ids(ofNodes: ids, in: QueryFixture())
        #expect(response == Self.expectedIDs([]))
    }

    @Test("nodes(ids:) keeps the order of the ids for the known ids")
    func nodesKeepTheOrderOfTheIDs() async throws {
        let ids = [QueryFixture.tagSlug, ReadinessFixture.ghost, ReadinessFixture.third, ReadinessFixture.first]
        let response = try await Self.ids(ofNodes: ids, in: QueryFixture())
        let expected = [
            QueryFixture.id(of: "tag/\(QueryFixture.tagSlug)"),
            QueryFixture.id(ofTask: ReadinessFixture.third),
            QueryFixture.id(ofTask: ReadinessFixture.first),
        ]
        #expect(response == Self.expectedIDs(expected))
    }

    @Test("nodes(ids:) with an ambiguous id is null with AMBIGUOUS_ID, and the other fields keep their data")
    func nodesWithAmbiguousIDIsNull() async throws {
        let fixture = try QueryFixture()
        let list = Self.quotedList(of: [ReadinessFixture.first, Self.sharedPrefix])
        let document = "{ board { name } nodes(ids: [\(list)]) { id } }"
        let response = try await fixture.respond(to: document)
        let data = #"{"data":{"board":{"name":"\#(QueryFixture.boardName)"},"nodes":null},"#
        #expect(response.hasPrefix(data + #""errors":["#))
        #expect(response.contains(#""path":["nodes"]"#))
        let result = try await PublicSchema().execute(request: document, context: fixture.context())
        let matches = [
            ReadinessFixture.first, ReadinessFixture.second, ReadinessFixture.third, ReadinessFixture.firstComment,
        ].map(ShortID.init(ofULIDString:))
        let expected = KanbanError.ambiguousID(reference: Self.sharedPrefix, matches: matches)
        #expect(result.errors.first?.originalError as? KanbanError == expected)
    }

    @Test("A deleted task is not in tasks, and node(id:) returns it with deleted set")
    func deletedTaskIsATombstone() async throws {
        var fixture = try QueryFixture()
        try fixture.delete(nodeAt: .task(DependencyMarkersTests.ulid(of: ReadinessFixture.third)))
        let response = try await fixture.respond(
            to: """
                { board { tasks { totalCount edges { node { title } } } }
                    node(id: "\(QueryFixture.sigilRef(of: ReadinessFixture.third))") { deleted ... on Task { title } } }
                """
        )
        let edges = [QueryFixture.secondTitle, QueryFixture.firstTitle].map { title in
            #"{"node":{"title":"\#(title)"}}"#
        }
        let expected = #"{"data":{"board":{"tasks":{"totalCount":2,"edges":[\#(edges.joined(separator: ","))]}},"#
            + #""node":{"deleted":"\#(Self.deletedTime)","title":"\#(QueryFixture.thirdTitle)"}}}"#
        #expect(response == expected)
    }

    @Test("tasks(deleted: true) lists only the deleted tasks")
    func deletedTasksListsOnlyTombstones() async throws {
        var fixture = try QueryFixture()
        try fixture.delete(nodeAt: .task(DependencyMarkersTests.ulid(of: ReadinessFixture.third)))
        let response = try await fixture.respond(
            to: "{ board { tasks(deleted: true) { totalCount edges { node { title deleted } } } } }"
        )
        let expected = #"{"data":{"board":{"tasks":{"totalCount":1,"edges":[{"node":"#
            + #"{"title":"\#(QueryFixture.thirdTitle)","deleted":"\#(Self.deletedTime)"}}]}}}}"#
        #expect(response == expected)
    }

    @Test("Comment.author returns a deleted author as the tombstone, with deleted set")
    func deletedAuthorIsTheTombstone() async throws {
        var fixture = try QueryFixture()
        try fixture.delete(nodeAt: .actor(slug: ReadinessFixture.author))
        let commentID = QueryFixture.id(of: "comment/\(ReadinessFixture.firstComment)")
        let response = try await fixture.respond(
            to: #"{ board { actors { name } } "#
                + #"node(id: "\#(commentID)") { ... on Comment { author { name deleted } } } }"#
        )
        let expected = #"{"data":{"board":{"actors":[]},"node":{"author":"#
            + #"{"name":"\#(QueryFixture.actorName)","deleted":"\#(Self.deletedTime)"}}}}"#
        #expect(response == expected)
    }
}

extension QueryFixture {
    /// Makes a node of the board a tombstone: its `deleted` time is the fixed time of the tests.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Throws: An error when the board has no node with the ref.
    mutating func delete(nodeAt ref: LocalRef) throws {
        var tombstone = try #require(graph.slot(for: ref).flatMap(graph.node(at:))?.state)
        tombstone.fields.deleted = DependencyMarkersTests.time
        graph.update(with: tombstone.node)
    }
}
