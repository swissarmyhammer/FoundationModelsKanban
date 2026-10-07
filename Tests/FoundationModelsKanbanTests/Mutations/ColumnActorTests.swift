import Foundation
import GraphQL
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the column and the actor mutations (plan.md §4.2, §6).
///
/// These tests are the GraphQL form of the Rust column and actor dispatch tests
/// (`dispatch/tests/board_columns.rs`, `dispatch/tests/actors_tags.rs`) and of the duplicate, not-empty, and not-found
/// tests of `column/add.rs`, `column/delete.rs`, and `actor/add.rs`. Each test uses the fixture logs of
/// ``KanbanGraphTests``: the board, the column `todo` with order 0, and one task in `todo`.
///
/// One rule is different from Rust: `addActor(ensure: true)` on an actor that exists writes nothing. The Rust code
/// updated a changed name or color.
@Suite("Column and actor mutations")
struct ColumnActorTests {
    /// The slug of the column that a test adds.
    private static let qaSlug = "qa"

    /// The name of the column that a test adds.
    private static let qaName = "QA"

    /// The order of the added column when the call gives no order: one after the order 0 of `todo`.
    private static let nextOrder = 1

    /// An order that a test gives.
    private static let givenOrder = 5

    /// The new name of `todo` in the update test.
    private static let backlogName = "Backlog"

    /// The body that a test gives to a column or an actor.
    static let body = "Tasks that wait for a check.\n"

    /// ``body`` as a JSON string value shows it, with the line end escaped.
    static let bodyJSON = body.replacingOccurrences(of: "\n", with: "\\n")

    /// The variables that give ``body`` to the variable `$body`.
    static let bodyVariables: [String: Map] = ["body": .string(body)]

    /// The name that gives an empty slug.
    static let emptySlugName = "---"

    /// The slug of the actor that a test adds.
    private static let aliceSlug = "alice"

    /// The name of the actor that a test adds.
    private static let aliceName = "Alice Smith"

    /// The new name of the actor in the update test.
    private static let renamedAlice = "Alice Jones"

    /// The color of the actor that a test adds.
    static let red = "ff0000"

    /// The color of the actor after the update test.
    static let green = "00ff00"

    /// The number of live tasks in `todo` in the fixture.
    private static let fixtureTaskCount = 1

    /// The local ref of the added column.
    private static let qaColumn = LocalRef.column(slug: qaSlug)

    /// The local ref of the added actor.
    private static let alice = LocalRef.actor(slug: aliceSlug)

    /// The mutation field that adds the column ``qaName`` with no order.
    private static let addQA = #"addColumn(input: { name: "\#(qaName)" }) { id }"#

    /// The mutation field that adds the actor ``aliceName`` with the color ``red``.
    private static let addAliceField = #"addActor(input: { id: "\#(aliceSlug)", name: "\#(aliceName)", "#
        + #"color: "\#(red)" }) { id name color }"#

    /// The mutation that adds the actor ``aliceName`` with the color ``red``.
    private static let addAlice = "mutation { \(addAliceField) }"

    /// The `input` argument that names the added column.
    private static let qaReference = #"input: { id: "\#(qaSlug)" }"#

    /// The `input` argument that names the added actor.
    private static let aliceReference = #"input: { id: "\#(aliceSlug)" }"#

    // MARK: - Helpers

    /// Gives the full URI of a node of the fixture board, as the GraphQL `ID` shows it.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The URI text.
    static func id(of ref: LocalRef) -> String {
        NodeURI(boardKey: KanbanGraphTests.boardKey.description, ref: ref).description
    }

    /// Writes the fixture logs to a temporary repo, and makes a new engine for the repo.
    ///
    /// - Parameter directory: The temporary repo directory.
    /// - Returns: The engine, and the ULID of the fixture task.
    static func makeFixtureGraph(in directory: TemporaryDirectory) throws -> (graph: KanbanGraph, task: ULID) {
        let task = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        return (try KanbanGraphTests.makeGraph(at: directory.url), task)
    }

    /// Runs one document on a new engine of the fixture repo.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - variables: The values of the variables of the document. The default is no variables.
    ///   - directory: The temporary repo directory.
    /// - Returns: The response JSON text.
    static func respond(
        to document: String,
        with variables: [String: Map] = [:],
        onFixtureIn directory: TemporaryDirectory
    ) async throws -> String {
        try await KanbanGraphTests.execute(document, variables: variables, on: makeFixtureGraph(in: directory).graph)
    }

