import CoreServices
import Foundation
import Synchronization
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the file watcher of the live graph: the FSEvents stream, the batches through the serial gate, the filter of
/// the file signatures, and `close()` (plan.md §5.6, §12 item 25).
///
/// FSEvents gives a batch some milliseconds after a write. Each test waits for a definite signal: a batch that the
/// engine applies, or a batch of a second watcher. The time limit only stops a test that would wait forever. A test
/// that expects no batch does not wait for one: it reads the watch state of the engine directly (the active watch,
/// and if its watcher runs), because the time of an FSEvents batch has no upper limit.
@Suite("Live graph: FSEvents watcher and batches", .timeLimit(.minutes(1)))
struct BoardWatcherTests {
    /// The arguments of a `searchTasks` query for a word of ``KanbanGraphTests/laterTitle``, with no filter. The
    /// column of the fixture is the terminal column, so its tasks are done, and the search also finds them.
    static let laterTitleSearch = TaskSearchTests.query(TaskSearchTests.titleWord)

    // MARK: - Fixture

    /// Waits for the first batch that satisfies a condition.
    ///
    /// - Parameters:
    ///   - batches: The batches, for example of a ``BatchRecorder`` or of a ``BoardWatcher``.
    ///   - condition: Tells if a batch is the batch that the test waits for. The condition can run a query.
    /// - Returns: `true` when a batch satisfies the condition, `false` when the batches end or the time limit ends
    ///   first.
    static func hasBatch(
        in batches: AsyncStream<[URL]>,
        satisfying condition: @escaping @Sendable ([URL]) async throws -> Bool
    ) async throws -> Bool {
        let isFound = try await StreamWait.value {
            for await batch in batches {
                if try await condition(batch) {
                    return true
                }
            }
            return false
        }
        return isFound ?? false
    }

    /// Waits until a query on an engine gives an expected response. The query runs again after each batch that the
    /// engine applies.
    ///
    /// - Parameters:
    ///   - query: The GraphQL document.
    ///   - expected: The expected response.
    ///   - graph: The engine.
    ///   - recorder: The batch recorder of the engine.
    /// - Returns: `true` when the query gives the expected response before the time limit ends.
    static func query(
        _ query: String,
        reaches expected: String,
        on graph: KanbanGraph,
        recordedBy recorder: BatchRecorder
    ) async throws -> Bool {
        try await hasBatch(in: recorder.batches) { _ in
            try await KanbanGraphTests.execute(query, on: graph) == expected
        }
    }

    /// Tells if a batch holds a file. The compare resolves symbolic links, because FSEvents gives `/private/var/…`
    /// for a file in `/var/…`.
    ///
    /// - Parameters:
    ///   - batch: The changed paths.
    ///   - file: The file.
    /// - Returns: `true` when a path of the batch is the file.
    static func batch(_ batch: [URL], holds file: URL) -> Bool {
        let path = file.resolvingSymlinksInPath().path
        return batch.contains { changed in changed.resolvingSymlinksInPath().path == path }
    }

    /// Writes a new title to the fixture task.
    ///
    /// - Parameters:
    ///   - task: The ULID of the task.
    ///   - ids: The ULID source of the event ids.
    ///   - log: The event log of the board.
    static func writeLaterTitle(to task: ULID, mintingFrom ids: inout FixedULIDSource, in log: EventLog) throws {
        let patch = try ReplayTests.titlePatch(setting: KanbanGraphTests.laterTitle, of: .task(task))
        try KanbanGraphTests.append(patch, mintingFrom: &ids, to: log)
    }

    // MARK: - Tests

