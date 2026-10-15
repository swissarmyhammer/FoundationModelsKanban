import Foundation
import GraphQL
import Testing
import ULID

@testable import FoundationModelsKanban

/// The move in its column that a priority value must give a task.
enum ExpectedPriorityMove: Sendable {
    /// The task goes before the first task of its column.
    case toTop

    /// The task goes after the last task of its column.
    case toEnd

    /// The task keeps its place.
    case stay
}

/// One row of the priority value table (divergence.md P2 and K15): an `input` field, its value as the document
/// writes it, and the move that the value must give.
struct PriorityRow: Sendable, CustomTestStringConvertible {
    /// The name of the `input` field: `priority`, `prio`, or `urgent`.
    let field: String

    /// The GraphQL literal of the value, for example `"high"` with the quotes, `true`, or `5`.
    let literal: String

    /// The text of the value in the warning: the literal without the quotes of a string.
    let text: String

    /// The move that the value must give.
    let move: ExpectedPriorityMove

    /// The name of the row in the test report.
    var testDescription: String {
        inputField
    }

    /// The `input` field of the row, for example `priority: "high"`.
    var inputField: String {
        "\(field): \(literal)"
    }

    /// Makes a row whose value is a string literal.
    ///
    /// - Parameters:
    ///   - text: The text of the string.
    ///   - move: The move that the value must give.
    ///   - field: The name of the `input` field. The default is `priority`.
    /// - Returns: The row.
    static func string(_ text: String, _ move: ExpectedPriorityMove, field: String = "priority") -> PriorityRow {
        PriorityRow(field: field, literal: #""\#(text)""#, text: text, move: move)
    }

    /// Makes a row whose value is a literal that is not a string, for example `true` or a number.
    ///
    /// - Parameters:
    ///   - literal: The GraphQL literal.
    ///   - move: The move that the value must give.
    ///   - field: The name of the `input` field. The default is `priority`.
    /// - Returns: The row.
    static func bare(_ literal: String, _ move: ExpectedPriorityMove, field: String = "priority") -> PriorityRow {
        PriorityRow(field: field, literal: literal, text: literal, move: move)
    }
}

/// Tests a priority value in a task input (divergence.md P2 and K15).
///
/// A task has no priority field: its place in the column is its priority. `addTask` and `updateTask` accept
/// `priority`, `prio`, and `urgent`, and move the task in its column by a fixed table, in the same change. Each value
/// gives one warning in `extensions.warnings`. Each test uses the fixture logs of ``KanbanGraphTests`` in a new
/// temporary repo, never the `.kanban` folder of this repo.
@Suite("A priority value in a task input", .watcherBudget)
struct PriorityInputTests {
    /// The code of the warning of a priority value.
    static let warningCode = "PRIORITY_IS_POSITION"

    /// The end of each warning of a priority value, after the sentence that tells the move.
    private static let warningTail = " A task has no priority field: the place in the column is the priority. "
        + "Use moveTask with before or after to change the place, or filter with #HIGH, #MEDIUM, or #LOW."

    /// A number that is more than each other number of the table, as a literal.
    private static let largeNumber = "2147483648"

    /// Each row of the value table, with the case of the text changed in some rows: the case does not matter.
    static let rows: [PriorityRow] = [
        .string("urgent", .toTop),
        .string("Critical", .toTop),
        .string("HIGH", .toTop),
        .string("P0", .toTop),
        .string("p1", .toTop),
        .bare("true", .toTop, field: "urgent"),
        .bare("high", .toTop),
        .string("low", .toEnd, field: "prio"),
        .string("P3", .toEnd),
        .string("p4", .toEnd),
        .string("medium", .stay),
        .string("NORMAL", .stay),
        .string("P2", .stay),
        .bare("1", .stay),
        .bare(largeNumber, .stay),
        .string("whenever", .stay),
    ]

    // MARK: - Helpers

