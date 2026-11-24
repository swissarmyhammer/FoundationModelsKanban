import Foundation
import ULID

/// One change of the board of a folder that has no open session, in the stream of
/// ``KanbanHost/boardChanges(inFolder:)`` (TestudoApp D214).
///
/// The stream works for a folder that has no open session. It gives the changes of a session of this process, of a
/// different process (for example the `sah` tools), and of each other writer of the log files.
///
/// Each change holds the folder of the stream and the stamp of the board after the change, so that a caller that
/// follows many folders knows the folder of each change, and keeps the stamp to compare it later with
/// ``KanbanHost/boardStamp(ofFolder:)``.
public struct BoardFolderChange: Hashable, Sendable {
    /// The folder that the caller gave to ``KanbanHost/boardChanges(inFolder:)``, as the caller gave it.
    public let folder: URL

    /// The stamp of the board after the change (``KanbanHost/boardStamp(ofFolder:)``), or `nil` for
    /// ``Kind/boardRemoved``. The stream reads the stamp before it reads the changed log files, the same as
    /// ``BoardSnapshot/stamp``. Thus, when nothing changed after the change, the stamp is equal to the stamp that
    /// ``KanbanHost/boardStamp(ofFolder:)`` gives now, and a write during the read gives a different stamp.
    public let stamp: BoardStamp?

    /// What changed.
    public let kind: Kind

    /// What changed in the board. Each id is the ULID text of a task, the same as ``BoardSnapshot/Task/id``.
    public enum Kind: Hashable, Sendable {
        /// The ids of the tasks that are new or that changed. A change of a comment of a task also gives the id of
        /// its task. Read the board again to get the new values of these tasks.
        case tasksChanged(Set<String>)

        /// The ids of the tasks whose log file went away, or that a `deleteTask` made a tombstone.
        case tasksRemoved(Set<String>)

        /// A column, a tag, an actor, or the board node changed. Read the board again.
        case boardChanged

        /// The `.kanban/` folder went away. The stream continues: when a new `.kanban/` folder comes, the stream
        /// gives ``boardChanged`` and ``tasksChanged(_:)`` with the id of each task of the new board.
        case boardRemoved
    }
}

// MARK: - Feed

/// The change stream of the board of one folder, with the file watcher that feeds it (TestudoApp D214).
///
/// The feed opens no session and makes no ``BoardEngine``. It keeps its own ``LiveGraph`` of the board. It takes no
/// lock, runs no git, and writes no file. The watcher watches the folder that holds `.kanban/`, on the one
/// ``FolderStreams`` of the host, so that the feed sees the remove and the return of `.kanban/` too.
struct BoardFolderFeed: Sendable {
    /// The changes of the board, in the order of the batches of the watcher. The stream ends when the watcher stops:
    /// when the caller cancels its loop, and when the host closes.
    let changes: AsyncStream<BoardFolderChange>

    /// The file watcher of the folder.
    let watcher: BoardWatcher

    /// The task that reads each batch of the watcher and gives its changes to ``changes``. It ends after the watcher
    /// stopped and the stream ended.
    let consumer: Task<Void, Never>

    /// Starts the watcher on a folder, loads the board of the folder, and starts the stream.
    ///
    /// The watcher starts before the load. After the load, the feed asks the watcher for one compare of each file
    /// (``BoardWatcher/compareEachFile()``), the same as ``BoardEngine`` does after its load. Thus a change between the
    /// start of the watcher and the read of a file is not lost.
    ///
    /// - Parameters:
    ///   - folder: The folder that holds `.kanban/`. It must exist. It does not have to hold `.kanban/` yet.
    ///   - folderStreams: The FSEvents stream of the host.
    ///   - observer: Gets a call when each worker of the loader reads a file, or `nil` for no calls.
    /// - Returns: The started feed.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when the watcher cannot start.
    ///   ``EventLogError/incompatibleBoard(directory:)`` when `.kanban/` is a board of the old Rust kanban.
    ///   ``EventLogError/fileSystem(path:detail:)`` when a folder or a file is there and cannot be read.
    static func start(
        watching folder: URL,
        in folderStreams: FolderStreams,
        reportingTo observer: (any LoaderWorkerObserver)?
    ) async throws -> BoardFolderFeed {
        let watcher = try await BoardWatcher(watching: folder, in: folderStreams)
        let reader: BoardFolderReader
        do {
            reader = try await BoardFolderReader(readingFolder: folder, reportingTo: observer)
        } catch {
            await watcher.stop()
            throw error
        }
        let feed = BoardFolderFeed(feeding: watcher, to: reader)
        watcher.compareEachFile()
        return feed
    }

