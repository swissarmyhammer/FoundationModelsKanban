import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests `moveColumn` (divergence.md §25): a move of a column to a place next to its neighbor columns, in one
/// transaction.
///
/// Each test uses the fixture logs of ``KanbanGraphTests`` (the column `todo` with order 0) and adds the columns of
/// ``standardColumns``: `doing` and `review` have adjacent orders, and `review` and `done` have a gap. The call changes
/// the order of the moved column when an integer is between the orders of its new neighbors. Else it changes the
/// orders of as few columns as possible, and each other column keeps its place in the board order.
@Suite("moveColumn", .watcherBudget)
struct MoveColumnTests {
    /// The slug of the fixture column, the first column of the board.
    private static let todo = TaskOperationTests.todoSlug

    /// The slug of the second column.
    private static let doing = "doing"

    /// The slug of the third column.
    private static let review = "review"

    /// The slug of the terminal column.
    private static let done = TaskOperationTests.doneSlug

    /// The order of the fixture column `todo`.
    private static let todoOrder = 0

    /// The order of `doing`.
    private static let doingOrder = 3

    /// The order of `review`: one more than the order of `doing`, so no integer is between them.
    private static let reviewOrder = 4

    /// The order of `done`: two more than the order of `review`, so one integer is between them.
    private static let doneOrder = 6

    /// The one integer between ``reviewOrder`` and ``doneOrder``.
    private static let reviewDoneGapOrder = 5

    /// The order after the order of `done`: the order that a column gets when it goes after `done`.
    private static let afterDoneOrder = 7

    /// The order before the order of `todo`: the order that a column gets when it goes before `todo`.
    private static let beforeTodoOrder = -1

    /// The integer between ``todoOrder`` and ``doingOrder`` that the renumber gives.
    private static let todoDoingGapOrder = 1

    /// The columns that each test adds to the fixture board, with their orders.
    private static let standardColumns = [(doing, doingOrder), (review, reviewOrder), (done, doneOrder)]

    /// The columns of the tie tests: `doing` and `review` have the same order, so the slug sorts them.
    private static let tiedColumns = [(doing, doingOrder), (review, doingOrder), (done, doneOrder)]

    /// A ref that names no column of the board.
    private static let unknownColumn = "nope"

    /// A second ref that names no column of the board.
    private static let secondUnknownColumn = "gone"

    /// The query that lists the live columns of the board, in board order, with their orders.
    private static let columnsQuery = "{ board { columns { id order } } }"

    // MARK: - Helpers

    /// Makes the document that adds columns to the fixture board, with given orders. The name of each column gives its
    /// slug.
    ///
    /// - Parameter columns: The slug and the order of each column.
    /// - Returns: The mutation document.
    private static func setup(adding columns: [(String, Int)]) -> String {
        let fields = columns.map { slug, order in
            #"\#(slug): addColumn(input: { name: "\#(slug)", order: \#(order) }) { id }"#
        }
        return AddUpdateTaskTests.mutation(of: fields.joined(separator: " "))
    }

    /// Makes a new engine of the fixture repo, and adds columns to its board.
    ///
    /// - Parameters:
    ///   - columns: The slug and the order of each column to add.
    ///   - directory: The temporary repo directory.
    /// - Returns: The engine.
    private static func board(
        adding columns: [(String, Int)] = standardColumns,
        in directory: TemporaryDirectory
    ) async throws -> KanbanGraph {
        let graph = try ColumnActorTests.makeFixtureGraph(in: directory).graph
        _ = try await KanbanGraphTests.execute(setup(adding: columns), on: graph)
        return graph
    }

    /// Makes a `moveColumn` field with the selection `{ id order }`.
    ///
    /// - Parameters:
    ///   - slug: The column to move.
    ///   - place: The place fields of the `input` object, or `""` for none.
    /// - Returns: The field.
    private static func move(_ slug: String, placing place: String = "") -> String {
        CommentTests.nodeField(MutationName.moveColumn, naming: slug, with: place, selecting: "{ id order }")
    }

    /// Makes a `before` or an `after` place field.
    ///
    /// - Parameters:
    ///   - side: `before` or `after`.
    ///   - slug: The neighbor column as the input writes it.
    /// - Returns: The `input` field.
    private static func neighbor(_ side: String, _ slug: String) -> String {
        #"\#(side): "\#(slug)""#
    }