    /// Runs a setup document on a new engine of the fixture repo, then runs a body, and expects that the body writes
    /// no log file.
    ///
    /// - Parameters:
    ///   - setup: A document that runs before the body, or `nil` for none.
    ///   - directory: The temporary repo directory.
    ///   - body: Gets the engine, the event log of the board, and the response of the setup document, and gives the
    ///     result.
    /// - Returns: The result of the body.
    private static func runWritingNothing<Result>(
        after setup: String?,
        in directory: TemporaryDirectory,
        _ body: (KanbanGraph, EventLog, String) async throws -> Result
    ) async throws -> Result {
        let graph = try makeFixtureGraph(in: directory).graph
        let setupResponse = try await KanbanGraphTests.execute(setup ?? KanbanGraphTests.nameQuery, on: graph)
        let log = EventLog(repositoryAt: directory.url)
        let before = try log.nodeFileSignatures()
        let result = try await body(graph, log, setupResponse)
        #expect(try log.nodeFileSignatures() == before)
        return result
    }

    /// Runs one document in a commit session of a board, so that a test can read the ``KanbanError`` that a resolver
    /// threw.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - session: The commit session of the board.
    /// - Returns: The result of the document.
    static func result(of document: String, in session: inout CommitSession) async throws -> GraphQLResult {
        try await session.run { store in
            let context = KanbanContext(store: store, clock: { CommitTests.callTime })
            return try await PublicSchema().execute(request: document, context: context)
        }
    }

    /// Runs one mutation that fails on the fixture repo, and gives its error.
    ///
    /// The setup document runs first, on an engine. Then the mutation runs in a commit session of the board, so that
    /// the test can read the ``KanbanError`` that the resolver threw. The helper expects that the mutation writes no
    /// log file.
    ///
    /// - Parameters:
    ///   - setup: A document that runs before the mutation, or `nil` for none.
    ///   - directory: The temporary repo directory.
    ///   - makeMutation: Gives the GraphQL document that fails, from the response of the setup document.
    /// - Returns: The error of the first GraphQL error of the response.
    static func failure(
        after setup: String?,
        in directory: TemporaryDirectory,
        of makeMutation: (String) throws -> String
    ) async throws -> KanbanError {
        let error = try await runWritingNothing(after: setup, in: directory) { _, log, setupResponse in
            var session = try await CommitTests.makeSession(of: log)
            let result = try await result(of: makeMutation(setupResponse), in: &session)
            return result.errors.first?.originalError as? KanbanError
        }
        return try #require(error)
    }

    /// Runs one mutation that fails on the fixture repo, and gives its error. See
    /// ``failure(after:in:of:)``.
    ///
    /// - Parameters:
    ///   - mutation: The GraphQL document that fails.
    ///   - setup: A document that runs before the mutation, or `nil` for none.
    ///   - directory: The temporary repo directory.
    /// - Returns: The error of the first GraphQL error of the response.
    static func failure(
        of mutation: String,
        after setup: String? = nil,
        in directory: TemporaryDirectory
    ) async throws -> KanbanError {
        try await failure(after: setup, in: directory) { _ in mutation }
    }

    /// Runs one document on the fixture repo, and expects that it writes no log file.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - setup: A document that runs before it, on the same engine, or `nil` for none.
    ///   - directory: The temporary repo directory.
    /// - Returns: The response JSON text of the document.
    static func respondWritingNothing(
        to document: String,
        after setup: String? = nil,
        in directory: TemporaryDirectory
    ) async throws -> String {
        try await runWritingNothing(after: setup, in: directory) { graph, _, _ in
            try await KanbanGraphTests.execute(document, on: graph)
        }
    }

    /// Gives the patches of the log of a node in the repo of a temporary directory.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the node.
    ///   - directory: The temporary repo directory.
    /// - Returns: The patches, in the order of their events.
    static func patches(of ref: LocalRef, in directory: TemporaryDirectory) throws -> [PatchInput] {
        try BoardMutationTests.events(of: ref, inRepoAt: directory.url).map(\.patch)
    }

