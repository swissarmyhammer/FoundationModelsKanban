import Foundation
import FoundationModelsExtras

/// Sends the changes of the live graphs of some boards to the session views of the process (plan.md §6.7,
/// divergence.md §16). The changes are by the canonical path of the repo directory of each board.
typealias ChangePublisher = @Sendable ([String: BoardChanges]) async -> Void

/// Gets a call when the file load of a board starts and when it ends.
///
/// A test uses it to count the loads of a board, and to prove that the key read and the file load run at the same
/// time (divergence.md §16, L1).
protocol BoardLoadObserver: Sendable {
    /// Tells that the file load of a board started.
    ///
    /// - Parameter root: The root directory of the repo of the board.
    func boardLoadDidStart(at root: URL)

    /// Tells that the file load of a board ended.
    ///
    /// - Parameter root: The root directory of the repo of the board.
    func boardLoadDidFinish(at root: URL)
}

/// The engine of one board in a process: its live graph and commit path, its file watcher, its serial gate, its
/// search, and its change feed (plan.md §5.4, §5.6, §6.4, §6.7, divergence.md §16).
///
/// The ``KanbanHost`` makes one engine for each board, and gives it to each session view whose current board or
/// related board it is. The engine owns its watcher: the watcher starts when the engine loads, and stops only when
/// the engine closes. A board with no `.kanban/` directory yet has a watcher on its repo directory; the watcher moves
/// to `.kanban/` when the directory appears (X13).
///
/// The board stays in memory until the host closes. A session view that reads the board reads ``session``; it reads
/// no file. A call that writes holds ``gate``, runs on a copy of the session, and gives the new session back with
/// ``replaceSession(with:)`` while it still holds the gate (write through). The watcher brings each change from
/// outside the process into memory, inside the gate.
actor BoardEngine {
    /// The identity of the repo directory of the board: the key of the engine in the host.
    nonisolated let identity: FolderIdentity

    /// The root directory of the repo of the board, as the first load found it.
    nonisolated let root: URL

    /// The gate that lets one operation of the board run at a time: a call of a session view, or a batch of the
    /// watcher.
    nonisolated let gate = SerialGate()

    /// The subscribers of the changes of the board (plan.md §6.7).
    nonisolated let feed = ChangeFeed()

    /// The live graph of the board and its commit path.
    private(set) var session: CommitSession

    /// The state of the file watcher of the board.
    private var watchState: EngineWatchState

    /// Gets a call when the watcher applies a batch, or `nil` for no calls.
    private let batchObserver: (any LiveGraphObserver)?

    /// Sends the changes of a batch of the watcher to the session views.
    private let publish: ChangePublisher

    /// Makes the engine of a loaded board.
    ///
    /// - Parameters:
    ///   - identity: The identity of the repo directory of the board.
    ///   - root: The root directory of the repo of the board.
    ///   - session: The loaded session of the board.
    ///   - batchObserver: Gets a call when the watcher applies a batch, or `nil` for no calls.
    ///   - publish: Sends the changes of a batch of the watcher to the session views.
    private init(
        identity: FolderIdentity,
        root: URL,
        session: CommitSession,
        observingBatchesWith batchObserver: (any LiveGraphObserver)?,
        publishingTo publish: @escaping ChangePublisher
    ) {
        self.identity = identity
        self.root = root
        self.session = session
        self.batchObserver = batchObserver
        self.publish = publish
        watchState = .unwatched
    }

    /// The file watcher of the board while it runs, or `nil` when the board has no watcher. A test reads it to prove
    /// which directory the engine watches, and that a close stopped the watcher.
    var activeWatch: BoardWatch? {
        guard case .watching(let watch) = watchState else {
            return nil
        }
        return watch
    }

    // MARK: - Load

    /// Loads a board: it starts the file watcher, and reads the key and the log files of the board at the same time
    /// (divergence.md §16, L1). The log does not store the key, so the file load does not wait for it.
    ///
    /// The watcher starts first, so a change during the load is not lost: its batch waits until the engine is made,
    /// and then compares the files with the signatures of the load. The load checks first that the `.kanban/`
    /// directory is not a board of the old Rust kanban (divergence.md Q6), so the engine reads and writes nothing of
    /// an incompatible board. When the load fails, the watcher stops.
    ///
    /// The function is not isolated to an actor, so the host does not wait for it, and boards load at the same time
    /// (divergence.md §16, L6).
    ///
    /// - Parameter request: What to load, and the parts of the host that the engine uses.
    /// - Returns: The engine, with the board in memory and its search updated.
    /// - Throws: ``EventLogError/incompatibleBoard(directory:)`` when the `.kanban/` directory has Rust files. An
    ///   ``EventLogError`` when a file cannot be read, a ``BoardKeyError`` when git cannot give the key, or a
    ///   ``BoardWatcherError`` when the watcher cannot start.
    static func load(_ request: EngineLoad) async throws -> BoardEngine {
        let started = request.startsWatcher ? try BoardWatcher.started(onBoardAt: request.root) : nil
        do {
            async let key = request.key()
            async let live = request.liveGraph()
            let session = CommitSession(
                of: try await live,
                inBoard: try await key,
                mintingFrom: request.configuration.ids,
                timedBy: request.configuration.clock,
                searchingWith: TaskSearch(embeddingWith: request.embedder),
                writingWith: request.configuration.logWriter
            )
            await session.updateSearch()
            let engine = BoardEngine(
                identity: request.identity,
                root: request.root,
                session: session,
                observingBatchesWith: request.configuration.batchObserver,
                publishingTo: request.publish
            )
            if let started {
                await engine.consume(started)
            }
            return engine
        } catch {
            await started?.watcher.stop()
            throw error
        }
    }

    // MARK: - Session

    /// Gives the new session of the board after a call. The caller must hold ``gate``.
    ///
    /// - Parameter newSession: The session after the call.
    func replaceSession(with newSession: CommitSession) {
        session = newSession
    }

    /// Takes the changes of the live graph that added events since the last take, and forgets them. The caller must
    /// hold ``gate``.
    ///
    /// - Returns: The changes, or `nil` when the board did not change.
    func takeLiveChanges() -> BoardChanges? {
        let changes = session.takeLiveChanges()
        return BoardChanges(of: session, changes: changes)
    }

    /// Stops the file watcher and ends each subscription of the board. After the call returns, a change of a file
    /// applies nothing. The board stays in memory. A second call does nothing.
    func close() async {
        feed.finish()
        let watch = activeWatch
        watchState = .closed
        await watch?.end()
    }

    // MARK: - File watcher

    /// Starts the task that gives each batch of a watcher to ``receive(_:)``. The task holds the engine weakly, so
    /// the watcher does not keep the engine alive.
    ///
    /// - Parameter started: The started watcher and its directory.
    private func consume(_ started: StartedWatcher) {
        guard case .unwatched = watchState else {
            return
        }
        watchState = .watching(makeWatch(of: started))
    }

    /// Makes the watch of a started watcher: the watcher, and a task that gives each of its batches to
    /// ``receive(_:)``. The task holds the engine weakly.
    ///
    /// - Parameter started: The started watcher and its directory.
    /// - Returns: The watch.
    private func makeWatch(of started: StartedWatcher) -> BoardWatch {
        let batches = started.watcher.batches
        let consumer = Task { [weak self] in
            for await paths in batches {
                await self?.receive(paths)
            }
        }
        return BoardWatch(watcher: started.watcher, directory: started.directory, consumer: consumer)
    }

    /// Gives one batch of the watcher to the serial gate (plan.md §5.6, batch). A batch that cannot apply is recorded
    /// with swift-log. The live graph then does not change, and the commit check still finds the change.
    ///
    /// - Parameter paths: The changed paths of the batch.
    private func receive(_ paths: [URL]) async {
        do {
            try await gate.run {
                try await self.applyPublishing(paths)
            }
        } catch {
            Log.kanban.error(
                "The file watcher cannot apply a batch of changed files",
                metadata: ["paths": "\(paths.map(\.path))", "error": "\(error)"]
            )
        }
    }

    /// Applies one batch inside the serial gate, and then sends the changes of the board to the session views. The
    /// changes go out also when the apply throws, because the apply can change the live graph before it fails.
    ///
    /// - Parameter paths: The changed paths of the batch.
    /// - Throws: A ``BoardWatcherError`` when the watcher cannot move, or an ``EventLogError`` when a file cannot be
    ///   read.
    private func applyPublishing(_ paths: [URL]) async throws {
        do {
            try await apply(paths)
        } catch {
            await publishChanges()
            throw error
        }
        await publishChanges()
    }

    /// Sends the changes of the live graph since the last take to the session views.
    private func publishChanges() async {
        guard let changes = takeLiveChanges() else {
            return
        }
        await publish([root.canonicalPath: changes])
    }

    /// Moves the watcher to `.kanban/` when `.kanban/` appeared, and then applies one batch to the session of the
    /// board (plan.md §5.6). The engine stores the new watch before the apply, so the new watch stays also when the
    /// apply fails.
    ///
    /// When the watcher moved, the batch also holds the `.kanban/` directory, so that it compares each file of the
    /// board.
    ///
    /// - Parameter paths: The changed paths of the batch.
    /// - Throws: A ``BoardWatcherError`` when the watcher cannot move, or an ``EventLogError`` when a file cannot be
    ///   read.
    private func apply(_ paths: [URL]) async throws {
        guard let watch = activeWatch else {
            return
        }
        let moved = try await movedWatch(watch)
        if let moved {
            watchState = .watching(moved)
        }
        var updated = session
        let boardDirectory = updated.live.log.directory
        let applied = try await updated.apply(watchedPaths: moved == nil ? paths : paths + [boardDirectory])
        session = updated
        guard !applied.isEmpty else {
            return
        }
        batchObserver?.didApply(changedPaths: applied)
    }

    /// Moves the watcher from the repo directory to the `.kanban/` directory, when the watcher watches the repo
    /// directory and `.kanban/` is there now (plan.md §5.6, a repo with no `.kanban/` yet). The new watcher starts
    /// before the old one stops, so no change is lost.
    ///
    /// - Parameter watch: The watch of the board.
    /// - Returns: The new watch, or `nil` when the watcher did not move.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when the new watcher cannot start. Then the old
    ///   watcher stays.
    private func movedWatch(_ watch: BoardWatch) async throws(BoardWatcherError) -> BoardWatch? {
        guard
            watch.directory == root,
            let boardDirectory = BoardWatcher.existingBoardDirectory(ofBoardAt: root)
        else {
            return nil
        }
        let moved = makeWatch(
            of: StartedWatcher(watcher: try BoardWatcher(watching: boardDirectory), directory: boardDirectory)
        )
        await watch.watcher.stop()
        return moved
    }
}

