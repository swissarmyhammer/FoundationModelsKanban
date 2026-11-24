import Foundation
import Testing
import ULID

@testable import FoundationModelsKanban

/// Tests the change stream of the board of a folder that opens no session: ``KanbanHost/boardChanges(inFolder:)``
/// (TestudoApp D214).
///
/// Each test writes the fixture board of ``KanbanGraphTests`` to a temporary folder, and starts the stream on a host
/// of its own. A change comes from a session view with its own host (a second engine on the same folder), or from a
/// direct write to the log files. A wait for a change that FSEvents gives has the time limit of ``FolderEventWait``.
/// A test that needs no FSEvents event uses ``QuietFolderEvents``, so that it is deterministic. No test opens a session
/// on the host of the stream, so each test also proves that the stream works for a folder with no open session.
@Suite("Board folder changes: the change stream of a board with no session", .watcherBudget)
struct BoardFolderChangesTests {
    /// The title of the task that the second engine adds.
    static let addedTitle = "Add the stream"

    /// The body of the comment that the second engine adds.
    static let commentBody = "Looks good."

    /// The new name of the column that the second engine renames.
    static let renamedColumn = "Backlog"

    /// The name of the file of a conflict version of a task log. It is outside `.kanban/`, the same as the version
    /// store of iCloud Drive.
    static let conflictVersionName = "conflict.jsonl"

    // MARK: - Fixture

    /// The temporary folder of the test. It holds the fixture board.
    let directory: TemporaryDirectory

    /// The ULID of the task of the fixture board.
    let task: ULID

    /// The ULID source after the fixture, for more direct writes.
    var ids: FixedULIDSource

    /// Writes the fixture board to a new temporary folder.
    init() throws {
        directory = try TemporaryDirectory()
        (task, ids) = try KanbanGraphTests.writeFixture(inRepoAt: directory.url)
    }

    /// The event log of the fixture board.
    var log: EventLog {
        EventLog(repositoryAt: directory.url)
    }

    /// The ULID text of the task of the fixture board.
    var taskID: String {
        task.ulidString
    }

    /// Waits for the first change of a stream that matches a condition. The wait has the time limit of
    /// ``FolderEventWait``.
    ///
    /// - Parameters:
    ///   - changes: The stream of changes.
    ///   - change: The change that the test waits for. The failure message at the time limit names it.
    ///   - path: The file or folder that the test changed. The failure message at the time limit names it.
    ///   - isMatch: Tells if a change is the change that the test waits for.
    /// - Returns: The first change that matches, or `nil` when the stream ends first.
    static func firstChange(
        of changes: AsyncStream<BoardFolderChange>,
        waitingFor change: String,
        at path: URL,
        where isMatch: @escaping @Sendable (BoardFolderChange) -> Bool
    ) async throws -> BoardFolderChange? {
        try await FolderEventWait.value(waitingFor: change, at: path.path) {
            await changes.first(where: isMatch)
        }
    }

    /// Waits for the first change of a stream that is a ``BoardFolderChange/Kind/tasksChanged(_:)`` with a task id.
    ///
    /// - Parameters:
    ///   - changes: The stream of changes.
    ///   - id: The ULID text of the task.
    ///   - path: The file or folder that the test changed.
    /// - Returns: `true` when the change came, and `false` when the stream ended first.
    static func waitsForChange(
        of changes: AsyncStream<BoardFolderChange>,
        ofTask id: String,
        at path: URL
    ) async throws -> Bool {
        let found = try await firstChange(of: changes, waitingFor: "a change of task \(id)", at: path) { change in
            guard case .tasksChanged(let ids) = change.kind else {
                return false
            }
            return ids.contains(id)
        }
        return found != nil
    }