    /// Tells if the last patch of a node is a `delete` patch with a value.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the node.
    ///   - isDeleted: The `delete` value: `true` for a delete, `false` for an undelete.
    ///   - directory: The temporary repo directory.
    /// - Returns: `true` when the last patch of the node is only the `delete` part with the value.
    static func lastPatch(
        of ref: LocalRef,
        isDelete isDeleted: Bool,
        in directory: TemporaryDirectory
    ) throws -> Bool {
        try patches(of: ref, in: directory).last == PatchInput(node: ref, delete: isDeleted)
    }

    /// Gives a patch that sets some values of a node, and gives ``body`` to the node in place of an empty body.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the node.
    ///   - values: The `set` part of the patch.
    /// - Returns: The patch, with the body diff in its `edit` part.
    static func bodyPatch(of ref: LocalRef, setting values: [String: PatchValue]) throws -> PatchInput {
        try PatchInput(node: ref, set: values, edit: PatchEdit(body: ReplayTests.diff(from: "", to: body)))
    }

    /// Gives the `set` part of a patch that sets a name and an order.
    ///
    /// - Parameters:
    ///   - name: The name.
    ///   - order: The order.
    /// - Returns: The `set` part.
    private static func setting(name: String, order: Int) -> [String: PatchValue] {
        [PropertyName.name: .json(.string(name)), PropertyName.order: .json(.number(Number(order)))]
    }

    /// Gives the `set` part of a patch that sets a name and a color.
    ///
    /// - Parameters:
    ///   - name: The name.
    ///   - color: The color.
    /// - Returns: The `set` part.
    static func setting(name: String, color: String) -> [String: PatchValue] {
        [PropertyName.name: .json(.string(name)), PropertyName.color: .json(.string(color))]
    }

    // MARK: - addColumn

    @Test("addColumn with an id and a name makes the column after the last column, and returns it")
    func addColumnAppendsColumn() async throws {
        let directory = try TemporaryDirectory()
        let mutation = #"mutation { addColumn(input: { id: "\#(Self.qaSlug)", name: "\#(Self.qaName)" }) "#
            + "{ id name order } }"
        let response = try await Self.respond(to: mutation, onFixtureIn: directory)
        let column = #"{"id":"\#(Self.id(of: Self.qaColumn))","name":"\#(Self.qaName)","#
            + #""order":\#(Self.nextOrder)}"#
        #expect(response == #"{"data":{"addColumn":\#(column)}}"#)
        let set = Self.setting(name: Self.qaName, order: Self.nextOrder)
        #expect(try Self.patches(of: Self.qaColumn, in: directory) == [PatchInput(node: Self.qaColumn, set: set)])
    }

    @Test("addColumn with an order and a body writes one patch with the name, the order, and the body diff")
    func addColumnWithOrderAndBody() async throws {
        let directory = try TemporaryDirectory()
        let mutation = "mutation($body: String) { addColumn(input: "
            + #"{ id: "\#(Self.qaSlug)", name: "\#(Self.qaName)", order: \#(Self.givenOrder), body: $body }) "#
            + "{ order body } }"
        let response = try await Self.respond(to: mutation, with: Self.bodyVariables, onFixtureIn: directory)
        let column = #"{"body":"\#(Self.bodyJSON)","order":\#(Self.givenOrder)}"#
        #expect(response == #"{"data":{"addColumn":\#(column)}}"#)
        let set = Self.setting(name: Self.qaName, order: Self.givenOrder)
        let expected = try Self.bodyPatch(of: Self.qaColumn, setting: set)
        #expect(try Self.patches(of: Self.qaColumn, in: directory) == [expected])
    }

    @Test("addColumn with only a name uses the slug of the name as the id")
    func addColumnSlugsName() async throws {
        let directory = try TemporaryDirectory()
        let mutation = #"mutation { addColumn(input: { name: "In QA" }) { id } }"#
        let response = try await Self.respond(to: mutation, onFixtureIn: directory)
        #expect(response == #"{"data":{"addColumn":{"id":"\#(Self.id(of: .column(slug: "in-qa")))"}}}"#)
    }