// MARK: - Load request

/// What a ``BoardEngine`` loads, and the parts of the host that the engine uses.
struct EngineLoad: Sendable {
    /// The root directory of the repo of the board.
    let root: URL

    /// The identity of the root directory.
    let identity: FolderIdentity

    /// The key of the board when the caller knows it (a board of the scan), or `nil` to read it from git.
    let knownKey: BoardKey?

    /// The readers, the clock, the ULID source, the writer, and the observers of the host.
    let configuration: HostConfiguration

    /// The embedder of the search of the board, or `nil` for BM25 and trigram only.
    let embedder: (any PooledEmbedding)?

    /// `true` when the engine starts a file watcher. A closed host loads a board with no watcher.
    let startsWatcher: Bool

    /// Sends the changes of a batch of the watcher to the session views.
    let publish: ChangePublisher

    /// Gives the key of the board: the known key, or the key that git gives (with the first commit of a repo with no
    /// commit, divergence.md §16 M8).
    ///
    /// - Returns: The key.
    /// - Throws: A ``BoardKeyError`` when git cannot give the key.
    func key() async throws(BoardKeyError) -> BoardKey {
        if let knownKey {
            return knownKey
        }
        return try await configuration.keyReader(root)
    }

    /// Checks that the `.kanban/` directory is not a Rust board, and loads the live graph of the board from its log
    /// files with the parallel loader (plan.md §5.3).
    ///
    /// - Returns: The live graph.
    /// - Throws: ``EventLogError/incompatibleBoard(directory:)`` when the `.kanban/` directory has Rust files.
    ///   ``EventLogError/fileSystem(path:detail:)`` when a directory or a file cannot be read.
    func liveGraph() async throws(EventLogError) -> LiveGraph {
        let log = EventLog(repositoryAt: root)
        try log.checkCompatibility()
        configuration.loadObserver?.boardLoadDidStart(at: root)
        let live = try await LiveGraph.load(using: BoardLoader(reading: log, reportingTo: configuration.workerObserver))
        configuration.loadObserver?.boardLoadDidFinish(at: root)
        return live
    }
}

