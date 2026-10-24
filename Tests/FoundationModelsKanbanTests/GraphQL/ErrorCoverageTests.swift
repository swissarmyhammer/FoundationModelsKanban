import Foundation
import FoundationModelsExtras
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
@Suite("Error codes through execute", .watcherBudget)
struct ErrorCoverageTests {
    /// A document with a syntax error: the selection set of the operation does not close.
    static let syntaxErrorDocument = "{ board { name }"

    /// A document with a field that `Board` does not have. The rewrite matches no name, so validation fails.
    static let unknownFieldDocument = "{ board { nmae } }"

    /// A document with a name that the rewrite matches to two names of `Board`: `task` and `tasks`.
    static let tieDocument = "{ board { taskz } }"

    /// The key of the code in the extensions object of a GraphQL error.
    static let codeKey = "code"

    /// A filter that does not parse: `&&` at the end has no term after it.
    static let unfinishedFilter = "#bug &&"

    /// The span of the error of ``unfinishedFilter``: the `&&`, in characters, with the end exclusive.
    static let unfinishedFilterSpan = 5..<7

    /// A filter that does not parse, with an emoji before the error. The emoji is one character and two UTF-16 units.
    static let emojiFilter = "#🐛 &&"

    /// The span of the error of ``emojiFilter``: the `&&`, in characters, with the end exclusive. In UTF-16 units, the
    /// span is `4..<6`.
    static let emojiFilterSpan = 3..<5

    /// Each filter of the span test, with the span of its error.
    static let filterSpans = [(unfinishedFilter, unfinishedFilterSpan), (emojiFilter, emojiFilterSpan)]

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
        #expect(try KanbanGraphTests.data(of: response)[field] is NSNull)
        let errors = try NameRewriteTests.errors(of: response)
        #expect(errors.count == 1)
        let error = try #require(errors.first)
        #expect(error["message"] as? String == expected.message)
        #expect(error["path"] as? [String] == [field])
        #expect(Self.code(of: error) == code)
    }

    /// Gives the JSON text of one error of a response, with the keys in sorted order: `extensions`, the location of
    /// the field that failed, the message of the error, and the path.
    ///
    /// - Parameters:
    ///   - error: The error that gives the message.
    ///   - extensions: The JSON text of the `extensions` object, for example `{"code":"NOT_FOUND"}`.
    ///   - field: The name of the field that failed. The location is the first place of this name in the document.
    ///   - document: The GraphQL document, on one line.
    ///   - path: The JSON text of the path, for example `["board","tasks"]`.
    /// - Returns: The JSON text of the error.
    /// - Throws: An error when the document does not hold the field.
    static func errorJSON(
        of error: KanbanError,
        extensions: String,
        at field: String,
        in document: String,
        path: String
    ) throws -> String {
        let start = try #require(document.range(of: field)).lowerBound
        let column = document.distance(from: document.startIndex, to: start) + 1
        let message = try KanbanArgumentsTests.jsonLiteral(of: error.message)
        return #"{"extensions":\#(extensions),"locations":[{"column":\#(column),"line":1}],"#
            + #""message":\#(message),"path":\#(path)}"#
    }

    /// Gives the JSON text of the start and the end of a span, as `extensions` gives them.
    ///
    /// - Parameter span: The span, in characters, with the end exclusive.
    /// - Returns: The JSON text of the two keys, for example `"end":7,"start":5`.
    static func spanJSON(of span: Range<Int>) -> String {
        #""end":\#(span.upperBound),"start":\#(span.lowerBound)"#
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
        let matches = added.map { task in
            KanbanError.AmbiguousMatch(id: AddUpdateTaskTests.sigilRef(of: task), title: AddUpdateTaskTests.title)
        }
        let expected = KanbanError.ambiguousID(reference: prefix, matches: matches)
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

    @Test(
        "INVALID_FILTER of tasks(filter:) gives the span of the error in characters in extensions.start and end",
        arguments: filterSpans
    )
    func invalidFilterGivesTheSpan(filter: String, span: Range<Int>) async throws {
        let document = #"{ board { tasks(filter: "\#(filter)") { totalCount } } }"#
        let response = try await ColumnActorTests.respond(to: document, onFixtureIn: TemporaryDirectory())
        let expected = try #require(throws: KanbanError.self) {
            try FilterExpr(parsing: filter)
        }
        let error = try Self.errorJSON(
            of: expected,
            extensions: #"{"code":"INVALID_FILTER",\#(Self.spanJSON(of: span))}"#,
            at: "tasks",
            in: document,
            path: #"["board","tasks"]"#
        )
        #expect(response == #"{"data":{"board":{"tasks":null}},"errors":[\#(error)]}"#)
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

    @Test("A resolver error that is not a CodedError gives INTERNAL, with the message of the engine")
    func internalFailure() {
        let fault = EventError.malformed(detail: "the line is not JSON")
        let error = GraphQLError(
            message: String(describing: fault),
            path: IndexPath([MutationName.addTask]),
            originalError: fault
        )
        let coded = error.codedAsResultError()
        #expect(coded.extensions[Self.codeKey] == .string("INTERNAL"))
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
        let added = try KanbanGraphTests.data(of: response)["addColumn"] as? [String: String]
        #expect(added == ["id": ColumnActorTests.id(of: ColumnActorTests.qaColumn)])
        let expected = deleteTodo.expected
        try Self.expectFailure(of: "deleteColumn", in: response, giving: expected, coded: "COLUMN_NOT_EMPTY")
        #expect(try ColumnActorTests.patches(of: ColumnActorTests.qaColumn, in: directory).map(\.node) == [
            ColumnActorTests.qaColumn,
        ])
        #expect(try !ColumnActorTests.lastPatch(of: KanbanGraphTests.todoColumn, isDelete: true, in: directory))
    }
}
