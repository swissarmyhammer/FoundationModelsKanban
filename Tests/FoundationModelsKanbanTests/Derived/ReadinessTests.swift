import Foundation
import Testing

@testable import FoundationModelsKanban

/// Tests the readiness of a task at read time: the terminal column, done, `ready`, `blockedBy`, and `blocks`
/// (plan.md §3.3 rules 3 and 4, §5.3 steps 4 and 5, §6). The port of the readiness tests of the Rust
/// `task_helpers.rs` is in the "Rust" section.
@Suite("Readiness")
struct ReadinessTests {
    // MARK: - Terminal column

    @Test("The terminal column is the live column with the maximum order")
    func terminalColumnHasMaximumOrder() throws {
        var board = ReadinessFixture()
        board.addColumn(withSlug: "archive", order: Int.max, isDeleted: true)
        let done = try #require(board.graph.slot(for: .column(slug: ReadinessFixture.done)))
        #expect(ColumnOrder(of: board.graph).terminal == done)
    }

    @Test("Two columns with the maximum order sort by slug, and the last slug is the terminal column")
    func terminalColumnTieSortsBySlug() throws {
        var board = ReadinessFixture()
        board.addColumn(withSlug: "shipped", order: Int.max)
        board.addColumn(withSlug: "closed", order: Int.max)
        let shipped = try #require(board.graph.slot(for: .column(slug: "shipped")))
        #expect(ColumnOrder(of: board.graph).terminal == shipped)
    }