    /// Waits for the first change of a stream that is a ``BoardFolderChange/Kind/tasksRemoved(_:)`` with a task id.
    ///
    /// - Parameters:
    ///   - changes: The stream of changes.
    ///   - id: The ULID text of the task.
    ///   - path: The file or folder that the test changed.
    /// - Returns: `true` when the change came, and `false` when the stream ended first.
    static func waitsForRemoval(
        of changes: AsyncStream<BoardFolderChange>,
        ofTask id: String,
        at path: URL
    ) async throws -> Bool {
        let found = try await firstChange(of: changes, waitingFor: "the removal of task \(id)", at: path) { change in
            guard case .tasksRemoved(let ids) = change.kind else {
                return false
            }
            return ids.contains(id)
        }
        return found != nil
    }

    /// Waits for the first change of a stream with one kind.
    ///
    /// - Parameters:
    ///   - kind: The kind of the change.
    ///   - changes: The stream of changes.
    ///   - path: The file or folder that the test changed.
    /// - Returns: The change, or `nil` when the stream ended first.
    static func firstChange(
        ofKind kind: BoardFolderChange.Kind,
        in changes: AsyncStream<BoardFolderChange>,
        at path: URL
    ) async throws -> BoardFolderChange? {
        try await firstChange(of: changes, waitingFor: "\(kind)", at: path) { change in
            change.kind == kind
        }
    }

    /// Waits for the first change of a stream with one kind.
    ///
    /// - Parameters:
    ///   - kind: The kind of the change.
    ///   - changes: The stream of changes.
    ///   - path: The file or folder that the test changed.
    /// - Returns: `true` when the change came, and `false` when the stream ended first.
    static func waits(
        for kind: BoardFolderChange.Kind,
        in changes: AsyncStream<BoardFolderChange>,
        at path: URL
    ) async throws -> Bool {
        try await firstChange(ofKind: kind, in: changes, at: path) != nil
    }

    /// Gives the ULID text of a task from its full URI.
    ///
    /// - Parameter uri: The full URI of the task, as a mutation gives it.
    /// - Returns: The ULID text.
    /// - Throws: An error when the text is not the URI of a node with a local id.
    static func taskID(ofURI uri: String) throws -> String {
        try #require(try NodeURI(parsing: uri).ref.localID)
    }

    // MARK: - Writes of other processes