    @Test("addColumn with the slug of a column that exists gives DUPLICATE_ID and writes nothing")
    func addColumnDuplicate() async throws {
        let directory = try TemporaryDirectory()
        let error = try await Self.failure(
            of: #"mutation { addColumn(input: { name: "\#(KanbanGraphTests.todoName)" }) { id } }"#,
            in: directory
        )
        #expect(error == .duplicateID(type: .column, id: "todo"))
    }

    @Test("addColumn with a name that gives an empty slug gives INVALID_SLUG and writes nothing")
    func addColumnInvalidSlug() async throws {
        let directory = try TemporaryDirectory()
        let error = try await Self.failure(
            of: #"mutation { addColumn(input: { name: "\#(Self.emptySlugName)" }) { id } }"#,
            in: directory
        )
        #expect(error == .invalidSlug(name: Self.emptySlugName))
    }

    // MARK: - updateColumn

    @Test("updateColumn changes the name and the order, and keeps the id")
    func updateColumnChangesNameAndOrder() async throws {
        let directory = try TemporaryDirectory()
        let mutation = #"mutation { updateColumn(input: { id: "todo", name: "\#(Self.backlogName)", "#
            + "order: \(Self.givenOrder) }) { id name order } }"
        let response = try await Self.respond(to: mutation, onFixtureIn: directory)
        let todo = Self.id(of: KanbanGraphTests.todoColumn)
        let column = #"{"id":"\#(todo)","name":"\#(Self.backlogName)","order":\#(Self.givenOrder)}"#
        #expect(response == #"{"data":{"updateColumn":\#(column)}}"#)
        let expected = try PatchInput(
            node: KanbanGraphTests.todoColumn,
            set: Self.setting(name: Self.backlogName, order: Self.givenOrder)
        )
        #expect(try Self.patches(of: KanbanGraphTests.todoColumn, in: directory).last == expected)
    }

    @Test("updateColumn with the current name and body writes no patch, and also no actor patch")
    func updateColumnNoOp() async throws {
        let directory = try TemporaryDirectory()
        let mutation = #"mutation { updateColumn(input: { id: "todo", name: "\#(KanbanGraphTests.todoName)", "#
            + #"body: "" }) { name } }"#
        let response = try await Self.respondWritingNothing(to: mutation, in: directory)
        #expect(response == #"{"data":{"updateColumn":{"name":"\#(KanbanGraphTests.todoName)"}}}"#)
    }

    @Test("updateColumn with a null name writes an unset of the name, and a missing order does not change")
    func updateColumnNullNameUnsetsName() async throws {
        let directory = try TemporaryDirectory()
        let mutation = #"mutation { updateColumn(input: { id: "todo", name: null }) { name order } }"#
        let response = try await Self.respond(to: mutation, onFixtureIn: directory)
        #expect(response == #"{"data":{"updateColumn":{"name":"","order":0}}}"#)
        let expected = try PatchInput(node: KanbanGraphTests.todoColumn, unset: [PropertyName.name])
        #expect(try Self.patches(of: KanbanGraphTests.todoColumn, in: directory).last == expected)
    }

    @Test("updateColumn with an id that names no column gives NOT_FOUND and writes nothing")
    func updateColumnNotFound() async throws {
        let directory = try TemporaryDirectory()
        let error = try await Self.failure(
            of: #"mutation { updateColumn(\#(Self.qaReference)) { id } }"#,
            in: directory
        )
        #expect(error == .notFound(type: .column, reference: Self.qaSlug))
    }

    // MARK: - deleteColumn and undeleteColumn

    @Test("deleteColumn on an empty column writes delete true and returns the tombstone")
    func deleteEmptyColumn() async throws {
        let directory = try TemporaryDirectory()
        let mutation = "mutation { \(Self.addQA) deleteColumn(\(Self.qaReference)) { id deleted } }"
        let response = try await Self.respond(to: mutation, onFixtureIn: directory)
        let qa = Self.id(of: Self.qaColumn)
        let deleted = #"{"deleted":"\#(KanbanGraphTests.time.rfc3339)","id":"\#(qa)"}"#
        #expect(response == #"{"data":{"addColumn":{"id":"\#(qa)"},"deleteColumn":\#(deleted)}}"#)
        #expect(try Self.lastPatch(of: Self.qaColumn, isDelete: true, in: directory))
    }