    /// Makes the stream and the task that gives each batch of a watcher to a reader.
    ///
    /// The end of the stream (a cancel of the loop of the caller) cancels the task. The task then stops the watcher,
    /// so that the FSEvents stream of the host does not watch the folder for this feed any more.
    ///
    /// - Parameters:
    ///   - watcher: The started watcher of the folder.
    ///   - reader: The reader of the board, after its load.
    private init(feeding watcher: BoardWatcher, to reader: BoardFolderReader) {
        let (changes, continuation) = AsyncStream<BoardFolderChange>.makeStream()
        let consumer = Task {
            var reader = reader
            for await paths in watcher.batches {
                for change in await reader.changes(after: paths) {
                    continuation.yield(change)
                }
            }
            await watcher.stop()
            continuation.finish()
        }
        continuation.onTermination = { _ in
            consumer.cancel()
        }
        self.changes = changes
        self.watcher = watcher
        self.consumer = consumer
    }
}

// MARK: - Reader

/// The board of one folder in memory, for the change stream of the folder: a ``LiveGraph``, or no board when the
/// folder has no `.kanban/` folder.
struct BoardFolderReader: Sendable {
    /// The folder that holds `.kanban/`: the folder that the watcher watches.
    private let folder: URL

    /// The event log of the board of the folder.
    private let log: EventLog

    /// Gets a call when each worker of the loader reads a file, or `nil` for no calls.
    private let observer: (any LoaderWorkerObserver)?

    /// The board in memory, or `nil` when the folder has no `.kanban/` folder.
    private var live: LiveGraph?

    /// Loads the board of a folder, when the folder has a `.kanban/` folder.
    ///
    /// - Parameters:
    ///   - folder: The folder that holds `.kanban/`.
    ///   - observer: Gets a call when each worker of the loader reads a file, or `nil` for no calls.
    /// - Throws: ``EventLogError/incompatibleBoard(directory:)`` when `.kanban/` is a board of the old Rust kanban.
    ///   ``EventLogError/fileSystem(path:detail:)`` when a folder or a file is there and cannot be read.
    init(readingFolder folder: URL, reportingTo observer: (any LoaderWorkerObserver)?) async throws(EventLogError) {
        self.folder = folder
        self.observer = observer
        log = EventLog(repositoryAt: folder)
        live = try await Self.loadedBoard(of: log, reportingTo: observer)
    }

    /// Loads a board with the full parallel loader, when its `.kanban/` folder is there.
    ///
    /// - Parameters:
    ///   - log: The event log of the board.
    ///   - observer: Gets a call when each worker of the loader reads a file, or `nil` for no calls.
    /// - Returns: The board, or `nil` when the folder has no `.kanban/` folder.
    /// - Throws: ``EventLogError/incompatibleBoard(directory:)`` when `.kanban/` is a board of the old Rust kanban.
    ///   ``EventLogError/fileSystem(path:detail:)`` when a folder or a file is there and cannot be read.
    private static func loadedBoard(
        of log: EventLog,
        reportingTo observer: (any LoaderWorkerObserver)?
    ) async throws(EventLogError) -> LiveGraph? {
        guard hasBoardDirectory(log) else {
            return nil
        }
        try log.checkCompatibility()
        return try await LiveGraph.load(using: BoardLoader(reading: log, reportingTo: observer))
    }

    /// Tells if the `.kanban/` folder of a board is there. A regular file with that name is not a board, the same as
    /// for ``BoardStamp``.
    ///
    /// - Parameter log: The event log of the board.
    /// - Returns: `true` when `.kanban/` is a directory.
    private static func hasBoardDirectory(_ log: EventLog) -> Bool {
        FileStamp(ofItemAt: log.directory)?.isDirectory == true
    }

    /// Reads one batch of the watcher, and gives the changes of the board.
    ///
    /// The reader keeps only the paths of the board: a node log, the `.kanban/` folder, a node directory, and the
    /// watched folder (a batch of lost events). Thus a batch with only the lock file, or only files outside `.kanban/`,
    /// reads no file and gives no change. A batch that cannot be read is recorded with swift-log and gives no change.
    /// The board in memory then does not change, and the compare of the next batch finds the change.
    ///
    /// - Parameter paths: The changed paths of the batch.
    /// - Returns: The changes, or an empty list when the board did not change.
    mutating func changes(after paths: [URL]) async -> [BoardFolderChange] {
        let boardPaths = paths.filter(isBoardPath)
        guard !boardPaths.isEmpty else {
            return []
        }
        do {
            return try await changes(afterBoardPaths: boardPaths)
        } catch {
            Log.kanban.error(
                "The change stream of a board folder cannot read a batch of changed files",
                metadata: ["folder": "\(folder.path)", "paths": "\(boardPaths.map(\.path))", "error": "\(error)"]
            )
            return []
        }
    }

