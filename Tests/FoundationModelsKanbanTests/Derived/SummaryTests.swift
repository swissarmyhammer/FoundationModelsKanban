import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the `summary` of a board: the counts of its live tasks (plan.md §4.1, §6). The tests in the "Rust" section
/// are the port of the summary tests of the Rust `board/get.rs`.
@Suite("Summary")
struct SummaryTests {
    /// A count of three tasks.
    static let threeTasks = 3

    /// A count of two tasks.
    static let twoTasks = 2

    /// The percent of done tasks when one task of three is done, rounded.
    static let oneOfThreePercent = 33

    /// The number of live tasks of the hand-counted board of ``handCountedBoard()``.
    static let handCountedTotal = 6

    /// The number of ready tasks of the hand-counted board: the two done tasks, the task that waits for a done task,
    /// and the task with no column.
    static let handCountedReady = 4

    /// The number of done tasks of the hand-counted board.
    static let handCountedDone = 2

    /// The number of blocked tasks of the hand-counted board: the task that waits for an unknown task, and the task
    /// that waits for a task that is not done.
    static let handCountedBlocked = 2

    /// The ULID text of a fifth task: it waits for the third task.
    static let fifth = "01KT6YF2C37Q9S1V3W5X7Y9Z1A"

    /// The ULID text of a sixth task: a tombstone.
    static let sixth = "01KT6ZG3D48R0T2W4X6Y8Z0A2B"

    /// The ULID text of a seventh task: it has no column.
    static let seventh = "01KT70H4E59S1V3X5Y7Z9A1B3C"

    // MARK: - Rust

    @Test("A board with no tasks has zero counts and zero percent (Rust test_empty_board)")
    func emptyBoardHasZeroCounts() {
        let summary = ReadinessFixture().readiness.summary
        #expect(summary == BoardSummary(total: .zero, ready: .zero, done: .zero))
        #expect(summary.blocked == .zero)
        #expect(summary.percent == .zero)
    }

    @Test("One done task of three is 33 percent (Rust test_board_with_tasks_in_different_columns)")
    func tasksInEachColumn() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first)
        try board.addTask(withULID: ReadinessFixture.second, inColumn: ReadinessFixture.doing)
        try board.addTask(withULID: ReadinessFixture.third, inColumn: ReadinessFixture.done)
        let summary = board.readiness.summary
        #expect(summary.total == Self.threeTasks)
        #expect(summary.done == 1)
        #expect(summary.percent == Self.oneOfThreePercent)
    }

    @Test("A task that waits for a task that is not done is blocked (Rust test_ready_vs_blocked_counts)")
    func readyAndBlockedCounts() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first)
        try board.addTask(withULID: ReadinessFixture.second, dependingOn: [ReadinessFixture.first])
        try board.addTask(withULID: ReadinessFixture.third)
        #expect(board.readiness.summary.ready == Self.twoTasks)
        #expect(board.readiness.summary.blocked == 1)
        try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.done)
        #expect(board.readiness.summary.ready == Self.threeTasks)
        #expect(board.readiness.summary.blocked == .zero)
    }

    @Test("A tombstoned task is not counted (Rust test_get_board_excludes_archived_from_counts)")
    func tombstonedTaskIsNotCounted() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first)
        try board.addTask(withULID: ReadinessFixture.second, fields: ReadinessFixture.fields(isDeleted: true))
        try board.addTask(withULID: ReadinessFixture.third)
        #expect(board.readiness.summary.total == Self.twoTasks)
    }

    // MARK: - Hand-counted board

    @Test("The counts of a mixed board match a hand count")
    func handCountedBoard() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.done)
        try board.addTask(withULID: ReadinessFixture.second, inColumn: ReadinessFixture.done)
        try board.addTask(
            withULID: ReadinessFixture.third,
            inColumn: ReadinessFixture.doing,
            dependingOn: [ReadinessFixture.first]
        )
        try board.addTask(withULID: ReadinessFixture.fourth, dependingOn: [ReadinessFixture.ghost])
        try board.addTask(withULID: Self.fifth, dependingOn: [ReadinessFixture.third])
        try board.addTask(withULID: Self.sixth, fields: ReadinessFixture.fields(isDeleted: true))
        try board.addTask(withULID: Self.seventh, inColumn: nil)
        let summary = board.readiness.summary
        let expected = BoardSummary(
            total: Self.handCountedTotal,
            ready: Self.handCountedReady,
            done: Self.handCountedDone
        )
        #expect(summary == expected)
        #expect(summary.blocked == Self.handCountedBlocked)
        #expect(summary.percent == Self.oneOfThreePercent)
    }

    @Test("All tasks done is 100 percent")
    func allDoneIsFullPercent() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.done)
        #expect(board.readiness.summary.percent == 100)
    }
}
