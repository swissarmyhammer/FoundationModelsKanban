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
/// engine applies, or a batch of a second watcher. The wait ends when the signal comes, or it fails at the time limit
/// of ``FolderEventWait``. A test that expects no batch does not wait for one: it reads the watch state of the engine
/// directly (the active watch, and if its watcher runs), because no wait can show that a batch does not come.
@Suite("Live graph: FSEvents watcher and batches", .watcherBudget)
struct BoardWatcherTests {
    /// The arguments of a `searchTasks` query for a word of ``KanbanGraphTests/laterTitle``, with no filter. The
    /// column of the fixture is the terminal column, so its tasks are done, and the search also finds them.
    static let laterTitleSearch = TaskSearchTests.query(TaskSearchTests.titleWord)

    /// The number of changes that the merge test reads from `history`. It is more than the number of changes of the
    /// task, so that an unexpected change also shows in the compare.
    static let mergeHistoryPageSize = 10

    /// The selection of the task query of the merge test: the title and the column name.
    static let titleAndColumnSelection = "{ title column { name } }"

    /// The name of the folder in the repo, outside `.kanban/`, that holds a moved node directory for a short time.
    static let movedFolderName = "moved"

    /// The step of the title that the single file test writes to a second task: the step after
    /// ``LiveGraphApplyTests/laterStep``, so that the two events have different ids.
    static let secondTitleStep = LiveGraphApplyTests.laterStep + 1

    // MARK: - Fixture

    /// Waits for the first batch that satisfies a condition. The wait has the time limit of ``FolderEventWait``.
    ///
    /// - Parameters:
    ///   - batches: The batches, for example of a ``BatchRecorder`` or of a ``BoardWatcher``.
    ///   - change: The change that the test waits for. The failure message at the time limit names it.
    ///   - path: The file or folder of the change. The failure message at the time limit names it.
    ///   - condition: Tells if a batch is the batch that the test waits for. The condition can run a query.
    /// - Returns: `true` when a batch satisfies the condition, `false` when the batches end first.
    /// - Throws: ``FolderEventTimeout`` when no batch satisfies the condition before the time limit, or an error that
    ///   the condition throws.
    static func hasBatch(
        in batches: AsyncStream<[URL]>,
        waitingFor change: String,
        at path: URL,
        satisfying condition: @escaping @Sendable ([URL]) async throws -> Bool
    ) async throws -> Bool {
        try await FolderEventWait.value(waitingFor: change, at: path.path) {
            try await batches.contains { batch in try await condition(batch) }
        }
    }

    /// Waits for the first batch that holds a file. The wait has the time limit of ``FolderEventWait``.
    ///
    /// - Parameters:
    ///   - batches: The batches, for example of a ``BatchRecorder`` or of a ``BoardWatcher``.
    ///   - file: The file that the test changed.
    /// - Returns: `true` when a batch holds the file, `false` when the batches end first.
    /// - Throws: ``FolderEventTimeout`` when no batch holds the file before the time limit.
    static func hasBatch(in batches: AsyncStream<[URL]>, holding file: URL) async throws -> Bool {
        try await hasBatch(in: batches, waitingFor: "a batch that holds the changed file", at: file) { batch in
            Self.batch(batch, holds: file)
        }
    }

