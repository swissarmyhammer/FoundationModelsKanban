import Foundation
import FoundationModelsExtras

/// The host of the kanban boards of one process: one engine for each board, and one session view for each working
/// directory (divergence.md §16).
///
/// One process runs many sessions at the same time, and each session has its own working directory. The host makes
/// each board load one time only: it keys each board by the file identity of the folder that holds `.kanban/` (its
/// device and its inode), not by the text of its path. A board that is the current board of one session and a related
/// board of another session is the same engine, with one live graph, one file watcher, one serial gate, one search,
/// and one change feed. Two sessions that open the same board at the same time wait for one load.
///
/// The boards are fully cached: a loaded board stays in memory until the process ends, also when its last session
/// closes. A read reads memory only. A write goes to the log files and to memory in the same commit, so each other
/// session sees it at once. The file watcher of each board brings the changes from outside the process into memory.
///
/// ``shared`` is the only host of a process. Get a session view with ``session(workingDirectory:actor:)``:
///
/// ```swift
/// let graph = try await KanbanHost.shared.session(workingDirectory: folder, actor: "Claude Code")
/// ```
public actor KanbanHost {
    /// The host of the process. It is the only host: the host has no public initializer.
    public static let shared = KanbanHost(configuration: HostConfiguration())

    /// The readers, the clock, the ULID source, the writer, and the observers of the boards of the host.
    nonisolated let configuration: HostConfiguration

    /// Finds the related boards (plan.md §6.6). ``configure(locator:embedder:)`` can change it before the first
    /// session.
    private(set) var locator: BoardLocator

    /// The embedder of the search of each board, or `nil` for BM25 and trigram only.
    private var embedder: (any PooledEmbedding)?

    /// The engine of each board, by the identity of its repo directory: loaded, or loading.
    private var engines: [FolderIdentity: EngineSlot] = [:]

    /// The index of the last scan of each list of scan places (plan.md §6.6, index life).
    private var scanIndexes: [[String]: BoardIndex] = [:]

    /// The session views that get the changes of the boards, by their object identity. The host does not keep a view
    /// alive.
    private var views: [ObjectIdentifier: WeakView] = [:]

    /// `true` after ``close()``: no file watcher starts.
    private var isClosed = false

    /// Makes a host. A process has one host, ``shared``. A test makes its own host, so that it can give fake readers
    /// and close the host at the end.
    ///
    /// - Parameter configuration: The readers, the clock, the ULID source, the writer, and the observers.
    init(configuration: HostConfiguration) {
        self.configuration = configuration
        locator = configuration.locator
        embedder = configuration.embedder
    }

    /// Sets the locator of the related boards and the embedder of the search. Call it one time when the process
    /// starts, before the first session.
    ///
    /// - Parameters:
    ///   - locator: Finds the related boards: it holds the extra search roots (plan.md §6.6).
    ///   - embedder: The embedder of `searchTasks`, for example a `PooledEmbedder`, or `nil` for a search with BM25
    ///     and trigram only, which needs no model (plan.md §6.4).
    public func configure(locator: BoardLocator, embedder: (any PooledEmbedding)?) {
        precondition(engines.isEmpty, "Configure the kanban host before the first session loads a board")
        self.locator = locator
        self.embedder = embedder
    }

    /// Makes the session view of a working directory, and loads its board before it returns (divergence.md §16,
    /// Gap 2).
    ///
    /// The board of the session is the `.kanban/` directory of the top folder of the worktree of the working
    /// directory (`git rev-parse --show-toplevel`). The host finds the engine of that board, or makes it and loads the
    /// board: the key of the repo (with a first commit when the repo has no commit), the file watcher, and the log
    /// files, at the same time. A second session on the same board waits for the same load. A working directory that
    /// is not in a git repo has no board: the session starts, and each call gives `NOT_A_REPO`.
    ///
    /// - Parameters:
    ///   - workingDirectory: The working directory of the session.
    ///   - actor: The name of the session actor: the actor of each change that the session writes. Give each session
    ///     its own actor, so that `undo` with no argument stays in its session. `nil` gives the name of the OS user.
    /// - Returns: The session view. Its calls with no board go to the board of the working directory.
    /// - Throws: ``KanbanError/incompatibleBoard(directory:)`` when the `.kanban/` directory is a board of the old
    ///   Rust kanban (divergence.md Q6). ``KanbanError/invalidSlug(name:)`` when the actor name gives an empty slug.
    ///   An I/O fault when git cannot give the top folder or the key, when a log file cannot be read, or when the
    ///   file watcher cannot start.
    public func session(workingDirectory: URL, actor: String?) async throws -> KanbanGraph {
        let view = try KanbanGraph(
            host: self,
            owningHost: false,
            workingDirectory: workingDirectory,
            actingAs: KanbanGraph.sessionActor(named: actor),
            locatedBy: locator
        )
        do {
            try await view.prepareBoard()
        } catch {
            throw KanbanError(callFailure: error) ?? error
        }
        return view
    }

    // MARK: - Engines

    /// Gives the engine of a board, and loads the board when no engine has it yet (divergence.md §16).
    ///
    /// The host finds the engine by the identity of the repo directory, so each path to the folder gives the same
    /// engine. The host stores the load task in its table before it waits, so a second caller waits for the same
    /// load. The load runs outside the host, so boards load at the same time. A load that fails leaves no engine, and
    /// the next caller loads again.
    ///
    /// - Parameters:
    ///   - root: The root directory of the repo of the board.
    ///   - knownKey: The key of the board when the caller knows it, or `nil` to read it from git.
    /// - Returns: The engine.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the folder cannot be read. An error of the load.
    func engine(ofBoardAt root: URL, knownKey: BoardKey? = nil) async throws -> BoardEngine {
        let identity = try FolderIdentity(of: root)
        switch engines[identity] {
        case .loaded(let engine):
            return engine
        case .loading(let load):
            return try await load.value
        case nil:
            return try await startLoad(ofBoardAt: root, identity: identity, knownKey: knownKey)
        }
    }

    /// Starts the load of a board, stores the load task, and waits for it.
    ///
    /// - Parameters:
    ///   - root: The root directory of the repo of the board.
    ///   - identity: The identity of the root directory.
    ///   - knownKey: The key of the board when the caller knows it, or `nil` to read it from git.
    /// - Returns: The engine.
    /// - Throws: An error of the load. Then the table has no engine for the board.
    private func startLoad(
        ofBoardAt root: URL,
        identity: FolderIdentity,
        knownKey: BoardKey?
    ) async throws -> BoardEngine {
        let request = EngineLoad(
            root: root,
            identity: identity,
            knownKey: knownKey,
            configuration: configuration,
            embedder: embedder,
            startsWatcher: !isClosed,
            publish: { [weak self] changed in await self?.publish(changed) }
        )
        let load = Task { try await BoardEngine.load(request) }
        engines[identity] = .loading(load)
        do {
            let engine = try await load.value
            engines[identity] = .loaded(engine)
            if isClosed {
                await engine.close()
            }
            return engine
        } catch {
            engines[identity] = nil
            throw error
        }
    }

    /// The number of loaded boards. A test reads it to prove that each board loads one time.
    var engineCount: Int {
        loadedEngines.count
    }

    /// The number of loaded boards whose file watcher runs. A test reads it to prove that each board has one watcher.
    var runningWatcherCount: Int {
        get async {
            var count = 0
            for engine in loadedEngines where await engine.activeWatch != nil {
                count += 1
            }
            return count
        }
    }

    /// The engine of each loaded board.
    private var loadedEngines: [BoardEngine] {
        engines.values.compactMap { slot in
            guard case .loaded(let engine) = slot else {
                return nil
            }
            return engine
        }
    }

    // MARK: - Scan

    /// Gives the index of the last scan of the places around a repo, or `nil` before the first scan (plan.md §6.6,
    /// index life).
    ///
    /// - Parameter root: The top folder of the worktree of the current board of a session.
    /// - Returns: The index.
    func scanIndex(around root: URL) -> BoardIndex? {
        scanIndexes[Self.placesKey(of: locator.places(around: root))]
    }

    /// Scans the places around a repo for repos, and records the new index. A repo of the earlier scan of the same
    /// places keeps its key.
    ///
    /// - Parameter root: The top folder of the worktree of the current board of a session.
    /// - Returns: The new index.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during the scan. Then the host
    ///   keeps the earlier index.
    func rescan(around root: URL) async throws(BoardKeyError) -> BoardIndex {
        let key = Self.placesKey(of: locator.places(around: root))
        let scanned = try await locator.scan(around: root, reusing: scanIndexes[key], readingKeysWith: configuration.keyReader)
        scanIndexes[key] = scanned
        return scanned
    }

    /// Gives the key of a list of scan places in the table of the scan indexes.
    ///
    /// - Parameter places: The places, in scan order.
    /// - Returns: The canonical path of each place, in scan order.
    private static func placesKey(of places: [URL]) -> [String] {
        places.map(\.canonicalPath)
    }

    // MARK: - Views

    /// Records a session view, so that it gets the changes of the boards. A view records itself when it finds its
    /// board and when a subscription of the view starts. A second record of a view changes nothing.
    ///
    /// - Parameter view: The view.
    func register(_ view: KanbanGraph) {
        views[ObjectIdentifier(view)] = WeakView(view: view)
    }

    /// Forgets a session view: it gets no more changes.
    ///
    /// - Parameter view: The view.
    func unregister(_ view: KanbanGraph) {
        views[ObjectIdentifier(view)] = nil
    }

    /// Sends the changes of some boards to each session view, so that each view sends them to its own subscribers
    /// (plan.md §6.7).
    ///
    /// - Parameter changed: The changes of each board that changed, by the canonical path of its repo directory.
    func publish(_ changed: [String: BoardChanges]) async {
        views = views.filter { _, entry in entry.view != nil }
        for view in views.values.compactMap(\.view) {
            await view.publish(changed)
        }
    }

    // MARK: - Close

    /// Stops the file watcher of each board and ends each subscription. The boards stay in memory, and a board that
    /// loads later has no watcher. The shared host stays open for the life of the process; a test closes its own
    /// host.
    func close() async {
        isClosed = true
        for slot in engines.values {
            switch slot {
            case .loaded(let engine):
                await engine.close()
            case .loading(let load):
                await (try? load.value)?.close()
            }
        }
    }
}

