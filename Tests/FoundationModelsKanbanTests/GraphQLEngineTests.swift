import Foundation
import GraphQL
import Testing

@testable import FoundationModelsKanban

/// Tests that the GraphQL engine runs Graphiti schemas end to end under Swift 6
/// strict concurrency (plan.md §10, step 2).
@Suite("GraphQL engine")
struct GraphQLEngineTests {
    /// The time at which the fixture board was made.
    static let createdText = "2026-10-06T14:49:10.690Z"

    /// The time that the fixed clock gives to a mutation.
    static let clockText = "2026-10-07T08:30:00.001Z"

    /// The key of the fixture board.
    static let boardKey = "local/kanban"

    /// Makes a context with a fixture board and a fixed clock, so that each
    /// response is deterministic.
    static func makeContext() throws -> KanbanContext {
        let created = try DateTime(rfc3339: createdText)
        let now = try DateTime(rfc3339: clockText)
        var graph = Graph()
        graph.update(with: .board(BoardNode(fields: NodeFields(created: created, updated: created), name: "Kanban")))
        return CommitTests.callContext(of: BoardStore.fixture(of: graph, inBoard: boardKey), timedBy: { now })
    }

    @Test("A query runs end to end and returns the expected JSON")
    func queryReturnsTheBoard() async throws {
        let schema = try PublicSchema()
        let response = try await schema.respond(
            to: "{ board { name body created updated } }",
            context: Self.makeContext()
        )
        #expect(
            response
                == #"{"data":{"board":{"name":"Kanban","body":"","created":"2026-10-06T14:49:10.690Z","updated":"2026-10-06T14:49:10.690Z"}}}"#
        )
    }

    @Test("A mutation runs end to end, returns the expected JSON, and changes the board")
    func mutationUpdatesTheBoard() async throws {
        let schema = try PublicSchema()
        let context = try Self.makeContext()
        let mutation = try await schema.respond(
            to: #"mutation { updateBoard(input: { name: "Port" }) { name body updated } }"#,
            context: context
        )
        #expect(
            mutation
                == #"{"data":{"updateBoard":{"name":"Port","body":"","updated":"2026-10-07T08:30:00.001Z"}}}"#
        )
        let query = try await schema.respond(to: "{ board { name } }", context: context)
        #expect(query == #"{"data":{"board":{"name":"Port"}}}"#)
    }

    @Test("A DateTime value round-trips through RFC 3339 text")
    func dateTimeRoundTripsThroughText() throws {
        let value = try DateTime(rfc3339: Self.createdText)
        #expect(value.rfc3339 == Self.createdText)
        #expect(try DateTime(rfc3339: value.rfc3339) == value)
    }

    @Test("A DateTime value round-trips through the DateTime scalar of the schema")
    func dateTimeRoundTripsThroughTheScalar() throws {
        let scalar = try #require(
            try PublicSchema().schema.schema.getType(name: "DateTime") as? GraphQLScalarType
        )
        let value = try DateTime(rfc3339: Self.clockText)
        let serialized = try scalar.serialize(value: value)
        #expect(serialized == .string(Self.clockText))
        #expect(try scalar.parseValue(value: serialized) == serialized)
    }

    @Test("The DateTime scalar refuses text that is not RFC 3339")
    func dateTimeScalarRefusesBadText() throws {
        let scalar = try #require(
            try PublicSchema().schema.schema.getType(name: "DateTime") as? GraphQLScalarType
        )
        #expect(throws: (any Error).self) {
            try scalar.parseValue(value: .string("yesterday"))
        }
    }

    @Test("A DateTime value round-trips through RFC 3339 text with no fractional seconds")
    func dateTimeReadsTextWithNoFraction() throws {
        let value = try DateTime(rfc3339: "2026-10-06T14:49:10Z")
        #expect(value.rfc3339 == "2026-10-06T14:49:10.000Z")
    }

    @Test("A DateTime value before 1970 round-trips through RFC 3339 text")
    func dateTimeRoundTripsBefore1970() throws {
        let text = "1969-12-31T23:59:59.999Z"
        #expect(try DateTime(rfc3339: text).rfc3339 == text)
    }

    @Test("A JSON value in the variables round-trips through the patch mutation")
    func jsonRoundTripsFromVariables() async throws {
        let patch: Map = [
            "node": "task/01K6Z3ABCDEFGHJKMNPQRSTVWX",
            "type": "Task",
            "set": ["title": "Port the filter DSL", "ordinal": "80", "points": 3, "open": true],
            "add": ["tags": ["tag/kanban"]],
            "delete": false,
        ]
        let response = try await PatchSchema().respond(
            to: "mutation($p: PatchInput!) { patch(input: $p) }",
            variables: ["p": patch],
            context: Self.makeContext()
        )
        #expect(
            response
                == #"{"data":{"patch":{"add":{"tags":["tag/kanban"]},"delete":false,"node":"task/01K6Z3ABCDEFGHJKMNPQRSTVWX","set":{"open":true,"ordinal":"80","points":3,"title":"Port the filter DSL"},"type":"Task"}}}"#
        )
    }

    @Test("A JSON literal in the document round-trips through the patch mutation")
    func jsonRoundTripsFromALiteral() async throws {
        let response = try await PatchSchema().respond(
            to: #"mutation { patch(input: { node: "tag/bug", type: Tag, unset: ["color"], set: { name: "bug", rank: 2, list: [1, "two", null, true] }, delete: true }) }"#,
            context: Self.makeContext()
        )
        #expect(
            response
                == #"{"data":{"patch":{"delete":true,"node":"tag/bug","set":{"list":[1,"two",null,true],"name":"bug","rank":2},"type":"Tag","unset":["color"]}}}"#
        )
    }

    @Test("A patch mutation whose node is not a local ref gives an INTERNAL error and no data")
    func patchRefusesANodeThatIsNotALocalRef() async throws {
        let response = try await PatchSchema().respond(
            to: #"mutation { patch(input: { node: "task/01K6Z3", type: Task }) }"#,
            context: Self.makeContext()
        )
        #expect(
            response
                == #"{"errors":[{"message":"invalidULID(ref: \"task/01K6Z3\")","locations":[{"line":1,"column":12}],"path":["patch"],"extensions":{"code":"INTERNAL"}}]}"#
        )
    }

    @Test("The JSON scalar refuses an output value that is not a Map")
    func jsonScalarRefusesAValueThatIsNotAMap() throws {
        let scalar = try #require(
            try PatchSchema().schema.schema.getType(name: JSONScalar.name) as? GraphQLScalarType
        )
        #expect(throws: JSONScalarError.notAMap("Int")) {
            try scalar.serialize(value: 1)
        }
    }

    @Test("The public SDL has no patch field, and the internal SDL has it")
    func onlyTheInternalSchemaHasPatch() throws {
        #expect(!(try PublicSchema().sdl.contains("patch")))
        #expect(try PatchSchema().sdl.contains("patch(input: PatchInput!): JSON!"))
    }

    @Test("A patch mutation sent to the public schema gives a validation error")
    func publicSchemaRefusesPatch() async throws {
        let response = try await PublicSchema().respond(
            to: #"mutation { patch(input: { node: "tag/bug", type: Tag }) }"#,
            context: Self.makeContext()
        )
        #expect(response.contains(#"Cannot query field \"patch\" on type \"Mutation\"."#))
    }
}