    /// Reads one batch of paths of the board, and gives the changes of the board with the folder and the stamp.
    ///
    /// The reader reads the stamp of the board first (``BoardStamp/init(ofBoardAt:)``), before it reads a log file.
    /// No stamp tells that `.kanban/` is not there.
    ///
    /// - When `.kanban/` went away, the reader forgets the board and gives ``BoardFolderChange/Kind/boardRemoved``.
    /// - When `.kanban/` came, the reader loads the board and gives the changes of a new board.
    /// - Else the reader applies the changed files to the live graph, and compares the graph before and after.
    ///
    /// - Parameter paths: The changed paths of the board.
    /// - Returns: The changes, or an empty list when the board did not change.
    /// - Throws: ``EventLogError`` when a folder or a file cannot be read, or when a new `.kanban/` is a board of the
    ///   old Rust kanban.
    private mutating func changes(afterBoardPaths paths: [URL]) async throws(EventLogError) -> [BoardFolderChange] {
        guard let stamp = BoardStamp(ofBoardAt: folder) else {
            return forgetBoard().map { kind in BoardFolderChange(folder: folder, stamp: nil, kind: kind) }
        }
        let kinds = try await kinds(afterBoardPaths: paths)
        return kinds.map { kind in BoardFolderChange(folder: folder, stamp: stamp, kind: kind) }
    }

    /// Reads one batch of paths of a board whose `.kanban/` folder is there, and gives what changed.
    ///
    /// - Parameter paths: The changed paths of the board.
    /// - Returns: What changed, or an empty list when the board did not change.
    /// - Throws: ``EventLogError`` when a folder or a file cannot be read, or when a new `.kanban/` is a board of the
    ///   old Rust kanban.
    private mutating func kinds(afterBoardPaths paths: [URL]) async throws(EventLogError) -> [BoardFolderChange.Kind] {
        guard var current = live else {
            return try await loadNewBoard()
        }
        let before = current.graph
        let refs = paths.contains(where: isDirectory) ? try current.changedRefs() : try current.changedRefs(among: paths)
        guard !refs.isEmpty else {
            return []
        }
        _ = try await current.apply(changedPaths: refs.sorted().map(log.fileURL(for:)))
        _ = current.takeChanges()
        live = current
        return BoardFolderDiff(before: before, after: current.graph).changes
    }

    /// Forgets the board after its `.kanban/` folder went away.
    ///
    /// - Returns: ``BoardFolderChange/Kind/boardRemoved``, or an empty list when the reader had no board.
    private mutating func forgetBoard() -> [BoardFolderChange.Kind] {
        guard live != nil else {
            return []
        }
        live = nil
        return [.boardRemoved]
    }

    /// Loads the board after a new `.kanban/` folder came.
    ///
    /// - Returns: ``BoardFolderChange/Kind/boardChanged``, and ``BoardFolderChange/Kind/tasksChanged(_:)`` with the id of each
    ///   live task when the board has a live task.
    /// - Throws: ``EventLogError`` when a folder or a file cannot be read, or when `.kanban/` is a board of the old Rust
    ///   kanban.
    private mutating func loadNewBoard() async throws(EventLogError) -> [BoardFolderChange.Kind] {
        guard let loaded = try await Self.loadedBoard(of: log, reportingTo: observer) else {
            return []
        }
        live = loaded
        let ids = BoardFolderDiff.liveTaskIDs(in: loaded.graph)
        return [.boardChanged] + (ids.isEmpty ? [] : [.tasksChanged(ids)])
    }

    /// Tells if a changed path is a path of the board: a node log, or a directory whose files the reader compares.
    ///
    /// - Parameter path: The changed path.
    /// - Returns: `true` when the path is a path of the board.
    private func isBoardPath(_ path: URL) -> Bool {
        log.ref(ofFileAt: path) != nil || isDirectory(path)
    }

    /// Tells if a changed path is a directory whose files the reader compares: the `.kanban/` folder, a node directory
    /// in it (a tool moved the whole directory), or the watched folder (FSEvents lost events, or the first compare
    /// after the start).
    ///
    /// - Parameter path: The changed path.
    /// - Returns: `true` when the reader compares each file of the board for the path.
    private func isDirectory(_ path: URL) -> Bool {
        log.isBoardDirectory(at: path) || log.isNodeDirectory(at: path) || path.canonicalPath == folder.canonicalPath
    }
}

// MARK: - Diff

/// The changes between two graphs of one board, as ``BoardFolderChange/Kind`` values.
struct BoardFolderDiff {
    /// The graph before the change.
    let before: Graph

    /// The graph after the change.
    let after: Graph