    /// Waits until a query on an engine gives an expected response. The query runs again after each batch that the
    /// engine applies. The wait has the time limit of ``FolderEventWait``.
    ///
    /// - Parameters:
    ///   - query: The GraphQL document.
    ///   - expected: The expected response.
    ///   - graph: The engine.
    ///   - recorder: The batch recorder of the engine.
    ///   - path: The file or folder that the test changed. The failure message at the time limit names it.
    /// - Returns: `true` when the query gives the expected response, `false` when the batches end first.
    /// - Throws: ``FolderEventTimeout`` when the query does not give the expected response before the time limit.
    static func query(
        _ query: String,
        reaches expected: String,
        on graph: KanbanGraph,
        recordedBy recorder: BatchRecorder,
        afterChangeAt path: URL
    ) async throws -> Bool {
        let change = "a batch after which the query \(query) gives \(expected)"
        return try await hasBatch(in: recorder.batches, waitingFor: change, at: path) { _ in
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

    /// Replaces the directory of a node log with a changed copy, the same as a tool that moves a whole directory:
    /// moves the directory out of `.kanban/`, writes the change to the moved copy, and moves the copy back in. The
    /// file watcher of the board then can report the directory only, and no file of it.
    ///
    /// - Parameters:
    ///   - node: A node whose log is in the directory. The directory of its log file is the replaced directory.
    ///   - log: The event log of the board.
    ///   - write: Writes the change. It gets the event log of the moved copy, which is outside the `.kanban/`
    ///     directory of the board.
    static func replaceLogDirectory(
        holding node: LocalRef,
        in log: EventLog,
        writing write: (EventLog) throws -> Void
    ) throws {
        let repository = log.directory.deletingLastPathComponent()
        let movedLog = EventLog(repositoryAt: repository.appending(path: movedFolderName, directoryHint: .isDirectory))
        let directory = log.fileURL(for: node).deletingLastPathComponent()
        let moved = movedLog.fileURL(for: node).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: movedLog.directory, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: directory, to: moved)
        try write(movedLog)
        try FileManager.default.moveItem(at: moved, to: directory)
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
        let log = EventLog(repositoryAt: directory.url)
        try Self.writeLaterTitle(to: task, mintingFrom: &ids, in: log)
        let expected = KanbanGraphTests.boardResponse(withTask: task, titled: KanbanGraphTests.laterTitle)
        let file = log.fileURL(for: .task(task))
        let query = KanbanGraphTests.boardQuery
        #expect(try await Self.query(query, reaches: expected, on: graph, recordedBy: recorder, afterChangeAt: file))
        await graph.close()
    }

    @Test("After a batch, the search of the board finds the text of a manual edit")
    func batchUpdatesSearch() async throws {
        let directory = try TemporaryDirectory()
        var (task, ids) = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let recorder = BatchRecorder()
        let graph = try KanbanGraphTests.makeGraph(at: directory.url, observingBatchesWith: recorder)
        #expect(try await TaskSearchTests.hits(searchingWith: Self.laterTitleSearch, on: graph).isEmpty)
        let log = EventLog(repositoryAt: directory.url)
        try Self.writeLaterTitle(to: task, mintingFrom: &ids, in: log)
        let id = NodeURI(boardKey: KanbanGraphTests.boardKey.description, ref: .task(task)).description
        let change = "a batch after which the search finds the task"
        let file = log.fileURL(for: .task(task))
        let isFound = try await Self.hasBatch(in: recorder.batches, waitingFor: change, at: file) { _ in
            try await TaskSearchTests.hits(searchingWith: Self.laterTitleSearch, on: graph).map(\.task.id) == [id]
        }
        #expect(isFound)
        await graph.close()
    }

    @Test("A union merge that adds lines to a task log updates the task, and history gets their transactions")
    func mergedLinesUpdateTaskAndHistory() async throws {
        let directory = try TemporaryDirectory()
        _ = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let recorder = BatchRecorder()
        let graph = try KanbanGraphTests.makeGraph(at: directory.url, observingBatchesWith: recorder)
        _ = try await CommentTests.run(AddUpdateTaskTests.doneColumn, on: graph)
        let id = try await CrossRepoFixture.addTask(with: "", on: graph)
        let task = try AddUpdateTaskTests.firstTask(in: id)
        let addTxn = try await SubscriptionTests.latestTxn(on: graph)
        let log = EventLog(repositoryAt: directory.url)
        var ids = GitGraphFixture.secondEngineIDs
        let titleTxn = SubscriptionTests.nextTxn(of: ids)
        try Self.writeLaterTitle(to: task, mintingFrom: &ids, in: log)
        let doneTxn = SubscriptionTests.nextTxn(of: ids)
        try SubscriptionTests.writeDoneMove(of: id, mintingFrom: &ids, in: log)
        let done = try #require(DefaultColumn.all.last).name
        let mergedTask = #"{"column":{"name":"\#(done)"},"title":"\#(KanbanGraphTests.laterTitle)"}"#
        let merged = #"{"data":{"board":{"task":\#(mergedTask)}}}"#
        let query = CommentTests.taskQuery(of: task, selecting: Self.titleAndColumnSelection)
        let file = log.fileURL(for: .task(task))
        #expect(try await Self.query(query, reaches: merged, on: graph, recordedBy: recorder, afterChangeAt: file))
        let expected = [(addTxn, UpdateKind.created), (titleTxn, .updated), (doneTxn, .updated)].map { txn, kind in
            let update = ChangeFilterTests.UpdateRow(type: NodeType.task.rawValue, kind: kind.rawValue, id: id)
            return ChangeFilterTests.ChangeRow(txn: txn, updates: [update])
        }
        let filter = AddUpdateTaskTests.sigilRef(of: task)
        let count = Self.mergeHistoryPageSize
        #expect(try await ChangeFilterTests.history(filteredBy: filter, count: count, on: graph) == expected)
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
        #expect(try await Self.hasBatch(in: recorder.batches, holding: markerFile))
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
        let log = EventLog(repositoryAt: root)
        let query = KanbanGraphTests.boardQuery
        let board = log.directory
        #expect(try await Self.query(query, reaches: loaded, on: graph, recordedBy: recorder, afterChangeAt: board))
        #expect(await graph.activeWatch?.directory == log.directory)
        #expect(await !rootWatch.watcher.isRunning)
        try Self.writeLaterTitle(to: task, mintingFrom: &ids, in: log)
        let edited = KanbanGraphTests.boardResponse(withTask: task, titled: KanbanGraphTests.laterTitle)
        let file = log.fileURL(for: .task(task))
        #expect(try await Self.query(query, reaches: edited, on: graph, recordedBy: recorder, afterChangeAt: file))
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
        let probe = try await BoardWatcher(watching: log.directory, in: FolderStreams())
        let task = try KanbanGraphTests.writeTask(titled: KanbanGraphTests.laterTitle, mintingFrom: &ids, to: log)
        let taskFile = log.fileURL(for: .task(task))
        #expect(try await Self.hasBatch(in: probe.batches, holding: taskFile))
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
        let router = EventRouter()
        router.insert(sink, at: log.directory.path)
        router.startWaitingSinks(after: FolderStreamsTests.beforeAllEvents)
        let flags = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        router.route([FolderEvent(path: file.path, flags: flags, id: FolderStreamsTests.firstEventID)])
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

    @Test("A batch that holds a node directory of the board, for example .kanban/tasks/, reads each changed file")
    func nodeDirectoryBatchReadsEachChangedFile() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try CommitTests.writeBoard(in: directory)
        var session = try await CommitTests.makeSession(of: log)
        let task = try #require(tasks.first)
        let taskFile = log.fileURL(for: task)
        try Self.replaceLogDirectory(holding: task, in: log) { moved in
            try LiveGraphApplyTests.writeTitle(to: task, atStep: LiveGraphApplyTests.laterStep, in: moved)
        }
        let applied = try await session.apply(watchedPaths: [taskFile.deletingLastPathComponent()])
        #expect(applied == [taskFile])
        #expect(try CommitTests.title(of: task, in: session) == LiveGraphApplyTests.changedTitle)
    }

    @Test("A batch that holds one node file reads only that file, also when a different file changed")
    func fileBatchReadsOnlyThatFile() async throws {
        let directory = try TemporaryDirectory()
        let (log, tasks) = try CommitTests.writeBoard(in: directory)
        var session = try await CommitTests.makeSession(of: log)
        let task = try #require(tasks.first)
        let other = try #require(tasks.last)
        try #require(task != other)
        let otherTitle = try CommitTests.title(of: other, in: session)
        try LiveGraphApplyTests.writeTitle(to: task, atStep: LiveGraphApplyTests.laterStep, in: log)
        try LiveGraphApplyTests.writeTitle(to: other, atStep: Self.secondTitleStep, in: log)
        let applied = try await session.apply(watchedPaths: [log.fileURL(for: task)])
        #expect(applied == [log.fileURL(for: task)])
        #expect(try CommitTests.title(of: task, in: session) == LiveGraphApplyTests.changedTitle)
        #expect(try CommitTests.title(of: other, in: session) == otherTitle)
    }

    @Test("When .kanban/tasks/ is moved away and a changed copy is moved back in, a later query shows the change")
    func movedTaskDirectoryChangesLaterQuery() async throws {
        let directory = try TemporaryDirectory()
        var (task, ids) = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
        let recorder = BatchRecorder()
        let graph = try KanbanGraphTests.makeGraph(at: directory.url, observingBatchesWith: recorder)
        let before = try await KanbanGraphTests.execute(KanbanGraphTests.boardQuery, on: graph)
        #expect(before == KanbanGraphTests.boardResponse(withTask: task, titled: KanbanGraphTests.taskTitle))
        let log = EventLog(repositoryAt: directory.url)
        try Self.replaceLogDirectory(holding: .task(task), in: log) { moved in
            try Self.writeLaterTitle(to: task, mintingFrom: &ids, in: moved)
        }
        let expected = KanbanGraphTests.boardResponse(withTask: task, titled: KanbanGraphTests.laterTitle)
        let folder = log.fileURL(for: .task(task)).deletingLastPathComponent()
        let query = KanbanGraphTests.boardQuery
        #expect(try await Self.query(query, reaches: expected, on: graph, recordedBy: recorder, afterChangeAt: folder))
        await graph.close()
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
