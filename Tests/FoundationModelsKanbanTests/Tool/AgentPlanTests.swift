import Foundation
import FoundationModelsExtras
import Testing

@testable import FoundationModelsKanban

/// Tests the ACP agent plan of one board (https://agentclientprotocol.com/protocol/v2/agent-plan): the entries, their
/// order, their status, their priority, and the detail line.
@Suite("Agent plan")
struct AgentPlanTests {
    /// The title of the task in the first column.
    static let pendingTitle = "Write the lexer"

    /// The title of the task in a column between the first column and the terminal column.
    static let inProgressTitle = "Write the parser"

    /// The title of the task in the terminal column.
    static let doneTitle = "Write the plan"

    /// The title of the tombstoned task.
    static let deletedTitle = "Write the old parser"

    /// Gives the agent plan of a board.
    ///
    /// - Parameter board: The board.
    /// - Returns: The plan.
    static func plan(of board: ReadinessFixture) -> PlanSnapshot {
        PlanSnapshot(of: board.readiness, inBoard: DependencyMarkersTests.boardKey)
    }

    /// Makes a board with one task in the first column, one in `doing`, one in the terminal column, and one
    /// tombstone. The ULID order is the reverse of the board order.
    ///
    /// - Returns: The board.
    /// - Throws: An error when a test ULID is not valid.
    static func mixedBoard() throws -> ReadinessFixture {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.first, titled: doneTitle, inColumn: ReadinessFixture.done)
        try board.addTask(withULID: ReadinessFixture.second, titled: inProgressTitle, inColumn: ReadinessFixture.doing)
        try board.addTask(withULID: ReadinessFixture.third, titled: pendingTitle)
        let tombstone = ReadinessFixture.fields(isDeleted: true)
        try board.addTask(withULID: ReadinessFixture.fourth, titled: deletedTitle, fields: tombstone)
        return board
    }

    @Test("The plan has the board key as id and one entry for each live task in board order, with its title")
    func entriesInBoardOrder() throws {
        let plan = Self.plan(of: try Self.mixedBoard())
        #expect(plan.id == DependencyMarkersTests.boardKey)
        #expect(plan.entries.map(\.content) == [Self.pendingTitle, Self.inProgressTitle, Self.doneTitle])
    }

    @Test("A task in the first column is pending, a task in a later column is in progress, and a done task completed")
    func statusOfEachColumn() throws {
        let plan = Self.plan(of: try Self.mixedBoard())
        #expect(plan.entries.map(\.status) == [.pending, .inProgress, .completed])
    }

    @Test("An open task has the priority of its third, and a done task is LOW")
    func priorityOfOpenAndDoneTasks() throws {
        let plan = Self.plan(of: try Self.mixedBoard())
        #expect(plan.entries.map(\.priority) == [.high, .medium, .low])
    }

    @Test(
        "The plan gives each open task the priority of its third of the board order",
        arguments: PriorityTagsTests.tiersByCount
    )
    func priorityOfEachRank(count: Int, tiers: [PriorityTier]) throws {
        let plan = Self.plan(of: try PriorityTagsTests.board(withOpenTasks: count))
        #expect(plan.entries.map(\.priority) == tiers.map(PlanSnapshot.Priority.init))
        #expect(plan.entries.map(\.content) == Array(PriorityTagsTests.tasks.prefix(count)))
    }

    @Test("A task that moves changes its place, status, and priority in the plan, and a move back restores them")
    func movedTaskChangesItsEntry() throws {
        var board = try PriorityTagsTests.board(withOpenTasks: PriorityTagsTests.movedBoardSize)
        let moved = PriorityTagsTests.tasks[0]
        let before = Self.plan(of: board)
        try board.addTask(withULID: moved, titled: moved, inColumn: ReadinessFixture.done)
        let done = try #require(Self.plan(of: board).entries.last)
        #expect(done == PlanSnapshot.Entry(content: moved, priority: .low, status: .completed))
        try board.addTask(withULID: moved, titled: moved)
        #expect(Self.plan(of: board) == before)
    }

    @Test("The detail line tells how many of the live tasks are done")
    func detailCountsDoneTasks() throws {
        #expect(try Self.mixedBoard().readiness.summary.progressDetail == "1 of 3 tasks done")
    }
}
