import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the apply of changed log files to a live graph (plan.md §5.6: apply a batch, large changes, a line that does
/// not parse). Each test changes the files on disk directly, calls `apply`, and compares the live graph with a fresh
/// load of the same files.
@Suite("Apply changed files to a live graph")
struct LiveGraphApplyTests {
    /// The first step of the events that a test writes after the load. It is after each step of the board fixture.
    static let laterStep = 1_000

    /// The text of a line that is not JSON: a manual edit with a typing error.
    static let brokenLine = "{\"id\": not json\n"

    /// The title that a test writes after the load.
    static let changedTitle = "changed after the load"

    // MARK: - Fixture

    /// Writes the changed title to a task.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the task.
    ///   - step: The step of the event.
    ///   - log: The event log of the board.
    /// - Returns: The event of the title.
    @discardableResult
    static func writeTitle(to ref: LocalRef, atStep step: Int, in log: EventLog) throws -> Event {
        try LoaderTests.append(ReplayTests.titlePatch(setting: changedTitle, of: ref), atStep: step, to: log)
    }

    /// Writes the board fixture of the loader tests, and gives the refs of its tasks.
    ///
    /// - Parameter log: The event log of the board.
    /// - Returns: The refs of the tasks of the fixture.
    static func writeBoard(to log: EventLog) throws -> [LocalRef] {
        try LoaderTests.writeBoard(to: log).filter { ref in ref.nodeType == .task }
    }

    /// Loads the live graph of a board.
    ///
    /// - Parameter log: The event log of the board.
    /// - Returns: The live graph.
    static func load(_ log: EventLog) async throws -> LiveGraph {
        try await LiveGraph.load(using: BoardLoader(reading: log))
    }

    /// Gives the nodes of a graph in a form that does not depend on the slots: each node by its ref, with each
    /// resolved edge changed to the rank of the ref of its target in the sort order of the refs. An unresolved edge
    /// does not change.
    ///
    /// - Parameter graph: The graph.
    /// - Returns: The nodes, by local ref.
    static func canonicalNodes(of graph: Graph) -> [LocalRef: Node] {
        let placed = graph.allSlots.compactMap { slot in graph.node(at: slot).map { node in (slot: slot, node: node) } }
        let ranked = placed.sorted { lhs, rhs in lhs.node.ref.description < rhs.node.ref.description }
        let rankBySlot = Dictionary(uniqueKeysWithValues: ranked.enumerated().map { rank, entry in (entry.slot, rank) })
        return Dictionary(
            uniqueKeysWithValues: placed.map { _, node in
                var canonical = node
                canonical.updateEdges { edge in
                    edge.resolvedSlot.flatMap { slot in rankBySlot[slot] }.map(EdgeTarget.slot) ?? edge
                }
                return (node.ref, canonical)
            }
        )
    }

    /// Checks that a live graph equals a fresh load of the files of its board: the nodes and their edges, the global
    /// event list, and the file signatures.
    ///
    /// - Parameters:
    ///   - live: The live graph after the apply.
    ///   - log: The event log of the board.
    static func expectEqualToFreshLoad(_ live: LiveGraph, of log: EventLog) async throws {
        let fresh = try await BoardLoader(reading: log).load()
        #expect(canonicalNodes(of: live.graph) == canonicalNodes(of: fresh.graph))
        #expect(live.events == fresh.events)
        #expect(live.signatures == (try log.nodeFileSignatures()))
    }

    /// Gives the state of a task in a graph.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the task.
    ///   - graph: The graph.
    /// - Returns: The state of the task.
    static func task(_ ref: LocalRef, in graph: Graph) throws -> TaskNode {
        try #require(try LoaderTests.node(of: ref, in: graph).state as? TaskNode)
    }

    // MARK: - Tests

    @Test("A changed file is folded again, and the graph equals a fresh load")
    func changedFileEqualsFreshLoad() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let task = try #require(try Self.writeBoard(to: log).first)
        var live = try await Self.load(log)
        let event = try Self.writeTitle(to: task, atStep: Self.laterStep, in: log)
        let newIDs = try await live.apply(changedPaths: [log.fileURL(for: task)])
        #expect(newIDs == [event.id])
        #expect(try Self.task(task, in: live.graph).title == Self.changedTitle)
        try await Self.expectEqualToFreshLoad(live, of: log)
    }

    @Test("A new file gets a slot, and an edge that pointed to it resolves")
    func newFileResolvesWaitingEdge() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        _ = try Self.writeBoard(to: log)
        let waiter = LocalRef.task(ULID())
        let target = LocalRef.task(ULID())
        try LoaderTests.writeTask(waiter, dependingOn: target, atStep: Self.laterStep, to: log)
        var live = try await Self.load(log)
        #expect(try Self.task(waiter, in: live.graph).dependsOn.first == ReplayTests.edge(to: target))
        let event = try Self.writeTitle(to: target, atStep: Self.laterStep + 1, in: log)
        let newIDs = try await live.apply(changedPaths: [log.fileURL(for: target)])
        #expect(newIDs == [event.id])
        let targetSlot = try #require(live.graph.slot(for: target))
        #expect(try Self.task(waiter, in: live.graph).dependsOn.first == .slot(targetSlot))
        try await Self.expectEqualToFreshLoad(live, of: log)
    }

    @Test("A removed file removes its node, and an edge to it becomes unresolved")
    func removedFileUnresolvesEdge() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        _ = try Self.writeBoard(to: log)
        let waiter = LocalRef.task(ULID())
        let target = LocalRef.task(ULID())
        try LoaderTests.writeTask(waiter, dependingOn: target, atStep: Self.laterStep, to: log)
        try Self.writeTitle(to: target, atStep: Self.laterStep + 1, in: log)
        var live = try await Self.load(log)
        try FileManager.default.removeItem(at: log.fileURL(for: target))
        let newIDs = try await live.apply(changedPaths: [log.fileURL(for: target)])
        #expect(newIDs.isEmpty)
        let targetSlot = try #require(live.graph.slot(for: target))
        #expect(live.graph.node(at: targetSlot) == nil)
        #expect(try Self.task(waiter, in: live.graph).dependsOn.first == ReplayTests.edge(to: target))
        try await Self.expectEqualToFreshLoad(live, of: log)
    }

    @Test("A change to more than half of the files loads the board again, and the graph equals a fresh load")
    func manyChangedFilesEqualFreshLoad() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let tasks = try Self.writeBoard(to: log)
        var live = try await Self.load(log)
        let events = try tasks.enumerated().map { offset, task in
            try Self.writeTitle(to: task, atStep: Self.laterStep + offset, in: log)
        }
        let newIDs = try await live.apply(changedPaths: tasks.map(log.fileURL(for:)))
        #expect(newIDs == events.map(\.id).sorted())
        try await Self.expectEqualToFreshLoad(live, of: log)
    }

    @Test("A full reload also reads a changed file that the batch does not name")
    func fullReloadReadsEachFile() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let tasks = try Self.writeBoard(to: log)
        var live = try await Self.load(log)
        let unnamed = try #require(tasks.last)
        let named = tasks.dropLast()
        for (offset, task) in tasks.enumerated() {
            try Self.writeTitle(to: task, atStep: Self.laterStep + offset, in: log)
        }
        _ = try await live.apply(changedPaths: named.map(log.fileURL(for:)))
        #expect(try Self.task(unnamed, in: live.graph).title == Self.changedTitle)
        try await Self.expectEqualToFreshLoad(live, of: log)
    }

    @Test("A line that does not parse is skipped, and the other lines of the file still apply")
    func brokenLineIsSkipped() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let task = try #require(try Self.writeBoard(to: log).first)
        var live = try await Self.load(log)
        let handle = try FileHandle(forWritingTo: log.fileURL(for: task))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(Self.brokenLine.utf8))
        try handle.close()
        let event = try Self.writeTitle(to: task, atStep: Self.laterStep, in: log)
        let newIDs = try await live.apply(changedPaths: [log.fileURL(for: task)])
        #expect(newIDs == [event.id])
        #expect(try Self.task(task, in: live.graph).title == Self.changedTitle)
        try await Self.expectEqualToFreshLoad(live, of: log)
    }

    @Test("A path that is not a node log of the board changes nothing")
    func otherPathChangesNothing() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        _ = try Self.writeBoard(to: log)
        var live = try await Self.load(log)
        let before = Self.canonicalNodes(of: live.graph)
        let paths = [log.lockFileURL, directory.url.appending(path: "tasks/\(ULID().ulidString).jsonl")]
        let newIDs = try await live.apply(changedPaths: paths)
        #expect(newIDs.isEmpty)
        #expect(Self.canonicalNodes(of: live.graph) == before)
    }
}