    @Test("deleteColumn on a column with a live task gives COLUMN_NOT_EMPTY and writes nothing")
    func deleteColumnWithTask() async throws {
        let directory = try TemporaryDirectory()
        let error = try await Self.failure(
            of: #"mutation { deleteColumn(input: { id: "todo" }) { id } }"#,
            in: directory
        )
        #expect(error == .columnNotEmpty(column: "todo", liveTaskCount: Self.fixtureTaskCount))
    }

    @Test("deleteColumn with an id that names no column gives NOT_FOUND and writes nothing")
    func deleteColumnNotFound() async throws {
        let directory = try TemporaryDirectory()
        let error = try await Self.failure(of: "mutation { deleteColumn(\(Self.qaReference)) { id } }", in: directory)
        #expect(error == .notFound(type: .column, reference: Self.qaSlug))
    }

    @Test("undeleteColumn on a tombstone writes delete false and returns the live column")
    func undeleteColumn() async throws {
        let directory = try TemporaryDirectory()
        let mutation = "mutation { \(Self.addQA) deleteColumn(\(Self.qaReference)) { id } "
            + "undeleteColumn(\(Self.qaReference)) { name deleted } }"
        let response = try await Self.respond(to: mutation, onFixtureIn: directory)
        #expect(response.hasSuffix(#""undeleteColumn":{"deleted":null,"name":"\#(Self.qaName)"}}}"#))
        #expect(try Self.lastPatch(of: Self.qaColumn, isDelete: false, in: directory))
    }

    @Test("undeleteColumn on a live column writes nothing and returns the column")
    func undeleteLiveColumn() async throws {
        let directory = try TemporaryDirectory()
        let response = try await Self.respondWritingNothing(
            to: #"mutation { undeleteColumn(input: { id: "todo" }) { name deleted } }"#,
            in: directory
        )
        let column = #"{"deleted":null,"name":"\#(KanbanGraphTests.todoName)"}"#
        #expect(response == #"{"data":{"undeleteColumn":\#(column)}}"#)
    }

    // MARK: - addActor

    @Test("addActor makes the actor with its name and color, and returns it")
    func addActor() async throws {
        let directory = try TemporaryDirectory()
        let response = try await Self.respond(to: Self.addAlice, onFixtureIn: directory)
        let actor = #"{"color":"\#(Self.red)","id":"\#(Self.id(of: Self.alice))","name":"\#(Self.aliceName)"}"#
        #expect(response == #"{"data":{"addActor":\#(actor)}}"#)
        let expected = try PatchInput(node: Self.alice, set: Self.setting(name: Self.aliceName, color: Self.red))
        #expect(try Self.patches(of: Self.alice, in: directory) == [expected])
    }

    @Test("An added actor is in the actors of the board")
    func addedActorIsListed() async throws {
        let directory = try TemporaryDirectory()
        let graph = try Self.makeFixtureGraph(in: directory).graph
        _ = try await KanbanGraphTests.execute(Self.addAlice, on: graph)
        let response = try await KanbanGraphTests.execute("{ board { actors { id } } }", on: graph)
        #expect(response.contains(#"{"id":"\#(Self.id(of: Self.alice))"}"#))
    }

    @Test("addActor with the slug of an actor that exists gives DUPLICATE_ID and writes nothing")
    func addActorDuplicate() async throws {
        let directory = try TemporaryDirectory()
        let mutation = #"mutation { addActor(input: { id: "\#(Self.aliceSlug)", name: "\#(Self.renamedAlice)" }) "#
            + "{ id } }"
        let error = try await Self.failure(of: mutation, after: Self.addAlice, in: directory)
        #expect(error == .duplicateID(type: .actor, id: Self.aliceSlug))
    }

    @Test("addActor with ensure on an actor that exists returns the actor and writes nothing")
    func addActorEnsureExisting() async throws {
        let directory = try TemporaryDirectory()
        let mutation = #"mutation { addActor(input: { id: "\#(Self.aliceSlug)", name: "\#(Self.renamedAlice)", "#
            + "ensure: true }) { name } }"
        let response = try await Self.respondWritingNothing(to: mutation, after: Self.addAlice, in: directory)
        #expect(response == #"{"data":{"addActor":{"name":"\#(Self.aliceName)"}}}"#)
    }