    /// Gives the warning text of a priority value.
    ///
    /// - Parameters:
    ///   - text: The text of the value.
    ///   - move: The move that the value gave.
    /// - Returns: The message of the warning.
    static func warning(forValue text: String, giving move: ExpectedPriorityMove) -> String {
        let effect = switch move {
        case .toTop: "moved the task to the top of its column."
        case .toEnd: "moved the task to the end of its column."
        case .stay: "made no move."
        }
        return "The priority value `\(text)` \(effect)" + warningTail
    }

    /// Expects that a response has no error and one warning of a priority value.
    ///
    /// - Parameters:
    ///   - response: The response JSON text.
    ///   - text: The text of the value.
    ///   - move: The move that the value gave.
    /// - Throws: An error when the response has no warnings.
    private static func expectPriorityWarning(
        in response: String,
        forValue text: String,
        giving move: ExpectedPriorityMove
    ) throws {
        #expect(try KanbanGraphTests.object(of: response)["errors"] == nil, "\(response)")
        let warnings = try ResponseWarningsTests.warnings(of: response)
        #expect(warnings.map(\.message) == [warning(forValue: text, giving: move)], "\(response)")
        #expect(warnings.map(\.code) == [warningCode], "\(response)")
    }

    /// Gives the live tasks of the board in board order: column order, then ordinal.
    ///
    /// - Parameter graph: The engine.
    /// - Returns: The ULID of each live task.
    private static func boardOrder(on graph: KanbanGraph) async throws -> [ULID] {
        try AddUpdateTaskTests.taskULIDs(in: await KanbanGraphTests.execute(KanbanGraphTests.boardQuery, on: graph))
    }

    /// Adds two tasks to `todo` after the fixture task, on a new engine of the fixture repo.
    ///
    /// - Parameter directory: The temporary repo directory.
    /// - Returns: The engine, and the ULIDs of the three tasks in the order of their ordinals.
    private static func threeTasks(
        in directory: TemporaryDirectory
    ) async throws -> (graph: KanbanGraph, first: ULID, second: ULID, third: ULID) {
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let setup = AddUpdateTaskTests.mutation(
            of: "b: " + AddUpdateTaskTests.addTask(with: ""),
            "c: " + AddUpdateTaskTests.addTask(with: "")
        )
        let added = try await AddUpdateTaskTests.addedTasks(by: setup, on: fixture.graph)
        return (fixture.graph, fixture.task, try #require(added.first), try #require(added.last))
    }

    // MARK: - The value table

    @Test("updateTask moves the task in its column by the value table", arguments: rows)
    func updateTaskMovesByTable(row: PriorityRow) async throws {
        let directory = try TemporaryDirectory()
        let tasks = try await Self.threeTasks(in: directory)
        let update = AddUpdateTaskTests.updateTask(tasks.second, with: row.inputField)
        let response = try await CommentTests.run(update, on: tasks.graph)
        try Self.expectPriorityWarning(in: response, forValue: row.text, giving: row.move)
        let expected = switch row.move {
        case .toTop: [tasks.second, tasks.first, tasks.third]
        case .toEnd: [tasks.first, tasks.third, tasks.second]
        case .stay: [tasks.first, tasks.second, tasks.third]
        }
        #expect(try await Self.boardOrder(on: tasks.graph) == expected)
    }

    @Test("addTask gives the warning of each value, and puts the new task by the value table", arguments: rows)
    func addTaskGivesWarningOfEachValue(row: PriorityRow) async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let response = try await CommentTests.run(AddUpdateTaskTests.addTask(with: row.inputField), on: fixture.graph)
        try Self.expectPriorityWarning(in: response, forValue: row.text, giving: row.move)
        let added = try AddUpdateTaskTests.firstTask(in: response)
        let expected = row.move == .toTop ? [added, fixture.task] : [fixture.task, added]
        #expect(try await Self.boardOrder(on: fixture.graph) == expected)
    }

    // MARK: - One change