    /// Gives the JSON object of a column with the selection `{ id order }`.
    ///
    /// - Parameters:
    ///   - slug: The slug of the column.
    ///   - order: The order of the column.
    /// - Returns: The JSON object text.
    private static func columnJSON(_ slug: String, order: Int) -> String {
        #"{"id":"\#(ColumnActorTests.id(of: .column(slug: slug)))","order":\#(order)}"#
    }

    /// Gives the response of a `moveColumn` field with the selection `{ id order }`, with no `extensions.txn`.
    ///
    /// - Parameters:
    ///   - slug: The slug of the moved column.
    ///   - order: The order of the column after the move.
    /// - Returns: The response JSON text.
    private static func movedResponse(_ slug: String, order: Int) -> String {
        TaskOperationTests.dataResponse(of: #""moveColumn":\#(columnJSON(slug, order: order))"#)
    }

    /// Gives the response of ``columnsQuery``.
    ///
    /// - Parameter columns: The slug and the order of each live column, in board order.
    /// - Returns: The response JSON text.
    private static func columnsResponse(_ columns: [(String, Int)]) -> String {
        let objects = columns.map { slug, order in columnJSON(slug, order: order) }
        return #"{"data":{"board":{"columns":[\#(objects.joined(separator: ","))]}}}"#
    }

    /// Runs ``columnsQuery`` on an engine.
    ///
    /// - Parameter graph: The engine.
    /// - Returns: The response JSON text.
    private static func columns(on graph: KanbanGraph) async throws -> String {
        try await KanbanGraphTests.execute(columnsQuery, on: graph)
    }

    // MARK: - Renumber

    @Test("moveColumn between neighbors with adjacent orders changes the fewest orders, and keeps the other places")
    func moveBetweenAdjacentOrders() async throws {
        let directory = try TemporaryDirectory()
        let graph = try await Self.board(in: directory)
        let response = try await KanbanGraphTests.runWithoutTransaction(
            Self.move(Self.done, placing: Self.neighbor("before", Self.review)),
            on: graph
        )
        #expect(response == Self.movedResponse(Self.done, order: Self.doneOrder))
        let expected = [
            (Self.todo, Self.todoOrder), (Self.doing, Self.doingOrder), (Self.done, Self.doneOrder),
            (Self.review, Self.afterDoneOrder),
        ]
        #expect(try await Self.columns(on: graph) == Self.columnsResponse(expected))
    }

    @Test("moveColumn into a gap between two orders changes only the order of the moved column")
    func moveIntoGapChangesOnlyMovedColumn() async throws {
        let directory = try TemporaryDirectory()
        let graph = try await Self.board(in: directory)
        let response = try await KanbanGraphTests.runWithoutTransaction(
            Self.move(Self.doing, placing: Self.neighbor("after", Self.review)),
            on: graph
        )
        #expect(response == Self.movedResponse(Self.doing, order: Self.reviewDoneGapOrder))
        let expected = [
            (Self.todo, Self.todoOrder), (Self.review, Self.reviewOrder), (Self.doing, Self.reviewDoneGapOrder),
            (Self.done, Self.doneOrder),
        ]
        #expect(try await Self.columns(on: graph) == Self.columnsResponse(expected))
    }

    @Test("moveColumn after the terminal column makes the column the terminal column")
    func moveAfterTerminalColumn() async throws {
        let directory = try TemporaryDirectory()
        let graph = try await Self.board(in: directory)
        let response = try await KanbanGraphTests.runWithoutTransaction(
            Self.move(Self.todo, placing: Self.neighbor("after", Self.done)),
            on: graph
        )
        #expect(response == Self.movedResponse(Self.todo, order: Self.afterDoneOrder))
        let expected = [
            (Self.doing, Self.doingOrder), (Self.review, Self.reviewOrder), (Self.done, Self.doneOrder),
            (Self.todo, Self.afterDoneOrder),
        ]
        #expect(try await Self.columns(on: graph) == Self.columnsResponse(expected))
    }

    @Test("moveColumn before the first column makes the column the first column")
    func moveBeforeFirstColumn() async throws {
        let directory = try TemporaryDirectory()
        let graph = try await Self.board(in: directory)
        let response = try await KanbanGraphTests.runWithoutTransaction(
            Self.move(Self.done, placing: Self.neighbor("before", Self.todo)),
            on: graph
        )
        #expect(response == Self.movedResponse(Self.done, order: Self.beforeTodoOrder))
        let expected = [
            (Self.done, Self.beforeTodoOrder), (Self.todo, Self.todoOrder), (Self.doing, Self.doingOrder),
            (Self.review, Self.reviewOrder),
        ]
        #expect(try await Self.columns(on: graph) == Self.columnsResponse(expected))
    }

    @Test("moveColumn with before and after that are neighbors puts the column between them")
    func moveBetweenBothNeighbors() async throws {
        let directory = try TemporaryDirectory()
        let graph = try await Self.board(in: directory)
        let place = Self.neighbor("after", Self.doing) + " " + Self.neighbor("before", Self.review)
        let response = try await KanbanGraphTests.runWithoutTransaction(
            Self.move(Self.done, placing: place),
            on: graph
        )
        #expect(response == Self.movedResponse(Self.done, order: Self.doneOrder))
        let expected = [
            (Self.todo, Self.todoOrder), (Self.doing, Self.doingOrder), (Self.done, Self.doneOrder),
            (Self.review, Self.afterDoneOrder),
        ]
        #expect(try await Self.columns(on: graph) == Self.columnsResponse(expected))
    }

    // MARK: - Ties

    @Test("moveColumn between two neighbors with the same order gives each column a different order")
    func moveBetweenTiedNeighbors() async throws {
        let directory = try TemporaryDirectory()
        let graph = try await Self.board(adding: Self.tiedColumns, in: directory)
        let response = try await KanbanGraphTests.runWithoutTransaction(
            Self.move(Self.done, placing: Self.neighbor("after", Self.doing)),
            on: graph
        )
        #expect(response == Self.movedResponse(Self.done, order: Self.doneOrder))
        let expected = [
            (Self.todo, Self.todoOrder), (Self.doing, Self.doingOrder), (Self.done, Self.doneOrder),
            (Self.review, Self.afterDoneOrder),
        ]
        #expect(try await Self.columns(on: graph) == Self.columnsResponse(expected))
    }

    @Test("moveColumn before a neighbor with the same order puts the column in the gap before the neighbor")
    func moveBeforeTiedNeighbor() async throws {
        let directory = try TemporaryDirectory()
        let graph = try await Self.board(adding: Self.tiedColumns, in: directory)
        let response = try await KanbanGraphTests.runWithoutTransaction(
            Self.move(Self.review, placing: Self.neighbor("before", Self.doing)),
            on: graph
        )
        #expect(response == Self.movedResponse(Self.review, order: Self.todoDoingGapOrder))
        let expected = [
            (Self.todo, Self.todoOrder), (Self.review, Self.todoDoingGapOrder), (Self.doing, Self.doingOrder),
            (Self.done, Self.doneOrder),
        ]
        #expect(try await Self.columns(on: graph) == Self.columnsResponse(expected))
    }

    // MARK: - One transaction

    @Test("moveColumn writes one transaction, and one undoChange of it gives back each order")
    func moveIsOneTransaction() async throws {
        let directory = try TemporaryDirectory()
        let graph = try await Self.board(adding: Self.tiedColumns, in: directory)
        let before = try await Self.columns(on: graph)
        let move = AddUpdateTaskTests.mutation(of: Self.move(Self.todo, placing: Self.neighbor("after", Self.review)))
        let call = try await ResponseTransactionTests.run(move, on: graph, in: directory)
        let txn = try ResponseTransactionTests.transaction(of: call.response)
        #expect(call.written == [txn], "\(call.response)")
        #expect(try await Self.columns(on: graph) != before)
        let undo = UndoTests.reverseField(MutationName.undoChange, with: #"txn: "\#(txn)""#)
        _ = try await CommentTests.run(undo, on: graph)
        #expect(try await Self.columns(on: graph) == before)
    }

    // MARK: - Forgiving input

    @Test(
        "moveColumn with one ref that names no column uses the other ref, with a NEIGHBOR_NOT_FOUND warning",
        arguments: [
            (neighbor("after", review) + " " + neighbor("before", unknownColumn), "before", "after"),
            (neighbor("after", unknownColumn) + " " + neighbor("before", done), "after", "before"),
        ]
    )
    func unknownNeighborUsesOtherRef(place: String, unknownSide: String, usedSide: String) async throws {
        let directory = try TemporaryDirectory()
        let graph = try await Self.board(in: directory)
        let response = try await KanbanGraphTests.runWithoutTransaction(
            Self.move(Self.doing, placing: place),
            on: graph
        )
        let message = "The \(unknownSide) ref `\(Self.unknownColumn)` names no column. The call put the column by the "
            + "\(usedSide) ref only."
        let warnings = #""extensions":{"warnings":[{"code":"NEIGHBOR_NOT_FOUND","message":"\#(message)"}]}"#
        let data = #""data":{"moveColumn":\#(Self.columnJSON(Self.doing, order: Self.reviewDoneGapOrder))}"#
        #expect(response == "{\(data),\(warnings)}")
        let expected = [
            (Self.todo, Self.todoOrder), (Self.review, Self.reviewOrder), (Self.doing, Self.reviewDoneGapOrder),
            (Self.done, Self.doneOrder),
        ]
        #expect(try await Self.columns(on: graph) == Self.columnsResponse(expected))
    }

    @Test(
        "moveColumn to the place where the column is, or next to itself, writes nothing",
        arguments: [
            neighbor("after", todo), neighbor("before", review), neighbor("after", doing), neighbor("before", doing),
        ]
    )
    func moveToSamePlaceWritesNothing(place: String) async throws {
        let response = try await ColumnActorTests.respondWritingNothing(
            to: AddUpdateTaskTests.mutation(of: Self.move(Self.doing, placing: place)),
            after: Self.setup(adding: Self.standardColumns),
            in: try TemporaryDirectory()
        )
        #expect(response == Self.movedResponse(Self.doing, order: Self.doingOrder))
    }

    // MARK: - Errors

    /// Runs a `moveColumn` field that fails on the board of ``standardColumns``, expects that the call writes no log
    /// file, and expects the full response: `null` for the field, and the one error.
    ///
    /// - Parameters:
    ///   - field: The `moveColumn` field.
    ///   - error: The error that the field must give.
    ///   - code: The code that `extensions.code` must give.
    private static func expectFailure(of field: String, giving error: KanbanError, coded code: String) async throws {
        let document = AddUpdateTaskTests.mutation(of: field)
        let response = try await ColumnActorTests.respondWritingNothing(
            to: document,
            after: setup(adding: standardColumns),
            in: try TemporaryDirectory()
        )
        let errorJSON = try ErrorCoverageTests.errorJSON(
            of: error,
            extensions: #"{"code":"\#(code)"}"#,
            at: MutationName.moveColumn,
            in: document,
            path: #"["\#(MutationName.moveColumn)"]"#
        )
        #expect(response == #"{"data":{"moveColumn":null},"errors":[\#(errorJSON)]}"#)
    }

    @Test("moveColumn with no before and no after gives MISSING_PLACEMENT and writes nothing")
    func noPlaceGivesMissingPlacement() async throws {
        try await Self.expectFailure(
            of: Self.move(Self.todo),
            giving: .missingColumnPlacement(column: Self.todo),
            coded: "MISSING_PLACEMENT"
        )
    }

    @Test(
        "moveColumn with one ref that names no column and no other ref gives NOT_FOUND and writes nothing",
        arguments: ["before", "after"]
    )
    func onlyUnknownNeighborGivesNotFound(side: String) async throws {
        try await Self.expectFailure(
            of: Self.move(Self.doing, placing: Self.neighbor(side, Self.unknownColumn)),
            giving: .notFound(type: .column, reference: Self.unknownColumn),
            coded: "NOT_FOUND"
        )
    }

    @Test("moveColumn with two refs that name no column gives NOT_FOUND with each ref and writes nothing")
    func twoUnknownNeighborsGiveNotFound() async throws {
        let place = Self.neighbor("after", Self.unknownColumn) + " "
            + Self.neighbor("before", Self.secondUnknownColumn)
        try await Self.expectFailure(
            of: Self.move(Self.doing, placing: place),
            giving: .nodesNotFound(type: .column, references: [Self.unknownColumn, Self.secondUnknownColumn]),
            coded: "NOT_FOUND"
        )
    }

    @Test("moveColumn with before and after that are not neighbors gives CONFLICTING_PLACEMENT and writes nothing")
    func distantNeighborsGiveConflictingPlacement() async throws {
        let place = Self.neighbor("after", Self.todo) + " " + Self.neighbor("before", Self.done)
        try await Self.expectFailure(
            of: Self.move(Self.review, placing: place),
            giving: .conflictingColumnPlacement(after: Self.todo, before: Self.done),
            coded: "CONFLICTING_PLACEMENT"
        )
    }

    @Test("moveColumn with an id that names no column gives NOT_FOUND and writes nothing")
    func unknownColumnGivesNotFound() async throws {
        try await Self.expectFailure(
            of: Self.move(Self.unknownColumn, placing: Self.neighbor("after", Self.todo)),
            giving: .notFound(type: .column, reference: Self.unknownColumn),
            coded: "NOT_FOUND"
        )
    }
}