    @Test("addActor with ensure on an actor that does not exist makes the actor")
    func addActorEnsureNew() async throws {
        let directory = try TemporaryDirectory()
        let mutation = #"mutation { addActor(input: { name: "\#(Self.aliceName)", ensure: true }) { id name } }"#
        let response = try await Self.respond(to: mutation, onFixtureIn: directory)
        let actor = #"{"id":"\#(Self.id(of: .actor(slug: "alice-smith")))","name":"\#(Self.aliceName)"}"#
        #expect(response == #"{"data":{"addActor":\#(actor)}}"#)
    }

    @Test("addActor with a name that gives an empty slug gives INVALID_SLUG and writes nothing")
    func addActorInvalidSlug() async throws {
        let directory = try TemporaryDirectory()
        let error = try await Self.failure(
            of: #"mutation { addActor(input: { name: "\#(Self.emptySlugName)" }) { id } }"#,
            in: directory
        )
        #expect(error == .invalidSlug(name: Self.emptySlugName))
    }

    // MARK: - updateActor, deleteActor, and undeleteActor

    @Test("updateActor changes the name, the color, and the body, and keeps the id")
    func updateActor() async throws {
        let directory = try TemporaryDirectory()
        let update = #"updateActor(input: { id: "\#(Self.aliceSlug)", name: "\#(Self.renamedAlice)", "#
            + #"color: "\#(Self.green)", body: $body }) { id name color body }"#
        let mutation = "mutation($body: String) { \(Self.addAliceField) \(update) }"
        let response = try await Self.respond(to: mutation, with: Self.bodyVariables, onFixtureIn: directory)
        let actor = #"{"body":"\#(Self.bodyJSON)","color":"\#(Self.green)","id":"\#(Self.id(of: Self.alice))","#
            + #""name":"\#(Self.renamedAlice)"}"#
        #expect(response.hasSuffix(#""updateActor":\#(actor)}}"#))
        let set = Self.setting(name: Self.renamedAlice, color: Self.green)
        let expected = try Self.bodyPatch(of: Self.alice, setting: set)
        #expect(try Self.patches(of: Self.alice, in: directory).last == expected)
    }

    @Test("updateActor with a null color writes an unset of the color, and a missing name does not change")
    func updateActorNullColorUnsetsColor() async throws {
        let directory = try TemporaryDirectory()
        let update = #"updateActor(input: { id: "\#(Self.aliceSlug)", color: null }) { name color }"#
        let mutation = "mutation { \(Self.addAliceField) \(update) }"
        let response = try await Self.respond(to: mutation, onFixtureIn: directory)
        #expect(response.hasSuffix(#""updateActor":{"color":null,"name":"\#(Self.aliceName)"}}}"#))
        let expected = try PatchInput(node: Self.alice, unset: [PropertyName.color])
        #expect(try Self.patches(of: Self.alice, in: directory).last == expected)
    }

    @Test("deleteActor writes delete true and returns the tombstone")
    func deleteActor() async throws {
        let directory = try TemporaryDirectory()
        let mutation = "mutation { \(Self.addAliceField) deleteActor(\(Self.aliceReference)) { deleted } }"
        let response = try await Self.respond(to: mutation, onFixtureIn: directory)
        #expect(response.hasSuffix(#""deleteActor":{"deleted":"\#(KanbanGraphTests.time.rfc3339)"}}}"#))
        #expect(try Self.lastPatch(of: Self.alice, isDelete: true, in: directory))
    }

    @Test("undeleteActor on a tombstone writes delete false and returns the live actor")
    func undeleteActor() async throws {
        let directory = try TemporaryDirectory()
        let graph = try Self.makeFixtureGraph(in: directory).graph
        _ = try await KanbanGraphTests.execute(Self.addAlice, on: graph)
        _ = try await KanbanGraphTests.execute("mutation { deleteActor(\(Self.aliceReference)) { id } }", on: graph)
        #expect(try Self.lastPatch(of: Self.alice, isDelete: true, in: directory))
        let mutation = "mutation { undeleteActor(\(Self.aliceReference)) { name deleted } }"
        let response = try await KanbanGraphTests.execute(mutation, on: graph)
        #expect(response == #"{"data":{"undeleteActor":{"deleted":null,"name":"\#(Self.aliceName)"}}}"#)
        #expect(try Self.lastPatch(of: Self.alice, isDelete: false, in: directory))
    }
}