// MARK: - Watch

/// The state of the file watcher of a ``BoardEngine``.
private enum EngineWatchState {
    /// The engine has no watcher: the host loaded it after it closed, or the watcher did not start yet.
    case unwatched

    /// The watcher runs.
    case watching(BoardWatch)

    /// ``BoardEngine/close()`` stopped the watcher. No watcher starts again, and a batch that comes now changes
    /// nothing.
    case closed
}

/// A file watcher that started before its engine exists, and the directory that it watches. Its batches wait in the
/// stream of the watcher until the engine reads them.
struct StartedWatcher: Sendable {
    /// The watcher.
    let watcher: BoardWatcher

    /// The watched directory: the `.kanban/` directory of the board, or the repo directory until `.kanban/` appears.
    let directory: URL
}

extension BoardWatcher {
    /// Starts a file watcher on a board: on its `.kanban/` directory, or on the repo directory when `.kanban/` is not
    /// there.
    ///
    /// - Parameter root: The root directory of the repo of the board.
    /// - Returns: The started watcher.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when the watcher cannot start.
    static func started(onBoardAt root: URL) throws(BoardWatcherError) -> StartedWatcher {
        let directory = existingBoardDirectory(ofBoardAt: root) ?? root
        return StartedWatcher(watcher: try BoardWatcher(watching: directory), directory: directory)
    }

    /// Gives the `.kanban/` directory of a board when it is there.
    ///
    /// - Parameter root: The root directory of the repo of the board.
    /// - Returns: The `.kanban/` directory, or `nil` when the repo has no `.kanban/` directory yet.
    static func existingBoardDirectory(ofBoardAt root: URL) -> URL? {
        let boardDirectory = EventLog(repositoryAt: root).directory
        guard FileManager.default.fileExists(atPath: boardDirectory.path) else {
            return nil
        }
        return boardDirectory
    }
}

/// The file watcher of one loaded board, and the task that gives its batches to the engine (plan.md §5.6).
struct BoardWatch: Sendable {
    /// The watcher.
    let watcher: BoardWatcher

    /// The watched directory: the `.kanban/` directory of the board, or the repo directory until `.kanban/` appears.
    let directory: URL

    /// The task that gives each batch of the watcher to the engine. It ends when the batches of the watcher end.
    let consumer: Task<Void, Never>

    /// Stops the watcher, and waits until the task ends. After the call returns, the watch applies no batch.
    func end() async {
        await watcher.stop()
        consumer.cancel()
        await consumer.value
    }
}