    @Test("addTask with priority high writes one task patch with an ordinal before the first task")
    func addTaskHighWritesOnePatch() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let add = AddUpdateTaskTests.addTask(with: #"priority: "high""#)
        let task = try AddUpdateTaskTests.firstTask(in: await CommentTests.run(add, on: fixture.graph))
        let values: [String: PatchValue] = [
            PropertyName.title: .string(AddUpdateTaskTests.title),
            PropertyName.column: .ref(.local(KanbanGraphTests.todoColumn)),
            PropertyName.ordinal: .string(Ordinal(before: .first).value),
        ]
        let expected = try PatchInput(node: .task(task), set: values)
        #expect(try ColumnActorTests.patches(of: .task(task), in: directory) == [expected])
    }

    @Test("updateTask with a title and prio low writes one patch with the title and the new ordinal")
    func updateTaskLowWritesOnePatch() async throws {
        let directory = try TemporaryDirectory()
        let tasks = try await Self.threeTasks(in: directory)
        let input = #"title: "Renamed", prio: "low""#
        _ = try await CommentTests.run(AddUpdateTaskTests.updateTask(tasks.first, with: input), on: tasks.graph)
        let thirdOrdinal = Ordinal(after: Ordinal(after: .first))
        let values: [String: PatchValue] = [
            PropertyName.title: .string("Renamed"),
            PropertyName.ordinal: .string(Ordinal(after: thirdOrdinal).value),
        ]
        let expected = try PatchInput(node: .task(tasks.first), set: values)
        #expect(try AddUpdateTaskTests.lastPatch(of: tasks.first, in: directory) == expected)
    }

    @Test("updateTask with a column and priority high puts the task at the top of the new column")
    func updateTaskColumnAndHighGoesToTopOfNewColumn() async throws {
        let directory = try TemporaryDirectory()
        let tasks = try await Self.threeTasks(in: directory)
        let toDone = #"column: "done""#
        let setup = AddUpdateTaskTests.mutation(
            of: AddUpdateTaskTests.doneColumn,
            "a: " + AddUpdateTaskTests.updateTask(tasks.first, with: toDone),
            "b: " + AddUpdateTaskTests.updateTask(tasks.second, with: toDone)
        )
        _ = try await KanbanGraphTests.execute(setup, on: tasks.graph)
        let update = AddUpdateTaskTests.updateTask(tasks.third, with: toDone + #", priority: "high""#)
        let response = try await CommentTests.run(update, on: tasks.graph)
        try Self.expectPriorityWarning(in: response, forValue: "high", giving: .toTop)
        #expect(try await Self.boardOrder(on: tasks.graph) == [tasks.third, tasks.first, tasks.second])
    }

    // MARK: - Variables

    @Test("urgent true in the value of a variable moves the task to the top")
    func urgentTrueVariableGoesToTop() async throws {
        let directory = try TemporaryDirectory()
        let fixture = try ColumnActorTests.makeFixtureGraph(in: directory)
        let document = "mutation ($input: AddTaskInput!) { addTask(input: $input) { id } }"
        let input: Map = ["title": "x", "urgent": true]
        let response = try await KanbanGraphTests.execute(document, variables: ["input": input], on: fixture.graph)
        try Self.expectPriorityWarning(in: response, forValue: "true", giving: .toTop)
        let added = try AddUpdateTaskTests.firstTask(in: response)
        #expect(try await Self.boardOrder(on: fixture.graph) == [added, fixture.task])
    }

    @Test("A bare number in the value of a variable makes no move")
    func numberVariableMakesNoMove() async throws {
        let directory = try TemporaryDirectory()
        let tasks = try await Self.threeTasks(in: directory)
        let document = "mutation ($input: UpdateTaskInput!) { updateTask(input: $input) { id } }"
        let input: Map = ["id": .string(AddUpdateTaskTests.sigilRef(of: tasks.second)), "priority": 1]
        let response = try await KanbanGraphTests.execute(document, variables: ["input": input], on: tasks.graph)
        try Self.expectPriorityWarning(in: response, forValue: "1", giving: .stay)
        #expect(try await Self.boardOrder(on: tasks.graph) == [tasks.first, tasks.second, tasks.third])
    }
}