    @Test("A task that a second engine on the same folder adds shows in the stream of the first reader")
    func secondEngineTaskShows() async throws {
        let host = HostFixture.makeHost()
        let changes = try await host.boardChanges(inFolder: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let added = try Self.taskID(ofURI: try await CrossRepoFixture.addTask(with: "", on: graph))
        #expect(try await Self.waitsForChange(of: changes, ofTask: added, at: log.directory))
        await graph.close()
        await host.close()
    }

    @Test("A delete of a task file gives the id of the task in tasksRemoved")
    func removedTaskFileGivesID() async throws {
        let host = HostFixture.makeHost()
        let changes = try await host.boardChanges(inFolder: directory.url)
        let file = log.fileURL(for: .task(task))
        try FileManager.default.removeItem(at: file)
        #expect(try await Self.waits(for: .tasksRemoved([taskID]), in: changes, at: file))
        await host.close()
    }

    @Test("A line that a different writer appends to a task file gives the id of the task in tasksChanged")
    mutating func appendedLineGivesID() async throws {
        let host = HostFixture.makeHost()
        let changes = try await host.boardChanges(inFolder: directory.url)
        try BoardWatcherTests.writeLaterTitle(to: task, mintingFrom: &ids, in: log)
        #expect(try await Self.waits(for: .tasksChanged([taskID]), in: changes, at: log.fileURL(for: .task(task))))
        await host.close()
    }

    @Test("A lock file alone gives no change: the first change after the lock is the next task write")
    mutating func lockFileGivesNoChange() async throws {
        let host = HostFixture.makeHost()
        let changes = try await host.boardChanges(inFolder: directory.url)
        let lock = try await log.lock()
        lock.unlock()
        try BoardWatcherTests.writeLaterTitle(to: task, mintingFrom: &ids, in: log)
        let file = log.fileURL(for: .task(task))
        let first = try await Self.firstChange(of: changes, waitingFor: "the title write", at: file) { _ in true }
        #expect(first?.kind == .tasksChanged([taskID]))
        await host.close()
    }

    @Test("The stamp of a change is the stamp of the board right after the change")
    mutating func changeHoldsStamp() async throws {
        let host = HostFixture.makeHost()
        let changes = try await host.boardChanges(inFolder: directory.url)
        try BoardWatcherTests.writeLaterTitle(to: task, mintingFrom: &ids, in: log)
        let file = log.fileURL(for: .task(task))
        let change = try #require(try await Self.firstChange(ofKind: .tasksChanged([taskID]), in: changes, at: file))
        #expect(change.stamp == host.boardStamp(ofFolder: directory.url))
        await host.close()
    }

    @Test("A change holds the folder that the caller gave")
    mutating func changeHoldsFolder() async throws {
        let host = HostFixture.makeHost()
        let changes = try await host.boardChanges(inFolder: directory.url)
        try BoardWatcherTests.writeLaterTitle(to: task, mintingFrom: &ids, in: log)
        let file = log.fileURL(for: .task(task))
        let change = try #require(try await Self.firstChange(ofKind: .tasksChanged([taskID]), in: changes, at: file))
        #expect(change.folder == directory.url)
        await host.close()
    }

    @Test("The boardRemoved change has no stamp")
    func boardRemovedHasNoStamp() async throws {
        let host = HostFixture.makeHost()
        let changes = try await host.boardChanges(inFolder: directory.url)
        try FileManager.default.removeItem(at: log.directory)
        let change = try #require(try await Self.firstChange(ofKind: .boardRemoved, in: changes, at: log.directory))
        #expect(change.stamp == nil)
        await host.close()
    }

    // MARK: - Mutations of a session

    @Test("A deleteTask mutation gives the id of the task in tasksRemoved")
    func deleteTaskGivesRemoval() async throws {
        let host = HostFixture.makeHost()
        let changes = try await host.boardChanges(inFolder: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        _ = try await CommentTests.run(TaskOperationTests.taskField(MutationName.deleteTask, of: task), on: graph)
        #expect(try await Self.waitsForRemoval(of: changes, ofTask: taskID, at: log.fileURL(for: .task(task))))
        await graph.close()
        await host.close()
    }

    @Test("An addComment mutation gives the id of the task of the comment in tasksChanged")
    func addCommentGivesTaskID() async throws {
        let host = HostFixture.makeHost()
        let changes = try await host.boardChanges(inFolder: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let taskURI = ColumnActorTests.id(of: .task(task))
        let field = #"addComment(input: { task: "\#(taskURI)", body: "\#(Self.commentBody)" }) { id }"#
        _ = try await CommentTests.run(field, on: graph)
        #expect(try await Self.waitsForChange(of: changes, ofTask: taskID, at: log.directory))
        await graph.close()
        await host.close()
    }

    @Test("A rename of a column gives boardChanged")
    func columnRenameGivesBoardChanged() async throws {
        let host = HostFixture.makeHost()
        let changes = try await host.boardChanges(inFolder: directory.url)
        let graph = try KanbanGraphTests.makeGraph(at: directory.url)
        let slug = try #require(KanbanGraphTests.todoColumn.localID)
        let field = #"updateColumn(input: { id: "\#(slug)", name: "\#(Self.renamedColumn)" }) { name }"#
        _ = try await CommentTests.run(field, on: graph)
        #expect(try await Self.waits(for: .boardChanged, in: changes, at: log.fileURL(for: KanbanGraphTests.todoColumn)))
        await graph.close()
        await host.close()
    }

    // MARK: - The board directory

    @Test("A remove of .kanban gives boardRemoved")
    func removedBoardGivesBoardRemoved() async throws {
        let host = HostFixture.makeHost()
        let changes = try await host.boardChanges(inFolder: directory.url)
        try FileManager.default.removeItem(at: log.directory)
        #expect(try await Self.waits(for: .boardRemoved, in: changes, at: log.directory))
        await host.close()
    }

    @Test("A new .kanban after a remove gives tasksChanged with each task id")
    func newBoardGivesEachTaskID() async throws {
        let host = HostFixture.makeHost()
        let changes = try await host.boardChanges(inFolder: directory.url)
        try FileManager.default.removeItem(at: log.directory)
        #expect(try await Self.waits(for: .boardRemoved, in: changes, at: log.directory))
        let rewritten = try KanbanGraphTests.writeFixture(inRepoAt: directory.url).task
        #expect(try await Self.waitsForChange(of: changes, ofTask: rewritten.ulidString, at: log.directory))
        await host.close()
    }

    // MARK: - iCloud conflict versions

    /// Writes a conflict version of the log of the task of the fixture board, as iCloud Drive makes it when two Macs
    /// write the same log: the version holds the current lines of the log and one more title line. The log itself
    /// keeps its current version.
    ///
    /// - Returns: The file of the conflict version, and the ids of the events of both versions, in file order.
    /// - Throws: An error when a file cannot be read or written.
    mutating func writeConflictVersion() throws -> (version: URL, eventIDs: [ULID]) {
        let file = log.fileURL(for: .task(task))
        let current = try Data(contentsOf: file)
        try BoardWatcherTests.writeLaterTitle(to: task, mintingFrom: &ids, in: log)
        let eventIDs = try log.readLog(of: .task(task)).events.map(\.id)
        let version = directory.url.appending(path: Self.conflictVersionName, directoryHint: .notDirectory)
        try FileManager.default.moveItem(at: file, to: version)
        try current.write(to: file)
        return (version, eventIDs)
    }

    /// Writes a conflict version of the task log, starts the stream on a host whose version store gives that version,
    /// and waits for the change of the task. The host uses ``QuietFolderEvents``, so the only batch is the first
    /// compare of each file after the start, and the test is deterministic.
    ///
    /// - Returns: The run of the merge. The caller closes its host.
    /// - Throws: An error when a file cannot be written, when the stream cannot start, or when no change of the task
    ///   comes.
    mutating func runMerge() async throws -> MergeRun {
        let (version, eventIDs) = try writeConflictVersion()
        let file = log.fileURL(for: .task(task))
        let source = FakeFileVersionSource(conflicts: [file.canonicalPath: [version]])
        let host = HostFixture.makeHost(watchingWith: QuietFolderEvents(), readingVersionsWith: source)
        let changes = try await host.boardChanges(inFolder: directory.url)
        let id = taskID
        let wait = "the merge of task \(id)"
        let change = try await Self.firstChange(of: changes, waitingFor: wait, at: file) { change in
            guard case .tasksChanged(let ids) = change.kind else {
                return false
            }
            return ids.contains(id)
        }
        return MergeRun(host: host, change: change, source: source, file: file, eventIDs: eventIDs)
    }

    @Test("A conflict version of a task log gives the id of the task in tasksChanged")
    mutating func conflictVersionGivesTaskID() async throws {
        let run = try await runMerge()
        #expect(run.change != nil)
        await run.host.close()
    }

    @Test("After the change of a merge, the task log holds the events of both versions")
    mutating func mergedLogHoldsBothVersions() async throws {
        let run = try await runMerge()
        #expect(try log.readLog(of: .task(task)).events.map(\.id) == run.eventIDs)
        await run.host.close()
    }

    @Test("After the change of a merge, the conflict versions of the task log are resolved")
    mutating func mergeResolvesVersions() async throws {
        let run = try await runMerge()
        #expect(run.source.resolvedPaths == [run.file.canonicalPath])
        await run.host.close()
    }

    @Test("The stamp of the change of a merge is the stamp of the board after the merge")
    mutating func mergeChangeHoldsStampAfterMerge() async throws {
        let run = try await runMerge()
        #expect(run.change?.stamp == run.host.boardStamp(ofFolder: directory.url))
        await run.host.close()
    }

    @Test("After the change of a merge, a read of the board shows the title of the conflict version")
    mutating func mergedBoardShowsConflictTitle() async throws {
        let run = try await runMerge()
        let snapshot = try #require(try await run.host.readBoard(inFolder: directory.url).snapshot)
        let merged = snapshot.tasks.first { snapshotTask in snapshotTask.id == taskID }
        #expect(merged?.title == KanbanGraphTests.laterTitle)
        await run.host.close()
    }

    @Test("A board with no conflict version gets no lock file from the stream")
    mutating func noConflictMakesNoLock() async throws {
        let source = FakeFileVersionSource(conflicts: [:])
        let host = HostFixture.makeHost(watchingWith: QuietFolderEvents(), readingVersionsWith: source)
        let feed = try #require(try await host.startBoardFolderFeed(inFolder: directory.url))
        try BoardWatcherTests.writeLaterTitle(to: task, mintingFrom: &ids, in: log)
        feed.watcher.compareEachFile()
        #expect(try await Self.waits(for: .tasksChanged([taskID]), in: feed.changes, at: log.directory))
        #expect(!FileManager.default.fileExists(atPath: log.lockFileURL.path))
        await host.close()
    }

    // MARK: - Life of the stream

    @Test("The stream adds only the watched folder to the FSEvents stream, and makes no engine in the host")
    func streamWatchesOnlyFolder() async throws {
        let events = QuietFolderEvents()
        let host = HostFixture.makeHost(watchingWith: events)
        _ = try await host.boardChanges(inFolder: directory.url)
        #expect(events.startedPaths == [[FolderStreams.eventPath(of: directory.url)]])
        #expect(await host.engineCount == 0)
        await host.close()
    }

    @Test("A cancel of the loop that reads the stream stops the watcher")
    func cancelStopsWatcher() async throws {
        let host = HostFixture.makeHost(watchingWith: QuietFolderEvents())
        let feed = try #require(try await host.startBoardFolderFeed(inFolder: directory.url))
        let reading = Task {
            for await _ in feed.changes {}
        }
        reading.cancel()
        await reading.value
        await feed.consumer.value
        #expect(await feed.watcher.isRunning == false)
        await host.close()
    }

    @Test("A close of the host ends the stream")
    func hostCloseEndsStream() async throws {
        let host = HostFixture.makeHost(watchingWith: QuietFolderEvents())
        let changes = try await host.boardChanges(inFolder: directory.url)
        await host.close()
        var received: [BoardFolderChange] = []
        for await change in changes {
            received.append(change)
        }
        #expect(received.isEmpty)
    }

    @Test("A closed host gives a stream that ends at once and starts no watcher")
    func closedHostStartsNoWatcher() async throws {
        let events = QuietFolderEvents()
        let host = HostFixture.makeHost(watchingWith: events)
        await host.close()
        let changes = try await host.boardChanges(inFolder: directory.url)
        var received: [BoardFolderChange] = []
        for await change in changes {
            received.append(change)
        }
        #expect(received.isEmpty)
        #expect(events.startCount == 0)
    }
}

// MARK: - Merge run

/// One run of the stream on a board with a conflict version of its task log (``BoardFolderChangesTests/runMerge()``).
struct MergeRun {
    /// The host of the stream. The test closes it.
    let host: KanbanHost

    /// The first change that holds the id of the task, or `nil` when the stream ended first.
    let change: BoardFolderChange?

    /// The version store of the host. It records each resolve.
    let source: FakeFileVersionSource

    /// The log file of the task.
    let file: URL

    /// The ids of the events of both versions of the task log, in file order.
    let eventIDs: [ULID]
}