// MARK: - Configuration

/// The parts of a ``KanbanHost`` that a test can change: the readers of git, the clock, the ULID source, the
/// locator, the embedder, the writer of the logs, and the observers.
struct HostConfiguration: Sendable {
    /// Reads the key of the board of a repo.
    let keyReader: BoardKeyReader

    /// Reads the top folder of the worktree of a folder.
    let topReader: WorktreeTopReader

    /// The clock that gives the time of a change.
    let clock: @Sendable () -> DateTime

    /// The source of the transaction ULIDs and the event ids of each board.
    let ids: any ULIDSource

    /// Finds the related boards.
    let locator: BoardLocator

    /// The embedder of the search of each board, or `nil` for BM25 and trigram only.
    let embedder: (any PooledEmbedding)?

    /// Gets a call when a file watcher applies a batch, or `nil` for no calls.
    let batchObserver: (any LiveGraphObserver)?

    /// The writer of the appends of each commit.
    let logWriter: any EventLogWriter

    /// Gets a call when the file load of a board starts and ends, or `nil` for no calls.
    let loadObserver: (any BoardLoadObserver)?

    /// Gets a call when each worker of a loader reads a file, or `nil` for no calls.
    let workerObserver: (any LoaderWorkerObserver)?

    /// Makes a configuration. Each default is the value of the process: git, the system clock, random ULIDs, and the
    /// log files.
    ///
    /// - Parameters:
    ///   - keyReader: Reads the key of the board of a repo.
    ///   - topReader: Reads the top folder of the worktree of a folder.
    ///   - clock: The clock that gives the time of a change.
    ///   - ids: The source of the transaction ULIDs and the event ids.
    ///   - locator: Finds the related boards.
    ///   - embedder: The embedder of the search, or `nil` for BM25 and trigram only.
    ///   - batchObserver: Gets a call when a file watcher applies a batch, or `nil` for no calls.
    ///   - logWriter: The writer of the appends of each commit.
    ///   - loadObserver: Gets a call when the file load of a board starts and ends, or `nil` for no calls.
    ///   - workerObserver: Gets a call when each worker of a loader reads a file, or `nil` for no calls.
    init(
        keyReader: @escaping BoardKeyReader = BoardKey.read(fromRepoAt:),
        topReader: @escaping WorktreeTopReader = BoardKey.worktreeTop(of:),
        clock: @escaping @Sendable () -> DateTime = { DateTime(Date()) },
        ids: any ULIDSource = SystemULIDSource(),
        locator: BoardLocator = .default,
        embedder: (any PooledEmbedding)? = nil,
        batchObserver: (any LiveGraphObserver)? = nil,
        logWriter: any EventLogWriter = FileEventLogWriter(),
        loadObserver: (any BoardLoadObserver)? = nil,
        workerObserver: (any LoaderWorkerObserver)? = nil
    ) {
        self.keyReader = keyReader
        self.topReader = topReader
        self.clock = clock
        self.ids = ids
        self.locator = locator
        self.embedder = embedder
        self.batchObserver = batchObserver
        self.logWriter = logWriter
        self.loadObserver = loadObserver
        self.workerObserver = workerObserver
    }
}

// MARK: - Table entries

/// The engine of one board in the table of a ``KanbanHost``.
private enum EngineSlot {
    /// The board loads. Each caller waits for this task.
    case loading(Task<BoardEngine, Error>)

    /// The board is loaded.
    case loaded(BoardEngine)
}

/// A session view that the host does not keep alive.
private struct WeakView {
    /// The view, or `nil` after the view is gone.
    weak var view: KanbanGraph?
}
