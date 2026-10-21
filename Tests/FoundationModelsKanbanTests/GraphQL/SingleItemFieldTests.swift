import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the single-item fields of the board (KANBAN-5; EXTRAS-9 rule 5): `task`, `column`, `actor` and `tag` each take
/// `id:`, and the other keys of the node are aliases of `id`. A root field moves into `board`, so `{ column(id:) }`
/// reads the same column as `{ board { column(id:) } }`. An id that names no node gives `null` and no error; an
/// ambiguous ULID prefix stays an error. Each test runs a document against ``QueryFixture``.
@Suite("Single-item fields: task, column, actor, and tag by id")
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
        ItemCase(
            field: "task",
            reference: QueryFixture.sigilRef(of: ReadinessFixture.first),
            alias: "task",
            localRef: "task/\(ReadinessFixture.first)"
        ),
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

    /// The length of the ULID prefix that the first and the second task of the fixture share: `01KT6R`.
    static let sharedTaskPrefixLength = 6

    /// The code of the error of a ref that is a prefix of more than one ULID.
    static let ambiguousIDCode = "AMBIGUOUS_ID"

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

    @Test("A single-item field of the board with an id that names no node gives null and no error", arguments: itemCases)
    func unknownIDGivesNull(item: ItemCase) async throws {
        let response = try await QueryFixture().respond(to: item.boardDocument(value: Self.missingReference))
        #expect(response == #"{"data":{"board":{"\#(item.field)":null}}}"#)
    }

    @Test("A single-item field at the root with an id that names no node gives null and no error", arguments: itemCases)
    func unknownIDAtRootGivesNull(item: ItemCase) async throws {
        let response = try await QueryFixture().respond(
            to: #"{ \#(item.field)(id: "\#(Self.missingReference)") { id } }"#
        )
        try Self.expectNullWithoutErrors(at: [item.field], in: response)
    }

    @Test("Board.task with a ULID prefix of two tasks gives null and AMBIGUOUS_ID")
    func ambiguousTaskIDGivesAnError() async throws {
        let prefix = String(ReadinessFixture.first.prefix(Self.sharedTaskPrefixLength))
        let response = try await QueryFixture().respond(to: #"{ board { task(id: "\#(prefix)") { id } } }"#)
        #expect(response.hasPrefix(#"{"data":{"board":{"task":null}},"errors":["#), "\(response)")
        #expect(try ViewerReachTests.errorCodes(of: response) == [Self.ambiguousIDCode])
    }

    /// Expects that a response has `null` at a path of keys in its `data` object, and no `errors` entry (EXTRAS-9
    /// rule 5). The response can have `extensions`, for example the rewrite of a root field into `board`.
    ///
    /// - Parameters:
    ///   - keys: The keys from `data` to the value.
    ///   - response: The response JSON text.
    /// - Throws: An error when the response is not a JSON object with a `data` object.
    static func expectNullWithoutErrors(at keys: [String], in response: String) throws {
        #expect(try KanbanGraphTests.object(of: response)["errors"] == nil, "\(response)")
        let data: Any? = try KanbanGraphTests.data(of: response)
        let value = keys.reduce(data) { parent, key in (parent as? [String: Any])?[key] }
        #expect(value is NSNull, "\(response)")
    }
}
