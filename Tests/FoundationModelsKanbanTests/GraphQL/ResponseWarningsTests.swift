import Graphiti
import Testing

@testable import FoundationModelsKanban

/// The arguments of the test field `warn`.
struct WarnArguments: Codable, Sendable {
    /// The text of the warning that the field adds.
    let message: String
}

extension KanbanResolver {
    /// The resolver of the test field `warn`: it adds one warning with the message of the arguments, and gives the
    /// message back.
    ///
    /// - Parameters:
    ///   - context: The context of the run.
    ///   - arguments: The arguments of the field.
    /// - Returns: The message of the warning.
    func warn(context: KanbanContext, arguments: WarnArguments) async -> String {
        await context.warnings.add(arguments.message, code: ResponseWarningsTests.warningCode)
        return arguments.message
    }
}

/// Tests the one warnings list of each response: `extensions.warnings` (plan.md §4.4).
///
/// No field of the public schema gives a warning yet, so each test adds the test field `warn` to the public schema.
/// The field adds one warning to the collector of its run.
@Suite("Response warnings: extensions.warnings of each call")
struct ResponseWarningsTests {
    /// The code of each warning of the test field.
    static let warningCode = "TEST_WARNING"

    /// The message of the warning of the first call.
    static let firstMessage = "first warning"

    /// The message of the warning of the second call.
    static let secondMessage = "second warning"

    // MARK: - Helpers

    /// Adds the test field `warn(message:)` to the root query type of the public schema: the ``SchemaExtension`` of
    /// each test.
    ///
    /// - Parameter builder: The builder of the public schema.
    /// - Returns: The builder, with the test field.
    static func addWarnField(
        to builder: SchemaBuilder<KanbanResolver, KanbanContext>
    ) -> SchemaBuilder<KanbanResolver, KanbanContext> {
        builder.addQuery {
            Field("warn", at: KanbanResolver.warn) {
                Argument("message", at: \.message)
            }
        }
    }

    /// Gives a document that runs the test field one time.
    ///
    /// - Parameter message: The message of the warning.
    /// - Returns: The document.
    static func warnQuery(_ message: String) -> String {
        #"{ warn(message: "\#(message)") }"#
    }

    /// Makes a test engine whose public schema has the test field, for an empty repo.
    ///
    /// - Parameter directory: The temporary directory of the repo.
    /// - Returns: The engine.
    static func makeWarningGraph(in directory: TemporaryDirectory) throws -> KanbanGraph {
        try KanbanGraphTests.makeGraph(
            at: KanbanGraphTests.makeEmptyRepo(in: directory),
            extendingSchemaWith: addWarnField
        )
    }

    /// Reads the `extensions.warnings` of a response.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The message and the code of each warning, in the order of the list.
    static func warnings(of response: String) throws -> [(message: String?, code: String?)] {
        let extensions = try #require(KanbanGraphTests.object(of: response)["extensions"] as? [String: Any])
        let warnings = try #require(extensions["warnings"] as? [[String: Any]], "\(response)")
        return warnings.map { warning in (warning["message"] as? String, warning["code"] as? String) }
    }

    // MARK: - Tests

    @Test("A warning of a call is in extensions.warnings with its message and its code")
    func warningIsInResponse() async throws {
        let directory = try TemporaryDirectory()
        let graph = try Self.makeWarningGraph(in: directory)
        let response = try await KanbanGraphTests.execute(Self.warnQuery(Self.firstMessage), on: graph)
        let warnings = try Self.warnings(of: response)
        #expect(warnings.map(\.message) == [Self.firstMessage])
        #expect(warnings.map(\.code) == [Self.warningCode])
        #expect((try KanbanGraphTests.object(of: response)["data"] as? [String: Any])?["warn"] as? String
            == Self.firstMessage)
    }

    @Test("Two fields of one call give two warnings in the one list")
    func twoFieldsGiveTwoWarnings() async throws {
        let document = #"""
            { first: warn(message: "\#(Self.firstMessage)") second: warn(message: "\#(Self.secondMessage)") }
            """#
        let response = try await QueryFixture().respond(to: document, extendedWith: Self.addWarnField)
        let messages = try Self.warnings(of: response).compactMap(\.message)
        #expect(messages.sorted() == [Self.firstMessage, Self.secondMessage].sorted())
    }

    @Test("A call with no warning has no extensions.warnings key")
    func noWarningGivesNoKey() async throws {
        let directory = try TemporaryDirectory()
        let graph = try Self.makeWarningGraph(in: directory)
        let response = try await KanbanGraphTests.execute(KanbanGraphTests.nameQuery, on: graph)
        #expect(try KanbanGraphTests.object(of: response)["extensions"] == nil)
    }

    @Test("A call with a rewrite and no warning has extensions.rewrites and no extensions.warnings")
    func rewriteWithoutWarningGivesNoWarningsKey() async throws {
        let response = try await QueryFixture().respond(
            to: "{ board { title: name } tasks { totalCount } }",
            extendedWith: Self.addWarnField
        )
        let extensions = try #require(KanbanGraphTests.object(of: response)["extensions"] as? [String: Any])
        #expect(extensions["rewrites"] != nil)
        #expect(extensions["warnings"] == nil)
    }

    @Test("Two calls of one engine at the same time each get only their own warning")
    func concurrentCallsOfEngineKeepTheirWarnings() async throws {
        let directory = try TemporaryDirectory()
        let graph = try Self.makeWarningGraph(in: directory)
        async let first = KanbanGraphTests.execute(Self.warnQuery(Self.firstMessage), on: graph)
        async let second = KanbanGraphTests.execute(Self.warnQuery(Self.secondMessage), on: graph)
        let responses = try await (first, second)
        #expect(try Self.warnings(of: responses.0).map(\.message) == [Self.firstMessage])
        #expect(try Self.warnings(of: responses.1).map(\.message) == [Self.secondMessage])
    }

    @Test("Two runs of one schema at the same time, with no serial gate, each get only their own warning")
    func concurrentRunsOfSchemaKeepTheirWarnings() async throws {
        let fixture = try QueryFixture()
        async let first = fixture.respond(to: Self.warnQuery(Self.firstMessage), extendedWith: Self.addWarnField)
        async let second = fixture.respond(to: Self.warnQuery(Self.secondMessage), extendedWith: Self.addWarnField)
        let responses = try await (first, second)
        #expect(try Self.warnings(of: responses.0).map(\.message) == [Self.firstMessage])
        #expect(try Self.warnings(of: responses.1).map(\.message) == [Self.secondMessage])
    }

    @Test("The result of the kanban tool shows the warning text")
    func toolResultShowsWarning() async throws {
        let directory = try TemporaryDirectory()
        let tool = KanbanTool(graph: try Self.makeWarningGraph(in: directory))
        let output = try await KanbanToolTests.call(tool, query: Self.warnQuery(Self.firstMessage), variables: nil)
        #expect(try Self.warnings(of: output).map(\.message) == [Self.firstMessage])
    }
}
