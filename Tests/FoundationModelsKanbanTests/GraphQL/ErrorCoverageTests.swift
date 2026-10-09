import Foundation
import GraphQL
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests that each error code of a public mutation or query comes back through `KanbanGraph.execute` in the GraphQL
/// form of plan.md §4.4: one item in `errors` with `message`, `path`, and `extensions.code`, and `null` for the field
/// that failed.
///
/// Each test runs a document on the fixture logs of ``KanbanGraphTests``: the board, the column `todo`, and one task
/// in `todo`. A test that `execute` throws for fails, so each test also proves that a GraphQL error does not throw.
/// The undo, commit, and tool tests cover the other codes of the catalog.
@Suite("Error codes through execute")
struct ErrorCoverageTests {
    /// A document with a syntax error: the selection set of the operation does not close.
    static let syntaxErrorDocument = "{ board { name }"

    /// A document with a field that `Board` does not have. The rewrite matches no name, so validation fails.
    static let unknownFieldDocument = "{ board { nmae } }"

    /// A document with a name that the rewrite matches to two names of `Board`: `task` and `tasks`.
    static let tieDocument = "{ board { taskz } }"

    // MARK: - Helpers

    /// Runs a document through `KanbanGraph.execute` on a new engine of the fixture repo, and expects that the call
    /// fails as a whole: the response has no `data` and one error with the code.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - code: The code that `extensions.code` must give, for example `GRAPHQL_PARSE_FAILED`.
    /// - Throws: An error when the response has no `errors` list.
    static func expectRequestFailure(of document: String, coded code: String) async throws {
        let response = try await ColumnActorTests.respond(to: document, onFixtureIn: TemporaryDirectory())
        #expect(try KanbanGraphTests.object(of: response)["data"] == nil)
        let errors = try NameRewriteTests.errors(of: response)
        #expect(errors.count == 1)
        #expect(errors.first.map(Self.code(of:)) == code)
    }

    /// Gives the `extensions.code` of one error of a response.
    ///
    /// - Parameter error: The error object.
    /// - Returns: The code, or `nil` when the error has no code.
    static func code(of error: [String: Any]) -> String? {
        (error["extensions"] as? [String: Any])?["code"] as? String
    }

    /// Expects that a response has one error, from a root field that failed with a ``KanbanError``.
    ///
    /// - Parameters:
    ///   - field: The response key of the root field that failed.
    ///   - response: The response JSON text.
    ///   - expected: The error that the field must give. The message of the response must be its message.
    ///   - code: The code that `extensions.code` must give, for example `NOT_FOUND`.
    /// - Throws: An error when the response has no `data` object or no `errors` list.
    static func expectFailure(
        of field: String,
        in response: String,
        giving expected: KanbanError,
        coded code: String
    ) throws {
        #expect(try NameRewriteTests.data(of: response)[field] is NSNull)
        let errors = try NameRewriteTests.errors(of: response)
        #expect(errors.count == 1)
        let error = try #require(errors.first)
        #expect(error["message"] as? String == expected.message)
        #expect(error["path"] as? [String] == [field])
        #expect(Self.code(of: error) == code)
    }

    /// Runs a mutation document with one field on a new engine of the fixture repo.
    ///
    /// - Parameter field: The mutation field, with its selection.
    /// - Returns: The response JSON text.
    static func respond(toMutationOf field: String) async throws -> String {
        try await ColumnActorTests.respond(
            to: AddUpdateTaskTests.mutation(of: field),
            onFixtureIn: TemporaryDirectory()
        )
    }

    /// Makes the `deleteColumn` field that names the fixture column `todo`. The column holds the fixture task, so the
    /// field fails with `COLUMN_NOT_EMPTY`.
    ///
    /// - Returns: The field, and the error that it must give.
    /// - Throws: An error when the fixture column has no slug.
    static func deleteTodoField() throws -> (field: String, expected: KanbanError) {
        let column = try #require(KanbanGraphTests.todoColumn.localID)
        let expected = KanbanError.columnNotEmpty(column: column, liveTaskCount: ColumnActorTests.fixtureTaskCount)
        return (CommentTests.nodeField("deleteColumn", naming: column), expected)
    }

    // MARK: - One test for each code

    @Test("NOT_FOUND comes back with its message, the path, and extensions.code")
    func notFound() async throws {
        let reference = try #require(ColumnActorTests.qaColumn.localID)
        let response = try await Self.respond(toMutationOf: CommentTests.nodeField("updateColumn", naming: reference))
        let expected = KanbanError.notFound(type: .column, reference: reference)
        try Self.expectFailure(of: "updateColumn", in: response, giving: expected, coded: "NOT_FOUND")
    }

