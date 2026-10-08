import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the priority tags `HIGH`, `MEDIUM`, and `LOW`: the derived tags that come from the place of an open task in
/// board order (plan.md §6, "Virtual tags").
@Suite("Priority tags")
struct PriorityTagsTests {
    /// The ULID texts of seven tasks, in ULID order. The tasks of one column with the same ordinal sort by ULID, so
    /// this is also their board order.
    static let tasks = [
        "01KT6R6HR3KJT6JVNDRAJV8V40",
        "01KT6R6HR3KJT6JVNDRAJV8V41",
        "01KT6R6HR3KJT6JVNDRAJV8V42",
        "01KT6R6HR3KJT6JVNDRAJV8V43",
        "01KT6R6HR3KJT6JVNDRAJV8V44",
        "01KT6R6HR3KJT6JVNDRAJV8V45",
        "01KT6R6HR3KJT6JVNDRAJV8V46",
    ]

    /// The priority tiers of each count of open tasks, in board order: the first third is `HIGH`, the second third
    /// `MEDIUM`, and the rest `LOW`.
    static let tiersByCount: [(count: Int, tiers: [PriorityTier])] = [
        (count: 1, tiers: [.high]),
        (count: 2, tiers: [.high, .medium]),
        (count: 3, tiers: [.high, .medium, .low]),
        (count: 7, tiers: [.high, .high, .high, .medium, .medium, .low, .low]),
    ]

    /// The priority tags: the virtual tag of each tier.
    static let priorityTags = Set(PriorityTier.allCases.map(\.virtualTag))

    /// The number of open tasks of the move tests.
    static let movedBoardSize = 3

    /// Gives the priority tags of one task of a board.
    ///
    /// - Parameters:
    ///   - text: The ULID text of the task.
    ///   - board: The board that holds the task.
    /// - Returns: The priority tags in the virtual tags of the task.
    /// - Throws: An error when the graph does not have the task.
    static func priority(ofTask text: String, on board: ReadinessFixture) throws -> [VirtualTag] {
        try VirtualTagsTests.tags(ofTask: text, on: board).filter(priorityTags.contains)
    }

    /// Makes a board with some tasks in the first column. The title of each task is its ULID text.
    ///
    /// - Parameter count: The number of tasks, from the start of ``tasks``.
    /// - Returns: The board.
    /// - Throws: An error when a test ULID is not valid.
    static func board(withOpenTasks count: Int) throws -> ReadinessFixture {
        var board = ReadinessFixture()
        for text in tasks.prefix(count) {
            try board.addTask(withULID: text, titled: text)
        }
        return board
    }

    @Test(
        "The first third of the open tasks in board order is HIGH, the second third MEDIUM, and the rest LOW",
        arguments: tiersByCount
    )
    func tiersOfOpenTasks(count: Int, tiers: [PriorityTier]) throws {
        let board = try Self.board(withOpenTasks: count)
        let found = try Self.tasks.prefix(count).flatMap { text in try Self.priority(ofTask: text, on: board) }
        #expect(found == tiers.map(\.virtualTag))
    }

    @Test("A done task has no priority tag, and the open tasks rank without it")
    func doneTaskHasNoPriority() throws {
        var board = try Self.board(withOpenTasks: Self.movedBoardSize)
        try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.done)
        #expect(try VirtualTagsTests.tags(ofTask: ReadinessFixture.first, on: board) == [.done])
        let found = try Self.tasks.prefix(Self.movedBoardSize).flatMap { text in
            try Self.priority(ofTask: text, on: board)
        }
        #expect(found == [.high, .medium, .low])
    }

    @Test("A deleted task has no priority tag")
    func deletedTaskHasNoPriority() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first, fields: ReadinessFixture.fields(isDeleted: true))
        try board.addTask(withULID: ReadinessFixture.second)
        #expect(try VirtualTagsTests.tags(ofTask: ReadinessFixture.first, on: board) == [.deleted])
        #expect(try Self.priority(ofTask: ReadinessFixture.second, on: board) == [.high])
    }

    @Test("A task that moves to a later column changes tier, and a move back gives the first tier again")
    func movedTaskChangesTier() throws {
        var board = try Self.board(withOpenTasks: Self.movedBoardSize)
        let moved = Self.tasks[0]
        #expect(try Self.priority(ofTask: moved, on: board) == [.high])
        try board.addTask(withULID: moved, inColumn: ReadinessFixture.doing)
        #expect(try Self.priority(ofTask: moved, on: board) == [.low])
        #expect(try Self.priority(ofTask: Self.tasks[1], on: board) == [.high])
        try board.addTask(withULID: moved)
        #expect(try Self.priority(ofTask: moved, on: board) == [.high])
        #expect(try Self.priority(ofTask: Self.tasks[1], on: board) == [.medium])
    }

    @Test("A task that becomes done loses its priority tag, and a task that opens again gets it back")
    func doneTaskLosesPriority() throws {
        var board = try Self.board(withOpenTasks: Self.movedBoardSize)
        let moved = Self.tasks[0]
        try board.addTask(withULID: moved, inColumn: ReadinessFixture.done)
        #expect(try Self.priority(ofTask: moved, on: board).isEmpty)
        #expect(try Self.priority(ofTask: Self.tasks[1], on: board) == [.high])
        try board.addTask(withULID: moved)
        #expect(try Self.priority(ofTask: moved, on: board) == [.high])
    }
}
