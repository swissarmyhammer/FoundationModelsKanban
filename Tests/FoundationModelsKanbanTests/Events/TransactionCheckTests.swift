import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the read side of the crash safety of a transaction on many files (divergence.md Q23, S5): the load and
/// `LiveGraph.reload` do not apply a transaction that is not complete in all its files, apply a complete transaction,
/// and apply an old line with no file count. A transaction that is not complete applies when its missing file
/// arrives later.
///
/// Each test writes the board fixture of the loader tests to a temporary folder, and then writes the lines of one
/// transaction directly to the log files. No test reads the `.kanban/` folder of this repo.
@Suite("Transaction check at load and reload", .watcherBudget)
struct TransactionCheckTests {
    /// The step of the events of the test transaction. It is after each step of the board fixture.
    static let transactionStep = 2_000

    /// The title that the test transaction sets on each of its tasks.
    static let transactionTitle = "set by the transaction"

    /// The count of the files of the test transaction: the log files of its two tasks.
    static let transactionFileCount = 2

    // MARK: - Fixture

    /// A board fixture and the events of one transaction that sets ``transactionTitle`` on two tasks of the board.
    struct Fixture {
        /// The temporary folder. The value keeps it, so that the folder stays until the test ends.
        let directory: TemporaryDirectory

        /// The event log of the board.
        let log: EventLog

        /// The two tasks of the transaction.
        let tasks: [LocalRef]

        /// The events of the transaction, one for each task, in the order of the tasks. No file holds them yet.
        let events: [Event]
    }

    /// Writes the board fixture, and makes the events of one transaction on two of its tasks.
    ///
    /// - Parameter fileCount: The file count of each event of the transaction, or `nil` for an old line with no
    ///   count.
    /// - Returns: The fixture.
    static func makeFixture(fileCount: Int?) throws -> Fixture {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let tasks = Array(try LiveGraphApplyTests.writeBoard(to: log).prefix(transactionFileCount))
        let events = try transactionEvents(settingTitleOf: tasks, fileCount: fileCount)
        return Fixture(directory: directory, log: log, tasks: tasks, events: events)
    }

    /// Makes the events of one transaction that sets ``transactionTitle`` on each of some tasks.
    ///
    /// - Parameters:
    ///   - tasks: The local refs of the tasks.
    ///   - fileCount: The file count of each event, or `nil` for an old line with no count.
    /// - Returns: The events, one for each task, in the order of the tasks. Their ids increase.
    static func transactionEvents(settingTitleOf tasks: [LocalRef], fileCount: Int?) throws -> [Event] {
        let date = ReplayTests.date(atStep: transactionStep)
        let txn = ULID(timestamp: date)
        return try tasks.enumerated().map { offset, task in
            Event(
                id: ULID(timestamp: ReplayTests.date(atStep: transactionStep + offset + 1)),
                txn: txn,
                ops: ["updateTask"],
                at: DateTime(date),
                actor: ReplayTests.actor,
                files: fileCount,
                patch: try ReplayTests.titlePatch(setting: transactionTitle, of: task)
            )
        }
    }

    /// Writes the line of each of some events to the log file of its node.
    ///
    /// - Parameters:
    ///   - events: The events.
    ///   - log: The event log of the board.
    static func write(_ events: some Sequence<Event>, to log: EventLog) throws {
        for event in events {
            try log.append(contentsOf: [event], toLogOf: event.patch.node)
        }
    }

    /// Gives the title of a task in a graph.
    ///
    /// - Parameters:
    ///   - task: The local ref of the task.
    ///   - graph: The graph.
    /// - Returns: The title.
    static func title(of task: LocalRef, in graph: Graph) throws -> String {
        try LiveGraphApplyTests.task(task, in: graph).title
    }

    /// Checks that a graph holds the title of the transaction on each of some tasks.
    ///
    /// - Parameters:
    ///   - tasks: The local refs of the tasks.
    ///   - graph: The graph.
    static func expectTransactionTitle(on tasks: [LocalRef], in graph: Graph) throws {
        for task in tasks {
            #expect(try title(of: task, in: graph) == transactionTitle)
        }
    }

    /// Checks that a graph holds the fixture title of each of some tasks, and not the title of the transaction.
    ///
    /// - Parameters:
    ///   - tasks: The local refs of the tasks.
    ///   - graph: The graph.
    static func expectFixtureTitle(on tasks: [LocalRef], in graph: Graph) throws {
        for task in tasks {
            #expect(try title(of: task, in: graph) == task.description)
        }
    }

    // MARK: - Load

    @Test("At load, a transaction with one file cut off is not applied, and its events wait")
    func loadHoldsCutOffTransaction() async throws {
        let fixture = try Self.makeFixture(fileCount: Self.transactionFileCount)
        try Self.write(fixture.events.prefix(1), to: fixture.log)
        let loaded = try await BoardLoader(reading: fixture.log).load()
        try Self.expectFixtureTitle(on: fixture.tasks, in: loaded.graph)
        #expect(!loaded.events.contains(fixture.events[0]))
        #expect(loaded.heldEvents == [fixture.events[0]])
    }

    @Test("At load, a complete transaction is applied")
    func loadAppliesCompleteTransaction() async throws {
        let fixture = try Self.makeFixture(fileCount: Self.transactionFileCount)
        try Self.write(fixture.events, to: fixture.log)
        let loaded = try await BoardLoader(reading: fixture.log).load()
        try Self.expectTransactionTitle(on: fixture.tasks, in: loaded.graph)
        #expect(Set(fixture.events).isSubset(of: loaded.events))
        #expect(loaded.heldEvents.isEmpty)
    }

