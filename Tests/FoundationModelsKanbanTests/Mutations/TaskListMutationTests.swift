import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the list mutations of tasks (divergence.md §20): `moveTasks`, `deleteTasks`, and `undeleteTasks`.
///
/// The `id` field of each mutation takes a list of task refs, or one task ref. The call changes the tasks in one
/// transaction, so one `undoChange` reverses it, and the result gives each task one time, in the order of the list.
/// When one ref names no task, the call writes nothing, and the error names each such ref. Each test uses the fixture
/// logs of ``KanbanGraphTests`` and the three tasks of ``TaskOperationTests/threeTasks(in:)`` in `todo`.
@Suite("Task list mutations", .watcherBudget)
struct TaskListMutationTests {
    /// The refs that name no task, in the tests of an unknown ref: short ids that no task has.
    private static let unknownRefs = ["zzzzzzz", "yyyyyyy"]

    /// Each list mutation, by its name.
    enum ListMutation: String, CaseIterable {
        case moveTasks
        case deleteTasks
        case undeleteTasks

        /// The fields of the `input` object other than `id`: a column for a move, and no field for the others.
        var otherFields: String {
            switch self {
            case .moveTasks:
                TaskOperationTests.moveInput()
            case .deleteTasks, .undeleteTasks:
                ""
            }
        }

        /// Makes a document that runs this mutation on some tasks.
        ///
        /// - Parameter tasks: The ULIDs of the tasks, in the order of the list.
        /// - Returns: The document.
        func document(on tasks: [ULID]) -> String {
            AddUpdateTaskTests.mutation(of: TaskListMutationTests.field(rawValue, naming: tasks, with: otherFields))
        }

        /// Makes the document that runs before this mutation: a delete of the tasks for an undelete, else `nil`.
        ///
        /// - Parameter tasks: The ULIDs of the tasks.
        /// - Returns: The document, or `nil` for no setup.
        func setup(of tasks: [ULID]) -> String? {
            switch self {
            case .undeleteTasks:
                ListMutation.deleteTasks.document(on: tasks)
            case .moveTasks, .deleteTasks:
                nil
            }
        }
    }

    // MARK: - Helpers

    /// Makes a field of a list mutation whose `id` field is a list of task refs.
    ///
    /// - Parameters:
    ///   - name: The name of the mutation, for example `moveTasks`.
    ///   - refs: The task refs, as the input writes them.
    ///   - input: The other fields of the `input` object, or `""` for none.
    /// - Returns: The field, with the selection ``AddUpdateTaskTests/idSelection``.
    private static func field(_ name: String, naming refs: [String], with input: String = "") -> String {
        #"\#(name)(input: { id: \#(AddUpdateTaskTests.list(of: refs)) \#(input) }) \#(AddUpdateTaskTests.idSelection)"#
    }

    /// Makes a field of a list mutation that names tasks by `^` and the short id.
    ///
    /// - Parameters:
    ///   - name: The name of the mutation, for example `moveTasks`.
    ///   - tasks: The ULIDs of the tasks, in the order of the list.
    ///   - input: The other fields of the `input` object, or `""` for none.
    /// - Returns: The field, with the selection ``AddUpdateTaskTests/idSelection``.
    static func field(_ name: String, naming tasks: [ULID], with input: String = "") -> String {
        field(name, naming: tasks.map(AddUpdateTaskTests.sigilRef(of:)), with: input)
    }

    /// Gives the JSON text of the result of a list mutation with the selection ``AddUpdateTaskTests/idSelection``.
    ///
    /// - Parameter tasks: The ULIDs of the tasks of the result, in its order.
    /// - Returns: The JSON array text.
    private static func idsJSON(of tasks: [ULID]) -> String {
        "[" + tasks.map { task in AddUpdateTaskTests.idJSON(of: .task(task)) }.joined(separator: ",") + "]"
    }

