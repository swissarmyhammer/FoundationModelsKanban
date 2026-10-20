import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the read side of the crash safety of a transaction on many files (divergence.md Q23, S5): the load and
/// `LiveGraph.reload` do not apply a transaction that is not complete in all the files that its lines name, apply a
/// complete transaction, check an old line with a file count by the count, and apply an old line with no file field.
/// A transaction that is not complete applies when its missing file arrives later.
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

    /// The count of the fixture tasks that the stray-line test uses: the two tasks of the transaction, and one task
    /// that the list of the transaction does not name.
    static let strayTestTaskCount = transactionFileCount + 1

    // MARK: - Files values

    /// The `files` value of each line of a transaction on some tasks.
    typealias FilesRecord = ([LocalRef]) -> TransactionFiles?

    /// The `files` value of a current line: the sorted refs of the log files of the tasks.
    ///
    /// - Parameter tasks: The local refs of the tasks.
    /// - Returns: The list of refs.
    static func namedFiles(of tasks: [LocalRef]) -> TransactionFiles? {
        .named(tasks)
    }

    /// The `files` value of an old line with a file count: the count of the tasks.
    ///
    /// - Parameter tasks: The local refs of the tasks.
    /// - Returns: The count.
    static func fileCount(of tasks: [LocalRef]) -> TransactionFiles? {
        .count(tasks.count)
    }

    /// The `files` value of an old line with no file field.
    ///
    /// - Parameter tasks: The local refs of the tasks. The value does not use them.
    /// - Returns: `nil`.
    static func noFiles(of tasks: [LocalRef]) -> TransactionFiles? {
        nil
    }

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
    /// - Parameter files: The `files` value of each event of the transaction, made from the two tasks. The default
    ///   is the list of the refs of the two tasks.
    /// - Returns: The fixture.
    static func makeFixture(recording files: FilesRecord = namedFiles(of:)) throws -> Fixture {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let tasks = Array(try LiveGraphApplyTests.writeBoard(to: log).prefix(transactionFileCount))
        let events = try transactionEvents(settingTitleOf: tasks, recording: files(tasks))
        return Fixture(directory: directory, log: log, tasks: tasks, events: events)
    }

    /// Makes the events of one transaction that sets ``transactionTitle`` on each of some tasks.
    ///
    /// - Parameters:
    ///   - tasks: The local refs of the tasks.
    ///   - files: The `files` value of each event, or `nil` for an old line with no file field.
    /// - Returns: The events, one for each task, in the order of the tasks. Their ids increase.
    static func transactionEvents(
        settingTitleOf tasks: [LocalRef],
        recording files: TransactionFiles?
    ) throws -> [Event] {
        let date = ReplayTests.date(atStep: transactionStep)
        let txn = ULID(timestamp: date)
        return try tasks.enumerated().map { offset, task in
            Event(
                id: ULID(timestamp: ReplayTests.date(atStep: transactionStep + offset + 1)),
                txn: txn,
                ops: ["updateTask"],
                at: DateTime(date),
                actor: ReplayTests.actor,
                files: files,
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

    @Test("At load, a transaction with one named file cut off is not applied, and its events wait")
    func loadHoldsCutOffTransaction() async throws {
        let fixture = try Self.makeFixture()
        try Self.write(fixture.events.prefix(1), to: fixture.log)
        let loaded = try await BoardLoader(reading: fixture.log).load()
        try Self.expectFixtureTitle(on: fixture.tasks, in: loaded.graph)
        #expect(!loaded.events.contains(fixture.events[0]))
        #expect(loaded.heldEvents == [fixture.events[0]])
    }

    @Test("The hold of a transaction with one named file cut off names the missing ref in the warning")
    func holdWarningNamesMissingRef() throws {
        let fixture = try Self.makeFixture()
        let incomplete = IncompleteTransactions(among: fixture.events.prefix(1))
        #expect(incomplete.missingFiles == [fixture.events[0].txn: [fixture.tasks[1]]])
        #expect(incomplete.holdDetail.contains(fixture.tasks[1].description), "\(incomplete.holdDetail)")
        #expect(!incomplete.holdDetail.contains(fixture.tasks[0].description), "\(incomplete.holdDetail)")
    }

    /// A board fixture and the lines of one transaction on two named tasks: the line of the first named task, and a
    /// stray line of the same transaction in the file of a third task that the list does not name.
    struct StrayFixture {
        /// The temporary folder. The value keeps it, so that the folder stays until the test ends.
        let directory: TemporaryDirectory

        /// The event log of the board.
        let log: EventLog

        /// The three tasks: the two named tasks, and the task of the stray line.
        let tasks: [LocalRef]

        /// The named task whose line is missing.
        let missing: LocalRef

        /// The two lines: the line of the first named task, and the stray line. No file holds them yet.
        let events: [Event]
    }

    /// Writes the board fixture, and makes the lines of ``StrayFixture``.
    ///
    /// - Returns: The fixture.
    static func makeStrayFixture() throws -> StrayFixture {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let tasks = Array(try LiveGraphApplyTests.writeBoard(to: log).prefix(strayTestTaskCount))
        let named = Array(tasks.prefix(transactionFileCount))
        let events = try transactionEvents(settingTitleOf: tasks, recording: .named(named))
        return StrayFixture(
            directory: directory,
            log: log,
            tasks: tasks,
            missing: named[1],
            events: [events[0], events[transactionFileCount]]
        )
    }

    @Test("At load, a line in an unnamed file does not complete a transaction with a named file missing")
    func loadHoldsTransactionWithStrayFile() async throws {
        let fixture = try Self.makeStrayFixture()
        try Self.write(fixture.events, to: fixture.log)
        let loaded = try await BoardLoader(reading: fixture.log).load()
        try Self.expectFixtureTitle(on: fixture.tasks, in: loaded.graph)
        #expect(loaded.heldEvents == fixture.events)
        let incomplete = IncompleteTransactions(among: fixture.events)
        #expect(incomplete.missingFiles == [fixture.events[0].txn: [fixture.missing]])
    }

    @Test("At load, a complete transaction is applied")
    func loadAppliesCompleteTransaction() async throws {
        let fixture = try Self.makeFixture()
        try Self.write(fixture.events, to: fixture.log)
        let loaded = try await BoardLoader(reading: fixture.log).load()
        try Self.expectTransactionTitle(on: fixture.tasks, in: loaded.graph)
        #expect(Set(fixture.events).isSubset(of: loaded.events))
        #expect(loaded.heldEvents.isEmpty)
    }

    @Test("At load, an old transaction with a file count and one file cut off is held by the count")
    func loadHoldsCutOffOldCountTransaction() async throws {
        let fixture = try Self.makeFixture(recording: Self.fileCount(of:))
        try Self.write(fixture.events.prefix(1), to: fixture.log)
        let loaded = try await BoardLoader(reading: fixture.log).load()
        try Self.expectFixtureTitle(on: fixture.tasks, in: loaded.graph)
        #expect(loaded.heldEvents == [fixture.events[0]])
    }

    @Test("At load, an old transaction with a file count in all its files is applied")
    func loadAppliesCompleteOldCountTransaction() async throws {
        let fixture = try Self.makeFixture(recording: Self.fileCount(of:))
        try Self.write(fixture.events, to: fixture.log)
        let loaded = try await BoardLoader(reading: fixture.log).load()
        try Self.expectTransactionTitle(on: fixture.tasks, in: loaded.graph)
        #expect(loaded.heldEvents.isEmpty)
    }

    @Test("At load, an old line with no file field is applied")
    func loadAppliesOldLine() async throws {
        let fixture = try Self.makeFixture(recording: Self.noFiles(of:))
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
        let events = try Self.transactionEvents(settingTitleOf: newTasks, recording: .named(newTasks))
        try Self.write(events.prefix(1), to: log)
        let loaded = try await BoardLoader(reading: log).load()
        #expect(loaded.graph.slot(for: newTasks[0]).flatMap(loaded.graph.node(at:)) == nil)
        #expect(loaded.heldEvents == [events[0]])
    }

    // MARK: - Reload

    @Test("LiveGraph.reload does not apply a transaction with one named file cut off")
    func reloadHoldsCutOffTransaction() async throws {
        let fixture = try Self.makeFixture()
        var live = try await LiveGraphApplyTests.load(fixture.log)
        try Self.write(fixture.events.prefix(1), to: fixture.log)
        let newIDs = try await live.apply(changedPaths: [fixture.log.fileURL(for: fixture.tasks[0])])
        #expect(newIDs.isEmpty)
        try Self.expectFixtureTitle(on: fixture.tasks, in: live.graph)
        #expect(live.heldEvents == [fixture.events[0]])
        try await LiveGraphApplyTests.expectEqualToFreshLoad(live, of: fixture.log)
    }

    @Test("LiveGraph.reload does not apply a transaction with a line in an unnamed file and a named file missing")
    func reloadHoldsTransactionWithStrayFile() async throws {
        let fixture = try Self.makeStrayFixture()
        var live = try await LiveGraphApplyTests.load(fixture.log)
        try Self.write(fixture.events, to: fixture.log)
        let newIDs = try await live.apply(changedPaths: fixture.events.map { event in
            fixture.log.fileURL(for: event.patch.node)
        })
        #expect(newIDs.isEmpty)
        try Self.expectFixtureTitle(on: fixture.tasks, in: live.graph)
        #expect(live.heldEvents == fixture.events)
        try await LiveGraphApplyTests.expectEqualToFreshLoad(live, of: fixture.log)
    }

    @Test("LiveGraph.reload applies a cut-off transaction on all its nodes when the missing file arrives")
    func reloadAppliesTransactionWhenMissingFileArrives() async throws {
        let fixture = try Self.makeFixture()
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
        let fixture = try Self.makeFixture()
        var live = try await LiveGraphApplyTests.load(fixture.log)
        try Self.write(fixture.events, to: fixture.log)
        let newIDs = try await live.apply(changedPaths: fixture.tasks.map(fixture.log.fileURL(for:)))
        #expect(newIDs == fixture.events.map(\.id))
        try Self.expectTransactionTitle(on: fixture.tasks, in: live.graph)
        try await LiveGraphApplyTests.expectEqualToFreshLoad(live, of: fixture.log)
    }

    @Test("LiveGraph.reload holds an old transaction with a file count and one file cut off")
    func reloadHoldsCutOffOldCountTransaction() async throws {
        let fixture = try Self.makeFixture(recording: Self.fileCount(of:))
        var live = try await LiveGraphApplyTests.load(fixture.log)
        try Self.write(fixture.events.prefix(1), to: fixture.log)
        let newIDs = try await live.apply(changedPaths: [fixture.log.fileURL(for: fixture.tasks[0])])
        #expect(newIDs.isEmpty)
        #expect(live.heldEvents == [fixture.events[0]])
        try await LiveGraphApplyTests.expectEqualToFreshLoad(live, of: fixture.log)
    }

    @Test("LiveGraph.reload applies an old line with no file field")
    func reloadAppliesOldLine() async throws {
        let fixture = try Self.makeFixture(recording: Self.noFiles(of:))
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
        let events = try Self.transactionEvents(settingTitleOf: [task, newTask], recording: .named([task, newTask]))
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
