import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the transaction of a call in its response: `extensions.txn` (divergence.md §19).
///
/// The response of a call that writes gives the ULID of its transaction in `extensions.txn`, so that a client can send
/// `undoChange(input: { txn: <that txn> })` with no read of `Board.history`. A call that writes nothing gives no
/// `txn`. Each test uses the fixture logs of ``KanbanGraphTests``: the board, the column `todo`, and one task in
/// `todo`.
@Suite("The transaction of a call in extensions.txn", .watcherBudget)
struct ResponseTransactionTests {
    /// The key of the transaction in the `extensions` object of a response.
    private static let txnKey = "txn"

    /// The key of the `extensions` object of a response.
    private static let extensionsKey = "extensions"

    /// The title that an `updateTask` field of a test gives to the fixture task.
    private static let newTitle = "Port the printer"

    /// A version that is not the version of the fixture task: a valid ULID text that no event has.
    private static let oldVersion = "01ARZ3NDEKTSV4RRFFQ69G5FAV"

    /// A query that reads each live task of the board, with the fields that the writes of the tests change.
    private static let tasksQuery = "{ board { tasks { edges { node { id title ordinal column { id } } } } } }"

    /// The writes of the document with more than one mutation field, in the order of the fields.
    private static let writesOfOneDocument: [Write] = [.addTask, .updateTask, .moveTask]

    /// Each mutation that a test runs on the fixture task and that writes, by its name.
    enum Write: String, CaseIterable {
        case addTask
        case updateTask
        case moveTask
        case deleteTask

        /// Makes the mutation field of the write.
        ///
        /// - Parameter task: The ULID of the fixture task.
        /// - Returns: The field, with its selection.
        func field(of task: ULID) -> String {
            switch self {
            case .addTask:
                AddUpdateTaskTests.addTask(with: "")
            case .updateTask:
                AddUpdateTaskTests.updateTask(task, with: #"title: "\#(newTitle)""#)
            case .moveTask:
                TaskOperationTests.taskField(
                    rawValue,
                    of: task,
                    with: TaskOperationTests.moveInput(to: TaskOperationTests.newColumnSlug)
                )
            case .deleteTask:
                TaskOperationTests.taskField(rawValue, of: task)
            }
        }
    }

    /// Each document that a test runs on the fixture task and that writes nothing, by the reason.
    enum NoWrite: String, CaseIterable {
        case query
        case noOpTag
        case staleUpdate
        case missingTask
        case dryRun

        /// Makes the document.
        ///
        /// - Parameter task: The ULID of the fixture task.
        /// - Returns: The GraphQL document.
        func document(of task: ULID) -> String {
            switch self {
            case .query:
                KanbanGraphTests.nameQuery
            case .noOpTag:
                AddUpdateTaskTests.mutation(of: TaskOperationTests.taskField("tagTask", of: task, with: "tags: []"))
            case .staleUpdate:
                AddUpdateTaskTests.mutation(
                    of: AddUpdateTaskTests.updateTask(
                        task,
                        with: #"title: "\#(newTitle)", ifVersion: "\#(oldVersion)""#
                    )
                )
            case .missingTask:
                AddUpdateTaskTests.mutation(
                    of: TaskOperationTests.taskField("moveTask", of: ULID(), with: TaskOperationTests.moveInput())
                )
            case .dryRun:
                AddUpdateTaskTests.mutation(of: "repairLinks(input: { dryRun: true }) { node }")
            }
        }
    }

    // MARK: - Calls that write

    @Test("A call that writes gives the transaction of its events in extensions.txn", arguments: Write.allCases)
    func writeGivesTransaction(write: Write) async throws {
        let directory = try TemporaryDirectory()
        let (graph, task) = try ColumnActorTests.makeFixtureGraph(in: directory)
        let call = try await Self.run(Self.mutation(of: [write], on: task), on: graph, in: directory)
        #expect(call.written == [try Self.transaction(of: call.response)], "\(call.response)")
    }

