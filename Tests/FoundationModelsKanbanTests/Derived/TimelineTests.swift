import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the `started` and `completed` times of a task, which come from its column moves and the current column order
/// (plan.md §5.3 steps 3 and 4).
@Suite("Timeline")
struct TimelineTests {
    /// The time of the first move of a test task, in seconds.
    static let firstSecond = 10

    /// The time of the second move of a test task, in seconds.
    static let secondSecond = 20

    /// The time of the third move of a test task, in seconds.
    static let thirdSecond = 30

    /// The time of the fourth move of a test task, in seconds.
    static let fourthSecond = 40

    /// The slug of a column that the tests delete.
    static let archive = "archive"

    /// The moves of a task that went to `todo`, `doing`, and `done`, in this order.
    static let throughDoing = [
        ReadinessFixture.move(toColumn: ReadinessFixture.todo, atSecond: firstSecond),
        ReadinessFixture.move(toColumn: ReadinessFixture.doing, atSecond: secondSecond),
        ReadinessFixture.move(toColumn: ReadinessFixture.done, atSecond: thirdSecond),
    ]

    // MARK: - Started

    @Test("started is the time of the first move to a column that is not the first column")
    func startedIsFirstMoveOutOfFirstColumn() throws {
        var board = ReadinessFixture()
        let slot = try board.addTask(
            withULID: ReadinessFixture.first,
            inColumn: ReadinessFixture.done,
            withMoves: Self.throughDoing
        )
        #expect(board.readiness.started(ofTaskAt: slot) == ReadinessFixture.time(atSecond: Self.secondSecond))
    }

    @Test("A task that only moved to the first column has not started")
    func onlyFirstColumnIsNotStarted() throws {
        var board = ReadinessFixture()
        let moves = [
            ReadinessFixture.move(toColumn: ReadinessFixture.todo, atSecond: Self.firstSecond),
            ReadinessFixture.move(toColumn: ReadinessFixture.todo, atSecond: Self.secondSecond),
        ]
        let slot = try board.addTask(withULID: ReadinessFixture.first, withMoves: moves)
        #expect(board.readiness.started(ofTaskAt: slot) == nil)
    }

    @Test("A task that was made in a column that is not the first column started when it was made")
    func madeInLaterColumnStartedAtOnce() throws {
        var board = ReadinessFixture()
        let slot = try board.addTask(
            withULID: ReadinessFixture.first,
            inColumn: ReadinessFixture.doing,
            withMoves: [ReadinessFixture.move(toColumn: ReadinessFixture.doing, atSecond: Self.firstSecond)]
        )
        #expect(board.readiness.started(ofTaskAt: slot) == ReadinessFixture.time(atSecond: Self.firstSecond))
    }

    @Test("started uses the current column order, not the order at the time of the move")
    func startedUsesCurrentColumnOrder() throws {
        var board = ReadinessFixture()
        board.addColumn(withSlug: ReadinessFixture.doing, order: -1)
        let moves = [
            ReadinessFixture.move(toColumn: ReadinessFixture.doing, atSecond: Self.firstSecond),
            ReadinessFixture.move(toColumn: ReadinessFixture.todo, atSecond: Self.secondSecond),
        ]
        let slot = try board.addTask(withULID: ReadinessFixture.first, withMoves: moves)
        #expect(board.readiness.started(ofTaskAt: slot) == ReadinessFixture.time(atSecond: Self.secondSecond))
    }

    @Test("A move to a tombstoned column counts as a move to the first column")
    func moveToTombstonedColumnIsNotStarted() throws {
        var board = ReadinessFixture()
        board.addColumn(withSlug: Self.archive, order: .zero, isDeleted: true)
        let moves = [
            ReadinessFixture.move(toColumn: Self.archive, atSecond: Self.firstSecond),
            ReadinessFixture.move(toColumn: ReadinessFixture.doing, atSecond: Self.secondSecond),
        ]
        let slot = try board.addTask(
            withULID: ReadinessFixture.first,
            inColumn: ReadinessFixture.doing,
            withMoves: moves
        )
        #expect(board.readiness.started(ofTaskAt: slot) == ReadinessFixture.time(atSecond: Self.secondSecond))
    }

    @Test("A task with no moves has not started and is not completed")
    func noMovesHasNoTimes() throws {
        var board = ReadinessFixture()
        let slot = try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.done)
        #expect(board.readiness.started(ofTaskAt: slot) == nil)
        #expect(board.readiness.completed(ofTaskAt: slot) == nil)
    }

    // MARK: - Completed

    @Test("completed is the time of the last move when the task is in the terminal column")
    func completedIsLastMove() throws {
        var board = ReadinessFixture()
        let moves = Self.throughDoing + [
            ReadinessFixture.move(toColumn: ReadinessFixture.doing, atSecond: Self.thirdSecond),
            ReadinessFixture.move(toColumn: ReadinessFixture.done, atSecond: Self.fourthSecond),
        ]
        let slot = try board.addTask(
            withULID: ReadinessFixture.first,
            inColumn: ReadinessFixture.done,
            withMoves: moves
        )
        #expect(board.readiness.completed(ofTaskAt: slot) == ReadinessFixture.time(atSecond: Self.fourthSecond))
    }

    @Test("A task that is not in the terminal column is not completed")
    func notInTerminalColumnIsNotCompleted() throws {
        var board = ReadinessFixture()
        let slot = try board.addTask(
            withULID: ReadinessFixture.first,
            inColumn: ReadinessFixture.doing,
            withMoves: Array(Self.throughDoing.dropLast())
        )
        #expect(board.readiness.completed(ofTaskAt: slot) == nil)
    }

    @Test("A new column with a larger order makes the tasks of the old terminal column not completed")
    func newTerminalColumnChangesCompleted() throws {
        var board = ReadinessFixture()
        let slot = try board.addTask(
            withULID: ReadinessFixture.first,
            inColumn: ReadinessFixture.done,
            withMoves: Self.throughDoing
        )
        #expect(board.readiness.completed(ofTaskAt: slot) == ReadinessFixture.time(atSecond: Self.thirdSecond))
        board.addColumn(withSlug: "shipped", order: Int.max)
        #expect(board.readiness.completed(ofTaskAt: slot) == nil)
    }

    @Test("A slot that holds no task has no times")
    func notATaskHasNoTimes() throws {
        let board = ReadinessFixture()
        let slot = try board.slot(ofColumn: ReadinessFixture.doing)
        #expect(board.readiness.started(ofTaskAt: slot) == nil)
        #expect(board.readiness.completed(ofTaskAt: slot) == nil)
    }
}