    @Test("AMBIGUOUS_ID comes back with its message, the path, and extensions.code")
    func ambiguousID() async throws {
        let directory = try TemporaryDirectory()
        let graph = try ColumnActorTests.makeFixtureGraph(in: directory).graph
        let setup = AddUpdateTaskTests.mutation(
            of: "first: " + AddUpdateTaskTests.addTask(with: ""),
            "second: " + AddUpdateTaskTests.addTask(with: "")
        )
        let added = try await AddUpdateTaskTests.addedTasks(by: setup, on: graph)
        let (first, second) = (try #require(added.first), try #require(added.last))
        let prefix = String(zip(first.ulidString, second.ulidString).prefix { pair in pair.0 == pair.1 }.map(\.0))
        let response = try await KanbanGraphTests.execute(#"{ node(id: "\#(prefix)") { id } }"#, on: graph)
        let expected = KanbanError.ambiguousID(reference: prefix, matches: added.map(ShortID.init(of:)))
        try Self.expectFailure(of: "node", in: response, giving: expected, coded: "AMBIGUOUS_ID")
    }

    @Test("ACTOR_NOT_FOUND comes back with its message, the path, and extensions.code")
    func actorNotFound() async throws {
        let input = "assignees: \(AddUpdateTaskTests.list(of: [AddUpdateTaskTests.unknownActor]))"
        let response = try await Self.respond(toMutationOf: AddUpdateTaskTests.addTask(with: input))
        let expected = KanbanError.actorNotFound(reference: AddUpdateTaskTests.unknownActor)
        try Self.expectFailure(of: "addTask", in: response, giving: expected, coded: "ACTOR_NOT_FOUND")
    }

    @Test("DUPLICATE_ID comes back with its message, the path, and extensions.code")
    func duplicateID() async throws {
        let field = #"addColumn(input: { name: "\#(KanbanGraphTests.todoName)" }) { id }"#
        let response = try await Self.respond(toMutationOf: field)
        let expected = KanbanError.duplicateID(type: .column, id: try #require(KanbanGraphTests.todoColumn.localID))
        try Self.expectFailure(of: "addColumn", in: response, giving: expected, coded: "DUPLICATE_ID")
    }

    @Test("COLUMN_NOT_EMPTY comes back with its message, the path, and extensions.code")
    func columnNotEmpty() async throws {
        let deleteTodo = try Self.deleteTodoField()
        let response = try await Self.respond(toMutationOf: deleteTodo.field)
        let expected = deleteTodo.expected
        try Self.expectFailure(of: "deleteColumn", in: response, giving: expected, coded: "COLUMN_NOT_EMPTY")
    }

    @Test("DEPENDENCY_CYCLE comes back with its message, the path, and extensions.code")
    func dependencyCycle() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let setup = AddUpdateTaskTests.mutation(
            of: AddUpdateTaskTests.addTask(with: AddUpdateTaskTests.dependsOn(fixture.task))
        )
        let dependent = try #require(try await AddUpdateTaskTests.addedTasks(by: setup, on: fixture.graph).first)
        let closeCycle = AddUpdateTaskTests.updateTask(fixture.task, with: AddUpdateTaskTests.dependsOn(dependent))
        let response = try await CommentTests.run(closeCycle, on: fixture.graph)
        let path = [fixture.task, dependent, fixture.task].map(AddUpdateTaskTests.sigilRef(of:))
        let expected = KanbanError.dependencyCycle(path: path)
        try Self.expectFailure(of: "updateTask", in: response, giving: expected, coded: "DEPENDENCY_CYCLE")
    }

    @Test("TAG_RENAME_CYCLE comes back with its message, the path, and extensions.code")
    func tagRenameCycle() async throws {
        let directory = try TemporaryDirectory()
        let graph = try ColumnActorTests.makeFixtureGraph(in: directory).graph
        _ = try await KanbanGraphTests.execute(TagMutationTests.renameBugToDefect, on: graph)
        let rename = TagMutationTests.renameTag(from: TagMutationTests.defect, to: TagMutationTests.bug)
        let response = try await CommentTests.run(rename, on: graph)
        let expected = KanbanError.tagRenameCycle(
            path: [TagMutationTests.defect, TagMutationTests.bug, TagMutationTests.defect]
        )
        try Self.expectFailure(of: "renameTag", in: response, giving: expected, coded: "TAG_RENAME_CYCLE")
    }

    @Test("INVALID_FILTER comes back with its message, the path, and extensions.code")
    func invalidFilter() async throws {
        let response = try await ColumnActorTests.respond(
            to: #"{ tasks(filter: "\#(NameRewriteTests.invalidFilter)") { totalCount } }"#,
            onFixtureIn: TemporaryDirectory()
        )
        let expected = try #require(throws: KanbanError.self) {
            try FilterExpr(parsing: NameRewriteTests.invalidFilter)
        }
        try Self.expectFailure(of: "tasks", in: response, giving: expected, coded: "INVALID_FILTER")
    }

    @Test("INVALID_TAG_NAME comes back with its message, the path, and extensions.code")
    func invalidTagName() async throws {
        let response = try await Self.respond(
            toMutationOf: TagMutationTests.addTag(named: ColumnActorTests.emptySlugName)
        )
        let expected = KanbanError.invalidTagName(name: ColumnActorTests.emptySlugName)
        try Self.expectFailure(of: "addTag", in: response, giving: expected, coded: "INVALID_TAG_NAME")
    }

    @Test("INVALID_SLUG comes back with its message, the path, and extensions.code")
    func invalidSlug() async throws {
        let field = #"addColumn(input: { name: "\#(ColumnActorTests.emptySlugName)" }) { id }"#
        let response = try await Self.respond(toMutationOf: field)
        let expected = KanbanError.invalidSlug(name: ColumnActorTests.emptySlugName)
        try Self.expectFailure(of: "addColumn", in: response, giving: expected, coded: "INVALID_SLUG")
    }

    @Test("INVALID_ORDINAL comes back with its message, the path, and extensions.code")
    func invalidOrdinal() async throws {
        let input = #"ordinal: "\#(AddUpdateTaskTests.invalidOrdinal)""#
        let response = try await Self.respond(toMutationOf: AddUpdateTaskTests.addTask(with: input))
        let expected = KanbanError.invalidOrdinal(ordinal: AddUpdateTaskTests.invalidOrdinal)
        try Self.expectFailure(of: "addTask", in: response, giving: expected, coded: "INVALID_ORDINAL")
    }

    // MARK: - Codes of the parse, validation, and rewrite

    @Test("A document with a syntax error gives one error with GRAPHQL_PARSE_FAILED")
    func parseFailed() async throws {
        try await Self.expectRequestFailure(of: Self.syntaxErrorDocument, coded: "GRAPHQL_PARSE_FAILED")
    }

    @Test("A document with an unknown field gives one error with GRAPHQL_VALIDATION_FAILED")
    func validationFailed() async throws {
        try await Self.expectRequestFailure(of: Self.unknownFieldDocument, coded: "GRAPHQL_VALIDATION_FAILED")
    }

    @Test("A name that ties in the rewrite gives one error with AMBIGUOUS_NAME")
    func ambiguousName() async throws {
        try await Self.expectRequestFailure(of: Self.tieDocument, coded: "AMBIGUOUS_NAME")
    }

    @Test("A resolver error that is not a KanbanError gives INTERNAL, with the message of the engine")
    func internalFailure() {
        let fault = EventError.malformed(detail: "the line is not JSON")
        let error = GraphQLError(
            message: String(describing: fault),
            path: IndexPath([MutationName.addTask]),
            originalError: fault
        )
        let coded = error.codedAsResultError()
        let codeKey = KanbanError.ResponseError.Extensions.CodingKeys.code.stringValue
        #expect(coded.extensions[codeKey] == .string("INTERNAL"))
        #expect(coded.message == error.message)
        #expect(coded.path.elements.count == error.path.elements.count)
    }

    // MARK: - Partial result

    @Test("When the second of two mutation fields fails, the first writes its patches and returns its data")
    func firstFieldKeepsItsResultWhenSecondFails() async throws {
        let directory = try TemporaryDirectory()
        let deleteTodo = try Self.deleteTodoField()
        let mutation = AddUpdateTaskTests.mutation(of: ColumnActorTests.addQA, deleteTodo.field)
        let response = try await ColumnActorTests.respond(to: mutation, onFixtureIn: directory)
        let added = try NameRewriteTests.data(of: response)["addColumn"] as? [String: String]
        #expect(added == ["id": ColumnActorTests.id(of: ColumnActorTests.qaColumn)])
        let expected = deleteTodo.expected
        try Self.expectFailure(of: "deleteColumn", in: response, giving: expected, coded: "COLUMN_NOT_EMPTY")
        #expect(try ColumnActorTests.patches(of: ColumnActorTests.qaColumn, in: directory).map(\.node) == [
            ColumnActorTests.qaColumn,
        ])
        #expect(try !ColumnActorTests.lastPatch(of: KanbanGraphTests.todoColumn, isDelete: true, in: directory))
    }
}