    @Test("undoChange with the txn of the response of a call reverses that call", arguments: Write.allCases)
    func undoOfResponseTransactionReversesCall(write: Write) async throws {
        let directory = try TemporaryDirectory()
        let (graph, task) = try ColumnActorTests.makeFixtureGraph(in: directory)
        let tasksBefore = try await KanbanGraphTests.execute(Self.tasksQuery, on: graph)
        let call = try await Self.run(Self.mutation(of: [write], on: task), on: graph, in: directory)
        let txn = try Self.transaction(of: call.response)
        let undo = UndoTests.reverseField(MutationName.undoChange, with: #"txn: "\#(txn)""#)
        let undoResponse = try await KanbanGraphTests.execute(AddUpdateTaskTests.mutation(of: undo), on: graph)
        let change = try KanbanGraphTests.object(named: MutationName.undoChange, in: undoResponse)
        #expect(change["undoes"] as? String == txn, "\(undoResponse)")
        #expect(try Self.transaction(of: undoResponse) == change[Self.txnKey] as? String)
        #expect(try await KanbanGraphTests.execute(Self.tasksQuery, on: graph) == tasksBefore)
    }

    @Test("Each mutation field of one document writes in the one transaction of extensions.txn")
    func fieldsOfOneDocumentShareTransaction() async throws {
        let directory = try TemporaryDirectory()
        let (graph, task) = try ColumnActorTests.makeFixtureGraph(in: directory)
        let writes = Self.writesOfOneDocument
        let call = try await Self.run(Self.mutation(of: writes, on: task), on: graph, in: directory)
        let txn = try Self.transaction(of: call.response)
        #expect(call.written == [txn], "\(call.response)")
        let events = try CrossRepoWriteTests.events(inRepoAt: directory.url).filter { event in
            event.txn.ulidString == txn
        }
        #expect(Set(events.map(\.ops)) == [writes.map(\.rawValue)], "\(events)")
    }

    // MARK: - Calls that write nothing

    @Test("A call that writes nothing gives no txn", arguments: NoWrite.allCases)
    func noWriteGivesNoTransaction(call: NoWrite) async throws {
        let directory = try TemporaryDirectory()
        let response = try await ColumnActorTests.respondWritingNothing(
            to: call.document(of: try AddUpdateTaskTests.fixtureTask()),
            in: directory
        )
        let extensions = try KanbanGraphTests.object(of: response)[Self.extensionsKey] as? [String: Any]
        #expect(extensions?[Self.txnKey] == nil, "\(response)")
    }

    // MARK: - Helpers

    /// Makes a mutation document with one field for each write. Each field has the name of its write as its alias, so
    /// that two writes of one mutation can be in one document.
    ///
    /// - Parameters:
    ///   - writes: The writes, in the order of the fields.
    ///   - task: The ULID of the fixture task.
    /// - Returns: The document.
    private static func mutation(of writes: [Write], on task: ULID) -> String {
        let fields = writes.map { write in "\(write.rawValue): \(write.field(of: task))" }
        return AddUpdateTaskTests.mutation(of: fields.joined(separator: " "))
    }

    /// Runs one document that writes on an engine, and expects that it gives no error.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - graph: The engine of the fixture repo.
    ///   - directory: The temporary repo directory.
    /// - Returns: The response JSON text, and the text of each transaction that the call added to the log, sorted.
    private static func run(
        _ document: String,
        on graph: KanbanGraph,
        in directory: TemporaryDirectory
    ) async throws -> (response: String, written: [String]) {
        let before = try transactions(inRepoAt: directory.url)
        let response = try await KanbanGraphTests.execute(document, on: graph)
        #expect(try CrossRepoWriteTests.hasNoErrors(response), "\(response)")
        let written = try transactions(inRepoAt: directory.url).subtracting(before)
        return (response, written.map(\.ulidString).sorted())
    }

    /// Gives the `extensions.txn` of a response.
    ///
    /// - Parameter response: The response JSON text.
    /// - Returns: The transaction ULID text.
    private static func transaction(of response: String) throws -> String {
        let extensions = try #require(
            KanbanGraphTests.object(of: response)[extensionsKey] as? [String: Any],
            "\(response)"
        )
        return try #require(extensions[txnKey] as? String, "\(response)")
    }

    /// Gives the transactions of the events of the log of a repo.
    ///
    /// - Parameter root: The root directory of the repo.
    /// - Returns: The transaction ULIDs.
    private static func transactions(inRepoAt root: URL) throws -> Set<ULID> {
        Set(try CrossRepoWriteTests.events(inRepoAt: root).map(\.txn))
    }
}
