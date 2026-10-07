import Foundation
import Synchronization
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the parallel loader: the stages, the work queue, the join, and the global event list (plan.md §5.3, §12
/// item 23).
@Suite("Parallel loader of one board")
struct LoaderTests {
    /// The worker count of the serial load.
    static let singleWorker = 1

    /// The worker count of the parallel load.
    static let manyWorkers = 8

    /// The number of tasks of the board fixture.
    static let fixtureTaskCount = 40

    /// The number of task files of the peak test.
    static let peakTaskCount = 2000

    /// The largest worker count of the peak test. The test uses fewer workers on a computer with fewer processors,
    /// because the workers can run at the same time only on different processors.
    static let peakWorkerLimit = 4

    /// The key of the different board of the cross-board `dependsOn` edge.
    static let remoteBoardKey = "github.com/o/other"

    /// The ref of the `done` column.
    static let doneColumn = LocalRef.column(slug: "done")

    /// The ref of the `old` tag, which is renamed to the `bug` tag.
    static let oldTag = LocalRef.tag(slug: "old")

    /// The refs of the board, the actor, the columns, and the tags of the fixture, in the order of their files.
    static let namedRefs: [LocalRef] = [
        .board, ReplayTests.actor, ReplayTests.todoColumn, doneColumn, ReplayTests.bugTag, oldTag,
    ]

    // MARK: - Fixture

    /// Appends one patch to the log of its node, and gives the event.
    ///
    /// - Parameters:
    ///   - patch: The patch.
    ///   - step: The step of the event. A larger step gives a later time and a later event id.
    ///   - log: The event log of the board.
    /// - Returns: The event that the log holds.
    @discardableResult
    static func append(_ patch: PatchInput, atStep step: Int, to log: EventLog) throws -> Event {
        let event = try Event(parsing: ReplayTests.line(atStep: step, patch: patch))
        try log.append(contentsOf: [event], toLogOf: patch.node)
        return event
    }

    /// Gives the cross-board ref to a task of a different board.
    ///
    /// - Returns: The remote ref.
    static func remoteTask() -> StoredRef {
        .remote(NodeURI(boardKey: remoteBoardKey, ref: .task(ULID())))
    }

    /// Writes the board, the actor, the columns, and the tags of the fixture. The `old` tag is renamed to the `bug`
    /// tag.
    ///
    /// - Parameter log: The event log of the board.
    static func writeNamedNodes(to log: EventLog) throws {
        for (step, ref) in namedRefs.enumerated() {
            try append(PatchInput(node: ref, set: ["name": .json(.string(ref.description))]), atStep: step, to: log)
        }
        let rename = try PatchInput(node: oldTag, set: ["renamedTo": .ref(.local(ReplayTests.bugTag))])
        try append(rename, atStep: namedRefs.count, to: log)
    }

    /// Writes a task that has each kind of edge: a column, an assignee, two tags, a `dependsOn` edge to a task of
    /// the board, and a `dependsOn` edge to a task of a different board.
    ///
    /// - Parameters:
    ///   - task: The ref of the task.
    ///   - dependency: The ref of the task in the board that the task waits for.
    ///   - step: The step of the event.
    ///   - log: The event log of the board.
    static func writeTask(
        _ task: LocalRef,
        dependingOn dependency: LocalRef,
        atStep step: Int,
        to log: EventLog
    ) throws {
        let patch = try PatchInput(
            node: task,
            set: ["title": .json(.string(task.description)), "column": .ref(.local(ReplayTests.todoColumn))],
            add: [
                "assignees": [.local(ReplayTests.actor)],
                "tags": [.local(oldTag), .local(ReplayTests.bugTag)],
                "dependsOn": [.local(dependency), remoteTask()],
            ]
        )
        try append(patch, atStep: step, to: log)
    }

    /// Writes the full board fixture: the named nodes, the tasks, and one comment on the first task. Each task waits
    /// for the task before it, and the first task waits for the last task.
    ///
    /// - Parameter log: The event log of the board.
    /// - Returns: The ref of each node of the fixture.
    static func writeBoard(to log: EventLog) throws -> [LocalRef] {
        try writeNamedNodes(to: log)
        let tasks = (0..<fixtureTaskCount).map { _ in LocalRef.task(ULID()) }
        let firstStep = namedRefs.count + 1
        for (index, task) in tasks.enumerated() {
            let dependency = tasks[(index + tasks.count - 1) % tasks.count]
            try writeTask(task, dependingOn: dependency, atStep: firstStep + index, to: log)
        }
        let comment = LocalRef.comment(ULID())
        let commentPatch = try PatchInput(
            node: comment,
            set: ["task": .ref(.local(tasks[0])), "author": .ref(.local(ReplayTests.actor))]
        )
        try append(commentPatch, atStep: firstStep + tasks.count, to: log)
        return namedRefs + tasks + [comment]
    }

    /// Loads a board.
    ///
    /// - Parameters:
    ///   - log: The event log of the board.
    ///   - workerCount: The number of workers.
    /// - Returns: The loaded board.
    static func load(_ log: EventLog, withWorkers workerCount: Int) async throws -> LoadedBoard {
        try await BoardLoader(reading: log, withWorkers: workerCount).load()
    }

    /// Gives the node of a ref in a graph.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the node.
    ///   - graph: The graph.
    /// - Returns: The node.
    static func node(of ref: LocalRef, in graph: Graph) throws -> Node {
        let slot = try #require(graph.slot(for: ref))
        return try #require(graph.node(at: slot))
    }

    /// Tells if an edge holds a local ref that the join did not change to a slot.
    ///
    /// - Parameter edge: The edge.
    /// - Returns: `true` for an unresolved local edge.
    static func isUnresolvedLocal(_ edge: EdgeTarget) -> Bool {
        guard case .unresolved(.local) = edge else {
            return false
        }
        return true
    }

    // MARK: - Tests

    @Test("A load with 1 worker and a load with 8 workers give equal graphs and equal global event lists")
    func workerCountDoesNotChangeResult() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        _ = try Self.writeBoard(to: log)
        let serial = try await Self.load(log, withWorkers: Self.singleWorker)
        let parallel = try await Self.load(log, withWorkers: Self.manyWorkers)
        #expect(serial.graph == parallel.graph)
        #expect(serial.events == parallel.events)
    }

    @Test("After the load, each edge to a node in the board is a slot")
    func eachLocalEdgeIsSlot() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let refs = try Self.writeBoard(to: log)
        let graph = try await Self.load(log, withWorkers: Self.manyWorkers).graph
        for ref in refs {
            let edges = try Self.node(of: ref, in: graph).edges
            #expect(!edges.contains(where: Self.isUnresolvedLocal), "\(ref)")
        }
    }

    @Test("The join changes each ref to the slot of its target, also a target in the same stage")
    func joinGivesTargetSlots() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let refs = try Self.writeBoard(to: log)
        let graph = try await Self.load(log, withWorkers: Self.manyWorkers).graph
        let bugSlot = try #require(graph.slot(for: ReplayTests.bugTag))
        let oldTag = try #require(try Self.node(of: Self.oldTag, in: graph).state as? TagNode)
        #expect(oldTag.renamedTo == .slot(bugSlot))
        let commentRef = try #require(refs.last)
        let comment = try #require(try Self.node(of: commentRef, in: graph).state as? CommentNode)
        let tasks = refs.dropFirst(Self.namedRefs.count).dropLast()
        let firstTask = try #require(tasks.first)
        let lastTask = try #require(tasks.last)
        let firstSlot = try #require(graph.slot(for: firstTask))
        let lastSlot = try #require(graph.slot(for: lastTask))
        #expect(comment.task == .slot(firstSlot))
        let task = try #require(graph.node(at: firstSlot)?.state as? TaskNode)
        #expect(task.dependsOn.first == .slot(lastSlot))
    }

    @Test("A cross-board dependsOn edge stays unresolved")
    func crossBoardEdgeStaysUnresolved() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let task = LocalRef.task(ULID())
        let remote = Self.remoteTask()
        try Self.append(PatchInput(node: task, add: ["dependsOn": [remote]]), atStep: 1, to: log)
        let graph = try await Self.load(log, withWorkers: Self.manyWorkers).graph
        let node = try #require(try Self.node(of: task, in: graph).state as? TaskNode)
        #expect(node.dependsOn == [.unresolved(remote)])
    }

    @Test("A dependsOn edge to a task with no file stays unresolved")
    func missingTargetStaysUnresolved() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let task = LocalRef.task(ULID())
        let missing = StoredRef.local(.task(ULID()))
        try Self.append(PatchInput(node: task, add: ["dependsOn": [missing]]), atStep: 1, to: log)
        let graph = try await Self.load(log, withWorkers: Self.manyWorkers).graph
        let node = try #require(try Self.node(of: task, in: graph).state as? TaskNode)
        #expect(node.dependsOn == [.unresolved(missing)])
    }

    @Test("The global event list holds each event of each file, in the order of the event ids")
    func globalEventsAreMergedById() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let refs = try Self.writeBoard(to: log)
        let expected = try refs.flatMap { ref in try log.readLog(of: ref).events }.sorted { $0.id < $1.id }
        let events = try await Self.load(log, withWorkers: Self.manyWorkers).events
        #expect(events == expected)
    }

    @Test("A missing node directory is an empty stage")
    func missingDirectoryIsEmptyStage() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        try Self.append(PatchInput(node: .board, set: ["name": .json(.string("board"))]), atStep: 1, to: log)
        let loaded = try await Self.load(log, withWorkers: Self.manyWorkers)
        #expect(try Self.node(of: .board, in: loaded.graph).ref == .board)
        #expect(loaded.events == (try log.readLog(of: .board)).events)
    }

    @Test("A board with no directory loads as an empty graph")
    func missingBoardIsEmpty() async throws {
        let directory = try TemporaryDirectory()
        let loaded = try await Self.load(EventLog(repositoryAt: directory.url), withWorkers: Self.manyWorkers)
        #expect(loaded.graph == Graph())
        #expect(loaded.events.isEmpty)
    }

    @Test("With 2000 task files and N workers, the peak number of workers that run at the same time is N")
    func peakWorkersEqualsWorkerCount() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        for step in 0..<Self.peakTaskCount {
            let task = LocalRef.task(ULID())
            try Self.append(PatchInput(node: task, set: ["title": .json(.string("task"))]), atStep: step, to: log)
        }
        let workerCount = min(Self.peakWorkerLimit, ProcessInfo.processInfo.activeProcessorCount)
        let meter = WorkerMeter()
        _ = try await BoardLoader(reading: log, withWorkers: workerCount, reportingTo: meter).load()
        #expect(meter.peak == workerCount)
    }
}

// MARK: - Worker meter

/// Counts the workers of the loader that run at the same time, and records the peak.
final class WorkerMeter: LoaderWorkerObserver {
    /// The worker counts.
    private struct Counts {
        /// The number of workers that run now.
        var running = 0

        /// The largest number of workers that ran at the same time.
        var peak = 0
    }

    /// The counts, behind a lock, because the workers run on different threads.
    private let counts = Mutex(Counts())

    /// The largest number of workers that ran at the same time.
    var peak: Int {
        counts.withLock { counts in counts.peak }
    }

    /// Adds one running worker, and records the peak.
    func workerDidStart() {
        counts.withLock { counts in
            counts.running += 1
            counts.peak = max(counts.peak, counts.running)
        }
    }

    /// Removes one running worker.
    func workerDidFinish() {
        counts.withLock { counts in counts.running -= 1 }
    }
}