    @Test("At load, an old line with no file count is applied")
    func loadAppliesOldLine() async throws {
        let fixture = try Self.makeFixture(fileCount: nil)
        try Self.write(fixture.events.prefix(1), to: fixture.log)
        let loaded = try await BoardLoader(reading: fixture.log).load()
        try Self.expectTransactionTitle(on: [fixture.tasks[0]], in: loaded.graph)
        #expect(loaded.events.contains(fixture.events[0]))
        #expect(loaded.heldEvents.isEmpty)
    }

    @Test("At load, a node that only a cut-off transaction makes is not in the graph")
    func loadHoldsNodeOfCutOffTransaction() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        _ = try LiveGraphApplyTests.writeBoard(to: log)
        let newTasks = [LocalRef.task(ULID()), LocalRef.task(ULID())]
        let events = try Self.transactionEvents(settingTitleOf: newTasks, fileCount: newTasks.count)
        try Self.write(events.prefix(1), to: log)
        let loaded = try await BoardLoader(reading: log).load()
        #expect(loaded.graph.slot(for: newTasks[0]).flatMap(loaded.graph.node(at:)) == nil)
        #expect(loaded.heldEvents == [events[0]])
    }

    // MARK: - Reload

    @Test("LiveGraph.reload does not apply a transaction with one file cut off")
    func reloadHoldsCutOffTransaction() async throws {
        let fixture = try Self.makeFixture(fileCount: Self.transactionFileCount)
        var live = try await LiveGraphApplyTests.load(fixture.log)
        try Self.write(fixture.events.prefix(1), to: fixture.log)
        let newIDs = try await live.apply(changedPaths: [fixture.log.fileURL(for: fixture.tasks[0])])
        #expect(newIDs.isEmpty)
        try Self.expectFixtureTitle(on: fixture.tasks, in: live.graph)
        #expect(live.heldEvents == [fixture.events[0]])
        try await LiveGraphApplyTests.expectEqualToFreshLoad(live, of: fixture.log)
    }

    @Test("LiveGraph.reload applies a cut-off transaction on all its nodes when the missing file arrives")
    func reloadAppliesTransactionWhenMissingFileArrives() async throws {
        let fixture = try Self.makeFixture(fileCount: Self.transactionFileCount)
        var live = try await LiveGraphApplyTests.load(fixture.log)
        try Self.write(fixture.events.prefix(1), to: fixture.log)
        _ = try await live.apply(changedPaths: [fixture.log.fileURL(for: fixture.tasks[0])])
        try Self.write(fixture.events.suffix(1), to: fixture.log)
        let newIDs = try await live.apply(changedPaths: [fixture.log.fileURL(for: fixture.tasks[1])])
        #expect(newIDs == fixture.events.map(\.id))
        try Self.expectTransactionTitle(on: fixture.tasks, in: live.graph)
        #expect(live.heldEvents.isEmpty)
        try await LiveGraphApplyTests.expectEqualToFreshLoad(live, of: fixture.log)
    }

    @Test("LiveGraph.reload applies a complete transaction")
    func reloadAppliesCompleteTransaction() async throws {
        let fixture = try Self.makeFixture(fileCount: Self.transactionFileCount)
        var live = try await LiveGraphApplyTests.load(fixture.log)
        try Self.write(fixture.events, to: fixture.log)
        let newIDs = try await live.apply(changedPaths: fixture.tasks.map(fixture.log.fileURL(for:)))
        #expect(newIDs == fixture.events.map(\.id))
        try Self.expectTransactionTitle(on: fixture.tasks, in: live.graph)
        try await LiveGraphApplyTests.expectEqualToFreshLoad(live, of: fixture.log)
    }

    @Test("LiveGraph.reload applies an old line with no file count")
    func reloadAppliesOldLine() async throws {
        let fixture = try Self.makeFixture(fileCount: nil)
        var live = try await LiveGraphApplyTests.load(fixture.log)
        try Self.write(fixture.events.prefix(1), to: fixture.log)
        let newIDs = try await live.apply(changedPaths: [fixture.log.fileURL(for: fixture.tasks[0])])
        #expect(newIDs == [fixture.events[0].id])
        try Self.expectTransactionTitle(on: [fixture.tasks[0]], in: live.graph)
        try await LiveGraphApplyTests.expectEqualToFreshLoad(live, of: fixture.log)
    }

    @Test("LiveGraph.reload holds a transaction again on all its nodes when one of its files is removed")
    func reloadHoldsTransactionWhenFileIsRemoved() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let task = try #require(try LiveGraphApplyTests.writeBoard(to: log).first)
        let newTask = LocalRef.task(ULID())
        let events = try Self.transactionEvents(settingTitleOf: [task, newTask], fileCount: Self.transactionFileCount)
        try Self.write(events, to: log)
        var live = try await LiveGraphApplyTests.load(log)
        try Self.expectTransactionTitle(on: [task, newTask], in: live.graph)
        try FileManager.default.removeItem(at: log.fileURL(for: newTask))
        _ = try await live.apply(changedPaths: [log.fileURL(for: newTask)])
        try Self.expectFixtureTitle(on: [task], in: live.graph)
        #expect(live.heldEvents == [events[0]])
        try await LiveGraphApplyTests.expectEqualToFreshLoad(live, of: log)
    }
}