    /// Gives the response of a document with one list mutation field.
    ///
    /// - Parameters:
    ///   - field: The response key of the field.
    ///   - tasks: The ULIDs of the tasks of the result, in its order.
    /// - Returns: The response JSON text, with no `extensions.txn`.
    private static func response(of field: String, giving tasks: [ULID]) -> String {
        TaskOperationTests.dataResponse(of: #""\#(field)":\#(idsJSON(of: tasks))"#)
    }

    // MARK: - moveTasks

    @Test("moveTasks puts the tasks before the neighbor in a different column, in the order of the list")
    func moveTasksBeforeNeighborInOrderOfList() async throws {
        let tasks = try await TaskOperationTests.threeTasks(in: try TemporaryDirectory())
        let toDone = TaskOperationTests.taskField(
            "moveTask",
            of: tasks.third,
            with: TaskOperationTests.moveInput(to: TaskOperationTests.doneSlug)
        )
        _ = try await KanbanGraphTests.execute(
            AddUpdateTaskTests.mutation(of: AddUpdateTaskTests.doneColumn, toDone),
            on: tasks.graph
        )
        let input = TaskOperationTests.moveInput(
            to: TaskOperationTests.doneSlug,
            placing: TaskOperationTests.neighbor("before", of: tasks.third)
        )
        let move = Self.field("moveTasks", naming: [tasks.second, tasks.first], with: input)
        let response = try await KanbanGraphTests.runWithoutTransaction(move, on: tasks.graph)
        #expect(response == Self.response(of: "moveTasks", giving: [tasks.second, tasks.first]))
        #expect(try await TaskOperationTests.listedTasks(on: tasks.graph) == [tasks.second, tasks.first, tasks.third])
    }

    @Test("moveTasks with no column puts the tasks as one block in the column of the first task")
    func moveTasksWithNoColumnKeepsBlockInColumn() async throws {
        let tasks = try await TaskOperationTests.threeTasks(in: try TemporaryDirectory())
        let input = TaskOperationTests.neighbor("before", of: tasks.second)
        let move = Self.field("moveTasks", naming: [tasks.third, tasks.first], with: input)
        let response = try await KanbanGraphTests.runWithoutTransaction(move, on: tasks.graph)
        #expect(response == Self.response(of: "moveTasks", giving: [tasks.third, tasks.first]))
        #expect(try await TaskOperationTests.listedTasks(on: tasks.graph) == [tasks.third, tasks.first, tasks.second])
    }

    @Test("moveTasks with no place puts the tasks at the end of the column, in the order of the list")
    func moveTasksWithNoPlaceAppendsBlock() async throws {
        let tasks = try await TaskOperationTests.threeTasks(in: try TemporaryDirectory())
        let move = Self.field("moveTasks", naming: [tasks.second, tasks.first], with: TaskOperationTests.moveInput())
        let response = try await KanbanGraphTests.runWithoutTransaction(move, on: tasks.graph)
        #expect(response == Self.response(of: "moveTasks", giving: [tasks.second, tasks.first]))
        #expect(try await TaskOperationTests.listedTasks(on: tasks.graph) == [tasks.third, tasks.second, tasks.first])
    }

    @Test("moveTasks takes one ref that is not a list as a list of one task")
    func moveTasksTakesOneRef() async throws {
        let tasks = try await TaskOperationTests.threeTasks(in: try TemporaryDirectory())
        let move = TaskOperationTests.taskField("moveTasks", of: tasks.first, with: TaskOperationTests.moveInput())
        let response = try await KanbanGraphTests.runWithoutTransaction(move, on: tasks.graph)
        #expect(response == Self.response(of: "moveTasks", giving: [tasks.first]))
        #expect(try await TaskOperationTests.listedTasks(on: tasks.graph) == [tasks.second, tasks.third, tasks.first])
    }

    @Test("moveTasks gives a task that the list names two times one time, at its first place")
    func moveTasksGivesRepeatedTaskOneTime() async throws {
        let tasks = try await TaskOperationTests.threeTasks(in: try TemporaryDirectory())
        let refs = [tasks.second, tasks.first, tasks.second]
        let move = Self.field("moveTasks", naming: refs, with: TaskOperationTests.moveInput())
        let response = try await KanbanGraphTests.runWithoutTransaction(move, on: tasks.graph)
        #expect(response == Self.response(of: "moveTasks", giving: [tasks.second, tasks.first]))
        #expect(try await TaskOperationTests.listedTasks(on: tasks.graph) == [tasks.third, tasks.second, tasks.first])
    }

    // MARK: - deleteTasks and undeleteTasks

    @Test("deleteTasks makes each task of the list a tombstone, and gives each task")
    func deleteTasksMakesTombstones() async throws {
        let tasks = try await TaskOperationTests.threeTasks(in: try TemporaryDirectory())
        let delete = Self.field("deleteTasks", naming: [tasks.third, tasks.first])
        let response = try await KanbanGraphTests.runWithoutTransaction(delete, on: tasks.graph)
        #expect(response == Self.response(of: "deleteTasks", giving: [tasks.third, tasks.first]))
        #expect(try await TaskOperationTests.listedTasks(on: tasks.graph) == [tasks.second])
    }

    @Test("undeleteTasks makes each tombstoned task of the list live again, and gives each task")
    func undeleteTasksMakesTasksLive() async throws {
        let tasks = try await TaskOperationTests.threeTasks(in: try TemporaryDirectory())
        _ = try await CommentTests.run(Self.field("deleteTasks", naming: [tasks.first, tasks.third]), on: tasks.graph)
        let undelete = Self.field("undeleteTasks", naming: [tasks.third, tasks.first])
        let response = try await KanbanGraphTests.runWithoutTransaction(undelete, on: tasks.graph)
        #expect(response == Self.response(of: "undeleteTasks", giving: [tasks.third, tasks.first]))
        #expect(try await TaskOperationTests.listedTasks(on: tasks.graph) == [tasks.first, tasks.second, tasks.third])
    }

    @Test("deleteTasks takes a JSON array of refs in one string")
    func deleteTasksSplitsJSONArrayInString() async throws {
        let tasks = try await TaskOperationTests.threeTasks(in: try TemporaryDirectory())
        let refs = [tasks.first, tasks.second].map(AddUpdateTaskTests.sigilRef(of:))
        let array = String(decoding: try JSONEncoder().encode(refs), as: UTF8.self)
        let text = try KanbanArgumentsTests.jsonLiteral(of: array)
        let delete = #"deleteTasks(input: { id: \#(text) }) \#(AddUpdateTaskTests.idSelection)"#
        let response = try await KanbanGraphTests.runWithoutTransaction(delete, on: tasks.graph)
        #expect(response == Self.response(of: "deleteTasks", giving: [tasks.first, tasks.second]))
        #expect(try await TaskOperationTests.listedTasks(on: tasks.graph) == [tasks.third])
    }

    @Test("deleteTasks with an empty list writes nothing and gives an empty list")
    func deleteTasksWithEmptyListWritesNothing() async throws {
        let response = try await ColumnActorTests.respondWritingNothing(
            to: AddUpdateTaskTests.mutation(of: Self.field("deleteTasks", naming: [String]())),
            in: try TemporaryDirectory()
        )
        #expect(response == Self.response(of: "deleteTasks", giving: []))
    }

    @Test("archiveTasks and unarchiveTasks name deleteTasks and undeleteTasks, and ids names id")
    func archiveVerbsNameListMutations() async throws {
        let tasks = try await TaskOperationTests.threeTasks(in: try TemporaryDirectory())
        let refs = AddUpdateTaskTests.list(of: [tasks.first, tasks.second].map(AddUpdateTaskTests.sigilRef(of:)))
        let archive = #"archiveTasks(input: { ids: \#(refs) }) \#(AddUpdateTaskTests.idSelection)"#
        let response = try await KanbanGraphTests.runWithoutTransaction(archive, on: tasks.graph)
        let rewrites = [
            #"{"from":"archiveTasks","path":["archiveTasks"],"to":"deleteTasks"}"#,
            #"{"from":"ids","path":["archiveTasks","input","ids"],"to":"id"}"#,
        ]
        let data = #""archiveTasks":\#(Self.idsJSON(of: [tasks.first, tasks.second]))"#
        #expect(response == #"{"data":{\#(data)},"extensions":{"rewrites":[\#(rewrites.joined(separator: ","))]}}"#)
        let unarchive = #"unarchiveTasks(input: { id: \#(refs) }) \#(AddUpdateTaskTests.idSelection)"#
        _ = try await CommentTests.run(unarchive, on: tasks.graph)
        #expect(try await TaskOperationTests.listedTasks(on: tasks.graph) == [tasks.first, tasks.second, tasks.third])
    }

    // MARK: - One transaction

    @Test(
        "A list mutation writes one transaction, and one undoChange of it reverses each change",
        arguments: ListMutation.allCases
    )
    func listMutationIsOneTransaction(mutation: ListMutation) async throws {
        let directory = try TemporaryDirectory()
        let tasks = try await TaskOperationTests.threeTasks(in: directory)
        let changed = [tasks.third, tasks.first]
        if let setup = mutation.setup(of: changed) {
            _ = try await KanbanGraphTests.execute(setup, on: tasks.graph)
        }
        let before = try await KanbanGraphTests.execute(KanbanGraphTests.boardQuery, on: tasks.graph)
        let document = mutation.document(on: changed)
        let call = try await ResponseTransactionTests.run(document, on: tasks.graph, in: directory)
        let txn = try ResponseTransactionTests.transaction(of: call.response)
        #expect(call.written == [txn], "\(call.response)")
        let undo = UndoTests.reverseField(MutationName.undoChange, with: #"txn: "\#(txn)""#)
        _ = try await CommentTests.run(undo, on: tasks.graph)
        #expect(try await KanbanGraphTests.execute(KanbanGraphTests.boardQuery, on: tasks.graph) == before)
    }

    // MARK: - Unknown refs

    /// Runs a list mutation on the fixture task and on refs that name no task, and gives its error. The run expects
    /// that the call writes nothing.
    ///
    /// - Parameters:
    ///   - mutation: The list mutation.
    ///   - unknown: The refs that name no task. The list names them after the fixture task.
    /// - Returns: The error of the first GraphQL error of the response.
    private static func failure(of mutation: ListMutation, naming unknown: [String]) async throws -> KanbanError {
        let refs = [AddUpdateTaskTests.sigilRef(of: try AddUpdateTaskTests.fixtureTask())] + unknown
        let field = Self.field(mutation.rawValue, naming: refs, with: mutation.otherFields)
        return try await CommentTests.failure(of: field, in: try TemporaryDirectory())
    }

    @Test(
        "A list with refs that name no task gives NOT_FOUND with each ref, and writes nothing",
        arguments: ListMutation.allCases
    )
    func unknownRefsWriteNothing(mutation: ListMutation) async throws {
        let error = try await Self.failure(of: mutation, naming: Self.unknownRefs)
        #expect(error == .nodesNotFound(type: .task, references: Self.unknownRefs))
    }

    @Test(
        "A list with one ref that names no task gives the NOT_FOUND of that ref, and writes nothing",
        arguments: ListMutation.allCases
    )
    func unknownRefWritesNothing(mutation: ListMutation) async throws {
        let unknown = try #require(Self.unknownRefs.first)
        let error = try await Self.failure(of: mutation, naming: [unknown])
        #expect(error == .notFound(type: .task, reference: unknown))
    }
}
