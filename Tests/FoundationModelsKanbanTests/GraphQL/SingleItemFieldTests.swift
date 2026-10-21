import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the single-item fields of the board (KANBAN-5; EXTRAS-9 rule 5): `task`, `column`, `actor` and `tag` each take
/// `id:`, and the other keys of the node are aliases of `id`. A root field moves into `board`, so `{ column(id:) }`
/// reads the same column as `{ board { column(id:) } }`. Each test runs a document against ``QueryFixture``.
@Suite("Single-item fields: column, actor, and tag by id")
struct SingleItemFieldTests {
    /// One single-item field of the board, a ref of a node of the fixture, and the stored local ref of that node.
    struct ItemCase: CustomTestStringConvertible, Sendable {
        /// The name of the field, for example `column`.
        let field: String

        /// The ref of the node as the call writes it, for example its slug.
        let reference: String

        /// The other key of the node, as an alias of `id`, for example `slug`.
        let alias: String

        /// The stored local ref of the node, for example `column/doing`.
        let localRef: String

        /// The name of the case in the test output.
        var testDescription: String {
            "\(field)(id: \"\(reference)\")"
        }

        /// The response of `{ board { <field>(id: <reference>) { id } } }`.
        var expectedResponse: String {
            #"{"data":{"board":{"\#(field)":{"id":"\#(QueryFixture.id(of: localRef))"}}}}"#
        }

        /// Makes the document of the field in `board`, with one argument.
        ///
        /// - Parameters:
        ///   - argument: The name of the argument, for example `id`.
        ///   - value: The value of the argument.
        /// - Returns: The document.
        func boardDocument(argument: String = "id", value: String) -> String {
            #"{ board { \#(field)(\#(argument): "\#(value)") { id } } }"#
        }
    }

    /// The single-item fields of the board, each with a node of the fixture.
    static let itemCases = [
        ItemCase(field: "column", reference: ReadinessFixture.doing, alias: "slug", localRef: "column/doing"),
        ItemCase(
            field: "actor",
            reference: ReadinessFixture.author,
            alias: "name",
            localRef: "actor/\(ReadinessFixture.author)"
        ),
        ItemCase(field: "tag", reference: QueryFixture.tagSlug, alias: "name", localRef: "tag/\(QueryFixture.tagSlug)"),
    ]

    /// A ref that names no node of the fixture.
    static let missingReference = "no-such-node"

    @Test("A single-item field of the board takes id: and gives the node", arguments: itemCases)
    func fieldTakesID(item: ItemCase) async throws {
        let response = try await QueryFixture().respond(to: item.boardDocument(value: item.reference))
        #expect(response == item.expectedResponse)
    }

    @Test("A single-item field of the board takes the full URI of the node as id:", arguments: itemCases)
    func fieldTakesFullURI(item: ItemCase) async throws {
        let response = try await QueryFixture().respond(
            to: item.boardDocument(value: QueryFixture.id(of: item.localRef))
        )
        #expect(response == item.expectedResponse)
    }

    @Test("A single-item field of the board takes another key of the node as an alias of id:", arguments: itemCases)
    func fieldTakesAliasOfID(item: ItemCase) async throws {
        let response = try await QueryFixture().respond(
            to: item.boardDocument(argument: item.alias, value: item.reference)
        )
        let data = try KanbanGraphTests.data(of: response)
        let expected = try KanbanGraphTests.data(of: item.expectedResponse)
        #expect(NSDictionary(dictionary: data).isEqual(to: expected), "\(response)")
    }

    @Test("A single-item field at the root moves into board and gives the same node", arguments: itemCases)
    func rootFieldMovesIntoBoard(item: ItemCase) async throws {
        let response = try await QueryFixture().respond(
            to: #"{ \#(item.field)(id: "\#(item.reference)") { id } }"#
        )
        let data = try KanbanGraphTests.data(of: response)
        let board = try #require(KanbanGraphTests.data(of: item.expectedResponse)["board"] as? [String: Any])
        #expect(NSDictionary(dictionary: data).isEqual(to: board), "\(response)")
    }

    @Test("A single-item field of the board with an id that names no node gives null and NOT_FOUND", arguments: itemCases)
    func unknownIDGivesNotFound(item: ItemCase) async throws {
        let response = try await QueryFixture().respond(to: item.boardDocument(value: Self.missingReference))
        #expect(response.hasPrefix(#"{"data":{"board":{"\#(item.field)":null}},"errors":["#), "\(response)")
        #expect(try ViewerReachTests.errorCodes(of: response) == [CrossRepoTransferTests.notFoundCode])
    }
}