    @Test("A graph with no live column has no terminal column, and no task is done")
    func noColumnMeansNoTerminalColumn() throws {
        var board = ReadinessFixture()
        board.graph = Graph()
        board.addColumn(withSlug: ReadinessFixture.done, order: .zero, isDeleted: true)
        let slot = try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.done)
        #expect(ColumnOrder(of: board.graph).terminal == nil)
        #expect(!board.readiness.isDone(taskAt: slot))
    }

    // MARK: - Done

    @Test("A task in the terminal column is done, and a task in another column or with no column is not done")
    func doneMeansTerminalColumn() throws {
        var board = ReadinessFixture()
        let done = try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.done)
        let doing = try board.addTask(withULID: ReadinessFixture.second, inColumn: ReadinessFixture.doing)
        let noColumn = try board.addTask(withULID: ReadinessFixture.third, inColumn: nil)
        let readiness = board.readiness
        #expect(readiness.isDone(taskAt: done))
        #expect(!readiness.isDone(taskAt: doing))
        #expect(!readiness.isDone(taskAt: noColumn))
    }

    @Test("A new column with a larger order makes the tasks of the old terminal column not done")
    func newTerminalColumnChangesDone() throws {
        var board = ReadinessFixture()
        let slot = try board.addTask(withULID: ReadinessFixture.first, inColumn: ReadinessFixture.done)
        board.addColumn(withSlug: "shipped", order: Int.max)
        #expect(!board.readiness.isDone(taskAt: slot))
    }

    // MARK: - Rust

    @Test("A task with no dependencies is ready (Rust test_task_is_ready_no_deps)")
    func readyWithNoDependencies() throws {
        var board = ReadinessFixture()
        let slot = try board.addTask(withULID: ReadinessFixture.first)
        #expect(board.readiness.isReady(taskAt: slot))
        #expect(board.readiness.blockers(ofTaskAt: slot).isEmpty)
    }

    @Test("A task whose dependencies are done is ready (Rust test_task_is_ready_deps_complete)")
    func readyWhenDependenciesDone() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.second, inColumn: ReadinessFixture.done)
        let slot = try board.addTask(withULID: ReadinessFixture.first, dependingOn: [ReadinessFixture.second])
        #expect(board.readiness.isReady(taskAt: slot))
    }

    @Test("A task with a dependency that is not done is blocked by it (Rust test_task_blocked_by)")
    func blockedByDependencyNotDone() throws {
        var board = ReadinessFixture()
        let dependency = try board.addTask(withULID: ReadinessFixture.second)
        let slot = try board.addTask(withULID: ReadinessFixture.first, dependingOn: [ReadinessFixture.second])
        #expect(!board.readiness.isReady(taskAt: slot))
        #expect(board.readiness.blockers(ofTaskAt: slot) == [.slot(dependency)])
    }

    @Test("A task that depends on an unknown task is blocked by it (Rust missing dependency tests)")
    func unknownDependencyBlocks() throws {
        var board = ReadinessFixture()
        let slot = try board.addTask(withULID: ReadinessFixture.first, dependingOn: [ReadinessFixture.ghost])
        let ghost = try ReadinessFixture.edge(toTask: ReadinessFixture.ghost)
        #expect(!board.readiness.isReady(taskAt: slot))
        #expect(board.readiness.blockers(ofTaskAt: slot) == [ghost])
    }

    @Test("The tasks that depend on a task are the tasks that it blocks (Rust test_task_blocks)")
    func blocksGivesDependents() throws {
        var board = ReadinessFixture()
        let target = try board.addTask(withULID: ReadinessFixture.first)
        let dependent = try board.addTask(withULID: ReadinessFixture.second, dependingOn: [ReadinessFixture.first])
        let other = try board.addTask(
            withULID: ReadinessFixture.third,
            dependingOn: [ReadinessFixture.first, ReadinessFixture.ghost]
        )
        try board.addTask(withULID: ReadinessFixture.fourth)
        #expect(board.readiness.dependents(ofTaskAt: target) == [dependent, other])
    }

    @Test("A task that no task depends on blocks nothing (Rust find_dependent_task_ids, no reverse dependencies)")
    func noDependentsBlocksNothing() throws {
        var board = ReadinessFixture()
        let target = try board.addTask(withULID: ReadinessFixture.first)
        try board.addTask(withULID: ReadinessFixture.second)
        #expect(board.readiness.dependents(ofTaskAt: target).isEmpty)
    }

    // MARK: - Unknown and remote targets

    @Test("A task that depends on a task of a board that is not loaded is blocked")
    func remoteDependencyBlocks() throws {
        var board = ReadinessFixture()
        let otherBoard = DependencyMarkersTests.otherBoardKey
        let uri = try DependencyMarkersTests.uri(ofTask: ReadinessFixture.second, inBoard: otherBoard)
        let slot = try board.addTask(withULID: ReadinessFixture.first, dependingOnRemote: [uri])
        #expect(!board.readiness.isReady(taskAt: slot))
        #expect(board.readiness.blockers(ofTaskAt: slot) == [.unresolved(.remote(uri))])
    }

    @Test("A dependency marker in the body counts the same as an edge")
    func markerCountsAsDependency() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.second, inColumn: ReadinessFixture.done)
        let doneBody = "Wait for \(DependencyMarkersTests.url(ofTask: ReadinessFixture.second))."
        let ready = try board.addTask(withULID: ReadinessFixture.first, fields: ReadinessFixture.fields(body: doneBody))
        let ghostBody = "Wait for \(DependencyMarkersTests.url(ofTask: ReadinessFixture.ghost))."
        let blocked = try board.addTask(
            withULID: ReadinessFixture.third,
            fields: ReadinessFixture.fields(body: ghostBody)
        )
        #expect(board.readiness.isReady(taskAt: ready))
        #expect(!board.readiness.isReady(taskAt: blocked))
    }

    // MARK: - Tombstones

    @Test("A dependency on a tombstoned task is ignored")
    func tombstonedDependencyIsIgnored() throws {
        var board = ReadinessFixture()
        try board.addTask(withULID: ReadinessFixture.second, fields: ReadinessFixture.fields(isDeleted: true))
        let slot = try board.addTask(withULID: ReadinessFixture.first, dependingOn: [ReadinessFixture.second])
        #expect(board.readiness.isReady(taskAt: slot))
        #expect(board.readiness.blockers(ofTaskAt: slot).isEmpty)
    }

    @Test("A tombstoned task that depends on a task is not one of its dependents")
    func tombstonedDependentIsIgnored() throws {
        var board = ReadinessFixture()
        let target = try board.addTask(withULID: ReadinessFixture.first)
        try board.addTask(
            withULID: ReadinessFixture.second,
            dependingOn: [ReadinessFixture.first],
            fields: ReadinessFixture.fields(isDeleted: true)
        )
        #expect(board.readiness.dependents(ofTaskAt: target).isEmpty)
    }

    // MARK: - Cycles from a merge

    @Test("Each task of a dependency cycle is blocked, and the walk ends")
    func cycleBlocksEachTask() throws {
        var board = ReadinessFixture()
        let first = try board.addTask(withULID: ReadinessFixture.first, dependingOn: [ReadinessFixture.second])
        let second = try board.addTask(withULID: ReadinessFixture.second, dependingOn: [ReadinessFixture.first])
        let readiness = board.readiness
        #expect(readiness.blockers(ofTaskAt: first) == [.slot(second)])
        #expect(readiness.blockers(ofTaskAt: second) == [.slot(first)])
    }

    @Test("A task of a cycle is blocked by the next task of the cycle, also when that task is done")
    func cycleBlocksAlsoWhenDone() throws {
        var board = ReadinessFixture()
        let first = try board.addTask(
            withULID: ReadinessFixture.first,
            inColumn: ReadinessFixture.done,
            dependingOn: [ReadinessFixture.second]
        )
        let second = try board.addTask(
            withULID: ReadinessFixture.second,
            inColumn: ReadinessFixture.done,
            dependingOn: [ReadinessFixture.third]
        )
        let third = try board.addTask(withULID: ReadinessFixture.third, dependingOn: [ReadinessFixture.first])
        let readiness = board.readiness
        #expect(readiness.blockers(ofTaskAt: first) == [.slot(second)])
        #expect(readiness.blockers(ofTaskAt: second) == [.slot(third)])
        #expect(readiness.blockers(ofTaskAt: third) == [.slot(first)])
    }

    @Test("A task that depends on itself is blocked")
    func selfDependencyBlocks() throws {
        var board = ReadinessFixture()
        let slot = try board.addTask(
            withULID: ReadinessFixture.first,
            inColumn: ReadinessFixture.done,
            dependingOn: [ReadinessFixture.first]
        )
        #expect(board.readiness.blockers(ofTaskAt: slot) == [.slot(slot)])
    }

    @Test("A task that depends on a done task of a cycle that does not hold the task is ready, and the walk ends")
    func cycleBehindDoneDependencyDoesNotBlock() throws {
        var board = ReadinessFixture()
        try board.addTask(
            withULID: ReadinessFixture.second,
            inColumn: ReadinessFixture.done,
            dependingOn: [ReadinessFixture.third]
        )
        try board.addTask(withULID: ReadinessFixture.third, dependingOn: [ReadinessFixture.second])
        let slot = try board.addTask(withULID: ReadinessFixture.first, dependingOn: [ReadinessFixture.second])
        #expect(board.readiness.isReady(taskAt: slot))
    }
}