    @Test("With no subscriber, a manual edit of a task log changes the result of a later query")
    func manualEditChangesLaterQuery() async throws {
        let directory = try TemporaryDirectory()
        var (task, ids) = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let recorder = BatchRecorder()
        let graph = try KanbanGraphTests.makeGraph(at: directory.url, observingBatchesWith: recorder)
        let before = try await KanbanGraphTests.execute(KanbanGraphTests.boardQuery, on: graph)
        #expect(before == KanbanGraphTests.boardResponse(withTask: task, titled: KanbanGraphTests.taskTitle))
        try Self.writeLaterTitle(to: task, mintingFrom: &ids, in: EventLog(repositoryAt: directory.url))
        let expected = KanbanGraphTests.boardResponse(withTask: task, titled: KanbanGraphTests.laterTitle)
        #expect(try await Self.query(KanbanGraphTests.boardQuery, reaches: expected, on: graph, recordedBy: recorder))
        await graph.close()
    }

    @Test("After a batch, the search of the board finds the text of a manual edit")
    func batchUpdatesSearch() async throws {
        let directory = try TemporaryDirectory()
        var (task, ids) = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let recorder = BatchRecorder()
        let graph = try KanbanGraphTests.makeGraph(at: directory.url, observingBatchesWith: recorder)
        #expect(try await TaskSearchTests.hits(searchingWith: Self.laterTitleSearch, on: graph).isEmpty)
        try Self.writeLaterTitle(to: task, mintingFrom: &ids, in: EventLog(repositoryAt: directory.url))
        let id = NodeURI(boardKey: KanbanGraphTests.boardKey.description, ref: .task(task)).description
        let isFound = try await Self.hasBatch(in: recorder.batches) { _ in
            try await TaskSearchTests.hits(searchingWith: Self.laterTitleSearch, on: graph).map(\.task.id) == [id]
        }
        #expect(isFound)
        await graph.close()
    }

    @Test("The tool's own write makes no apply call")
    func ownWriteMakesNoApply() async throws {
        let directory = try TemporaryDirectory()
        var (task, ids) = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let log = EventLog(repositoryAt: directory.url)
        let recorder = BatchRecorder()
        let graph = try KanbanGraphTests.makeGraph(at: directory.url, observingBatchesWith: recorder)
        let update = AddUpdateTaskTests.mutation(of: UndoTests.titleField(KanbanGraphTests.laterTitle, of: task))
        _ = try await KanbanGraphTests.execute(update, on: graph)
        let marker = try KanbanGraphTests.writeTask(titled: KanbanGraphTests.taskTitle, mintingFrom: &ids, to: log)
        let markerFile = log.fileURL(for: .task(marker))
        #expect(try await Self.hasBatch(in: recorder.batches) { batch in Self.batch(batch, holds: markerFile) })
        let applied = recorder.appliedBatches
        #expect(!applied.isEmpty)
        #expect(applied.allSatisfy { batch in batch == [markerFile] })
        await graph.close()
    }

    @Test("A .kanban/ directory that appears after the first call is loaded and watched")
    func appearingBoardIsLoadedAndWatched() async throws {
        let directory = try TemporaryDirectory()
        let root = try KanbanGraphTests.makeEmptyRepo(in: directory)
        let recorder = BatchRecorder()
        let graph = try KanbanGraphTests.makeGraph(at: root, observingBatchesWith: recorder)
        let emptyName = #"{"data":{"board":{"name":"\#(KanbanGraphTests.emptyRepoName)"}}}"#
        #expect(try await KanbanGraphTests.execute(KanbanGraphTests.nameQuery, on: graph) == emptyName)
        let rootWatch = try #require(await graph.activeWatch)
        #expect(rootWatch.directory == root)
        var (task, ids) = try KanbanGraphTests.writeFixture(inRepoAt: root)
        let loaded = KanbanGraphTests.boardResponse(withTask: task, titled: KanbanGraphTests.taskTitle)
        #expect(try await Self.query(KanbanGraphTests.boardQuery, reaches: loaded, on: graph, recordedBy: recorder))
        let log = EventLog(repositoryAt: root)
        #expect(await graph.activeWatch?.directory == log.directory)
        #expect(await !rootWatch.watcher.isRunning)
        try Self.writeLaterTitle(to: task, mintingFrom: &ids, in: log)
        let edited = KanbanGraphTests.boardResponse(withTask: task, titled: KanbanGraphTests.laterTitle)
        #expect(try await Self.query(KanbanGraphTests.boardQuery, reaches: edited, on: graph, recordedBy: recorder))
        await graph.close()
    }