    /// The changes, in this order: ``BoardFolderChange/Kind/boardChanged``, ``BoardFolderChange/Kind/tasksChanged(_:)``, and
    /// ``BoardFolderChange/Kind/tasksRemoved(_:)``. Each one is in the list only when it has content.
    ///
    /// The diff compares the two graphs with ``Graph/changedRefs(since:)``. When that compare cannot tell (a full
    /// reload builds the graph again with new slots), the diff compares each task ref of the two graphs: each live
    /// task of the new graph is changed, and the board is changed.
    var changes: [BoardFolderChange.Kind] {
        guard let refs = after.changedRefs(since: before) else {
            return kinds(boardChanged: true, changedRefs: allTaskRefs)
        }
        let boardChanged = refs.contains { ref in Self.isBoardRef(ref) }
        return kinds(boardChanged: boardChanged, changedRefs: refs)
    }

    /// Gives the ids of the live tasks of a graph.
    ///
    /// - Parameter graph: The graph.
    /// - Returns: The ULID text of each task that is not a tombstone.
    static func liveTaskIDs(in graph: Graph) -> Set<String> {
        Set(graph.allSlots.compactMap { slot in
            graph.node(at: slot, as: TaskNode.self).flatMap { task in task.fields.isDeleted ? nil : task.id.ulidString }
        })
    }

    /// Tells if a ref is a node of the board itself, and not a task or a comment: the board, a column, a tag, or an
    /// actor.
    ///
    /// - Parameter ref: The ref.
    /// - Returns: `true` when a change of the node gives ``BoardFolderChange/Kind/boardChanged``.
    private static func isBoardRef(_ ref: LocalRef) -> Bool {
        switch ref {
        case .board, .column, .tag, .actor: true
        case .task, .comment: false
        }
    }

    /// The ref of each task of the two graphs.
    private var allTaskRefs: Set<LocalRef> {
        Set([before, after].flatMap { graph in
            graph.allSlots.compactMap { slot in graph.node(at: slot, as: TaskNode.self)?.ref }
        })
    }

    /// Makes the list of what changed from the changed refs.
    ///
    /// - Parameters:
    ///   - boardChanged: `true` when a node of the board itself changed.
    ///   - refs: The changed refs.
    /// - Returns: The changes, in the order of ``changes``.
    private func kinds(boardChanged: Bool, changedRefs refs: Set<LocalRef>) -> [BoardFolderChange.Kind] {
        let removed = Set(refs.compactMap(removedTaskID))
        let changed = Set(refs.compactMap(changedTaskID)).subtracting(removed)
        let board: [BoardFolderChange.Kind] = boardChanged ? [.boardChanged] : []
        let tasks: [BoardFolderChange.Kind] = changed.isEmpty ? [] : [.tasksChanged(changed)]
        return board + tasks + (removed.isEmpty ? [] : [.tasksRemoved(removed)])
    }

    /// Gives the id of the task of a changed ref when that task is live after the change: the task of a task ref, or
    /// the task of a comment ref.
    ///
    /// - Parameter ref: The changed ref.
    /// - Returns: The ULID text of the task, or `nil` when the ref names no task that is live after the change.
    private func changedTaskID(of ref: LocalRef) -> String? {
        let task: ULID?
        switch ref {
        case .task(let id):
            task = id
        case .comment:
            task = taskOfComment(at: ref, in: after) ?? taskOfComment(at: ref, in: before)
        case .board, .column, .tag, .actor:
            task = nil
        }
        return task.flatMap { id in after.isLive(TaskNode.self, for: .task(id)) ? id.ulidString : nil }
    }

    /// Gives the id of a task ref whose task was live before the change and is not live after it: its file went away,
    /// or it became a tombstone.
    ///
    /// - Parameter ref: The changed ref.
    /// - Returns: The ULID text of the task, or `nil` when the ref is not such a task.
    private func removedTaskID(of ref: LocalRef) -> String? {
        guard
            case .task(let id) = ref,
            before.isLive(TaskNode.self, for: ref),
            !after.isLive(TaskNode.self, for: ref)
        else {
            return nil
        }
        return id.ulidString
    }

    /// Gives the task of a comment in a graph.
    ///
    /// - Parameters:
    ///   - ref: The ref of the comment.
    ///   - graph: The graph.
    /// - Returns: The ULID of the task, or `nil` when the graph has no such comment, or the comment has no task edge to
    ///   a task of this board.
    private func taskOfComment(at ref: LocalRef, in graph: Graph) -> ULID? {
        guard
            let slot = graph.slot(for: ref),
            let target = graph.node(at: slot, as: CommentNode.self)?.task
        else {
            return nil
        }
        switch target {
        case .slot(let taskSlot):
            return graph.node(at: taskSlot, as: TaskNode.self)?.id
        case .unresolved(.local(.task(let id))):
            return id
        case .unresolved:
            return nil
        }
    }
}