    @Test("After close(), a file change makes no apply call")
    func closeStopsWatcher() async throws {
        let directory = try TemporaryDirectory()
        var (_, ids) = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let log = EventLog(repositoryAt: directory.url)
        let recorder = BatchRecorder()
        let graph = try KanbanGraphTests.makeGraph(at: directory.url, observingBatchesWith: recorder)
        let name = try await KanbanGraphTests.execute(KanbanGraphTests.nameQuery, on: graph)
        #expect(name == KanbanGraphTests.nameResponse)
        let watch = try #require(await graph.activeWatch)
        #expect(await watch.watcher.isRunning)
        await graph.close()
        try #require(await !watch.watcher.isRunning)
        #expect(watch.consumer.isCancelled)
        #expect(await graph.activeWatch == nil)
        let probe = try BoardWatcher(watching: log.directory)
        let task = try KanbanGraphTests.writeTask(titled: KanbanGraphTests.laterTitle, mintingFrom: &ids, to: log)
        let taskFile = log.fileURL(for: .task(task))
        #expect(try await Self.hasBatch(in: probe.batches) { batch in Self.batch(batch, holds: taskFile) })
        await probe.stop()
        #expect(recorder.appliedBatches.isEmpty)
    }

    @Test("A group of events with a flag for lost events gives a batch that also holds the watched directory")
    func lostEventsGiveWatchedDirectory() async throws {
        let directory = try TemporaryDirectory()
        let log = EventLog(repositoryAt: directory.url)
        let file = log.fileURL(for: .task(ULID()))
        let (batches, continuation) = AsyncStream<[URL]>.makeStream()
        let sink = BatchSink(watching: log.directory, feeding: continuation)
        sink.receive(paths: [file.path], flags: [FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)])
        sink.finish()
        var iterator = batches.makeAsyncIterator()
        let batch = try #require(await iterator.next())
        #expect(batch.map(\.path) == [file.path, log.directory.path])
    }

    @Test("A batch that holds the board directory reads each changed file, also a file that the batch does not name")
    func boardDirectoryBatchReadsEachChangedFile() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try CommitTests.writeBoard(in: directory)
        var session = try await CommitTests.makeSession(of: log)
        let task = try #require(tasks.first)
        try LiveGraphApplyTests.writeTitle(to: task, atStep: LiveGraphApplyTests.laterStep, in: log)
        let applied = try await session.apply(watchedPaths: [log.directory])
        #expect(applied == [log.fileURL(for: task)])
        #expect(try CommitTests.title(of: task, in: session) == LiveGraphApplyTests.changedTitle)
    }
}

// MARK: - Batch recorder

/// Records each batch that a ``KanbanGraph`` applies to its live graph, and gives each batch in a stream, so that a
/// test can wait for it.
final class BatchRecorder: LiveGraphObserver {
    /// The batches, in the order that the engine applied them.
    let batches: AsyncStream<[URL]>

    /// The continuation of ``batches``.
    private let continuation: AsyncStream<[URL]>.Continuation

    /// The recorded batches, behind a lock, because the engine can call from a different thread.
    private let recorded = Mutex<[[URL]]>([])

    /// Makes a recorder with no batches.
    init() {
        (batches, continuation) = AsyncStream.makeStream()
    }

    /// The files of each applied batch, in the order that the engine applied them.
    var appliedBatches: [[URL]] {
        recorded.withLock { batches in batches }
    }

    /// Records a batch.
    ///
    /// - Parameter paths: The files that the apply read.
    func didApply(changedPaths paths: [URL]) {
        recorded.withLock { batches in batches.append(paths) }
        continuation.yield(paths)
    }
}
