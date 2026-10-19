import Foundation
import FoundationModelsExtras
import Logging

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

    /// The one FSEvents stream of each folder that a file watcher of the host watches: the board directories, the
    /// scan places, the boards that could not load, and the folders that a path ref named (divergence.md §16). The
    /// system gives few FSEvents streams to all processes together, so the host does not start one for each folder.
    nonisolated let folderStreams: FolderStreams

    /// Finds the related boards (plan.md §6.6). ``configure(locator:embedder:)`` can change it before the first
    /// session.
    private(set) var locator: BoardLocator

    /// The embedder of the search of each board, or `nil` for BM25 and trigram only.
    private var embedder: (any PooledEmbedding)?

    /// The engine of each board, by the identity of its repo directory: loaded, or loading.
    private var engines: [FolderIdentity: EngineSlot] = [:]

    /// Each engine that the host let go of because its folder moved away from its root path (divergence.md §16,
    /// Gap 6). The host does not keep an engine alive: a session view that still holds the engine keeps it until the
    /// view follows the move. ``close()`` closes each engine that is still alive, so that its subscriptions end.
    private var retiredEngines: [Weak<BoardEngine>] = []

    /// Each related board whose last load failed, by the identity of its repo directory (divergence.md Q7). A related
    /// load of such a board gives the same error again, with no read of a file, until the file watcher of the board
    /// sees a change.
    private var unloadableBoards: [FolderIdentity: UnloadableBoard] = [:]

    /// The index of the last scan of each list of scan places, and when it can serve a call with no new scan
    /// (plan.md §6.6, index life; divergence.md §16, Gap 1).
    private var scanCache = ScanCache()

    /// The scan of each list of scan places that runs now, by the canonical path of each place in scan order. A call
    /// that needs the index of the places while their scan runs waits for the index of that scan, and does not start
    /// a second scan.
    private var runningScans: [[String]: RunningScan] = [:]

    /// The file watcher of each scan place, by the canonical path of the place. A change that a watcher sees makes
    /// the indexes of the place out of date.
    private var placeWatches: [String: BoardWatch] = [:]

    /// The start of the file watcher of each scan place whose start runs now, by the canonical path of the place. A
    /// second call that needs the watcher of the place waits for this start, so that one place never gets two
    /// watchers.
    private var placeWatchStarts: [String: Task<Void, Never>] = [:]

    /// What git told about each folder that a path ref named, and the file watcher that keeps it current, by the
    /// canonical path of the folder (divergence.md §16, Gap 1; divergence.md X4). A later call with the same path ref
    /// runs no `git`, and a later ref with the key of such a board resolves to it when the scan index has no copy with
    /// the key. A change that the watcher sees of the repo folder, its `.git` entry, or its git config removes the
    /// entry, the same as the scan index forgets the key of a repo.
    private var knownFolders: [String: KnownFolder] = [:]

    /// The file watcher of the parent folder of each current board of a session outside git, by the identity of the
    /// root directory of the board (divergence.md M9). A `git init` in the root directory shows in this watcher, and
    /// the host then gives the engine the git key. Thus a read runs no `git`.
    private var bareBoardWatches: [FolderIdentity: BoardWatch] = [:]

    /// The session views that get the changes of the boards, by their object identity. The host does not keep a view
    /// alive.
    private var views: [ObjectIdentifier: Weak<KanbanGraph>] = [:]

    /// `true` after ``close()``: no file watcher starts.
    private var isClosed = false

    /// Makes a host. A process has one host, ``shared``. A test makes its own host, so that it can give fake readers
    /// and close the host at the end.
    ///
    /// - Parameter configuration: The readers, the clock, the ULID source, the writer, the observers, and the FSEvents
    ///   calls.
    init(configuration: HostConfiguration) {
        self.configuration = configuration
        folderStreams = FolderStreams(service: configuration.folderEvents)
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
    /// files, at the same time. A second session on the same board waits for the same load. Outside git, the board is
    /// in the nearest folder, from the working directory up, that has a `.kanban/`, else in the working directory, and
    /// its key is its board ID (divergence.md M9).
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
        try await engine(identifiedBy: try FolderIdentity(of: root), at: root, knownKey: knownKey)
    }

    /// Gives the engine of the current board of a session, as ``engine(ofBoardAt:knownKey:)`` does with no known key.
    /// When the key of the board is a board ID (a board outside git), the host also watches the folder of the board
    /// for a `git init` (``watchGitInit(of:)``, divergence.md M9).
    ///
    /// - Parameter root: The root directory of the board: the top folder of the worktree, or the folder of a board
    ///   outside git.
    /// - Returns: The engine.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the folder cannot be read. An error of the load.
    func engine(ofSessionBoardAt root: URL) async throws -> BoardEngine {
        let engine = try await engine(ofBoardAt: root)
        await watchGitInit(of: engine)
        return engine
    }

    /// Gives the engine of a related board, as ``engine(ofBoardAt:knownKey:)`` does, and marks a board that cannot
    /// load (divergence.md Q7).
    ///
    /// When the load fails, the host keeps the error and starts a file watcher on the board. Each later related load
    /// of the board gives the same error with no read of a file, until the watcher sees a change of the board: the
    /// next load after the change reads the files again. A load that the host cannot repeat with the same result is
    /// not marked: an incompatible (Rust) board, whose error stops each call (divergence.md Q6), and a load that a
    /// cancel stopped.
    ///
    /// - Parameters:
    ///   - root: The root directory of the repo of the board.
    ///   - knownKey: The key of the board when the caller knows it, or `nil` to read it from git.
    /// - Returns: The engine.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the folder cannot be read. An error of the load, or
    ///   the kept error of the last load while the board did not change.
    func relatedEngine(ofBoardAt root: URL, knownKey: BoardKey?) async throws -> BoardEngine {
        let identity = try FolderIdentity(of: root)
        if engines[identity] == nil, let board = unloadableBoards[identity] {
            throw board.error
        }
        do {
            return try await engine(identifiedBy: identity, at: root, knownKey: knownKey)
        } catch {
            await markUnloadable(identity, at: root, failingWith: error)
            throw error
        }
    }

    /// Gives the engine of a board by the identity of its repo directory, and loads the board when no engine has it
    /// yet.
    ///
    /// A caller that knows the key read it from git after the engine loaded: the scan, or a path ref whose record
    /// expired. When that key is not the key of the engine, the engine takes it (``BoardEngine/changeKey(to:)``,
    /// divergence.md M9). For example, a `git init` in the folder of a loaded board outside git gives the git key with
    /// no restart.
    ///
    /// - Parameters:
    ///   - identity: The identity of the root directory.
    ///   - root: The root directory of the repo of the board.
    ///   - knownKey: The key of the board when the caller knows it, or `nil` to read it from git.
    /// - Returns: The engine.
    /// - Throws: An error of the load.
    private func engine(
        identifiedBy identity: FolderIdentity,
        at root: URL,
        knownKey: BoardKey?
    ) async throws -> BoardEngine {
        let engine =
            switch engines[identity] {
            case .loaded(let engine): engine
            case .loading(let load): try await load.value
            case nil: try await startLoad(ofBoardAt: root, identity: identity, knownKey: knownKey)
            }
        if let knownKey {
            await engine.changeKey(to: knownKey)
        }
        return engine
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
            folderStreams: folderStreams,
            publish: { [weak self] changed in await self?.publish(changed) },
            reportRetirement: { [weak self] engine in await self?.retire(engine) }
        )
        let load = Task { try await BoardEngine.load(request) }
        engines[identity] = .loading(load)
        do {
            let engine = try await load.value
            engines[identity] = .loaded(engine)
            if isClosed {
                await engine.close()
            }
            await unloadableBoards.removeValue(forKey: identity)?.watch.end()
            await retireEngines(replacedBy: engine)
            return engine
        } catch {
            engines[identity] = nil
            throw error
        }
    }

    // MARK: - Replaced repos

    /// Lets go of each loaded engine whose folder is not at its root path any more, because a new engine loaded the
    /// folder that is now at that path (divergence.md §16, Gap 6). For example, a user moved the repo away and made a
    /// new repo at the same path.
    ///
    /// - Parameter engine: The engine of the folder that is now at the path.
    private func retireEngines(replacedBy engine: BoardEngine) async {
        let path = engine.root.canonicalPath
        let replaced = loadedEngines.filter { other in
            other.identity != engine.identity && other.root.canonicalPath == path && !other.isAtRoot
        }
        for other in replaced {
            await retire(other)
        }
    }

    /// Lets go of an engine whose folder is not at its root path any more (divergence.md §16, Gap 6). The host takes
    /// the engine out of its table, and the engine stops its file watcher with ``BoardEngine/retire()``. Thus no engine
    /// of the host reads the files of the new folder at the path except the engine of that folder. A later load of
    /// the old folder at its new path makes a new engine with the new root path.
    ///
    /// Each session view that still holds the engine puts the engine of the path in its place at its next call or
    /// change, and moves its subscribers to it (``KanbanGraph``). The feed of the retired engine stays open for that
    /// move.
    ///
    /// The engine calls this method while it holds its serial gate, so the method waits for no engine gate:
    /// ``BoardEngine/retire()`` does not wait for the task of the watch. A second call does nothing. The watch of a
    /// `git init` in the folder of the engine stops too (``watchGitInit(of:)``).
    ///
    /// - Parameter engine: The engine whose folder moved away from its root path.
    func retire(_ engine: BoardEngine) async {
        if isLoaded(engine) {
            engines[engine.identity] = nil
            retiredEngines.removeGoneObjects()
            retiredEngines.append(Weak(object: engine))
        }
        await bareBoardWatches.removeValue(forKey: engine.identity)?.stop()
        await engine.retire()
    }

    // MARK: - Boards that cannot load

    /// Marks a related board whose load failed, and starts a file watcher on it, so that each later related load
    /// gives the same error until the board changes (divergence.md Q7). A closed host starts no watcher, so it marks
    /// nothing. When the watcher cannot start, the board is not marked, and the host records it with swift-log.
    /// The host can run other calls while the watcher starts. Thus the host checks the state again after the start,
    /// and stops the new watcher when a close, a parallel mark, or a load came first.
    ///
    /// - Parameters:
    ///   - identity: The identity of the repo directory of the board.
    ///   - root: The root directory of the repo of the board.
    ///   - error: The error of the load.
    private func markUnloadable(_ identity: FolderIdentity, at root: URL, failingWith error: any Error) async {
        guard
            !isClosed,
            unloadableBoards[identity] == nil,
            KanbanError(callFailure: error) == nil,
            !Task.isCancelled
        else {
            return
        }
        let watch: BoardWatch
        do {
            watch = try await makeUnloadableWatch(of: root, identity)
        } catch {
            Self.logWatchFailure(
                "The host cannot watch a board that could not load, so each call loads the board again",
                path: root.path,
                error: error
            )
            return
        }
        guard !isClosed, unloadableBoards[identity] == nil, engines[identity] == nil else {
            await watch.end()
            return
        }
        unloadableBoards[identity] = UnloadableBoard(error: error, watch: watch)
    }

    /// Makes the watch of a board that could not load: a file watcher on its `.kanban/` directory, or on its repo
    /// directory when `.kanban/` is not there, and a task that gives each batch to
    /// ``unloadableBoardDidChange(_:at:)``. The task holds the host weakly.
    ///
    /// - Parameters:
    ///   - root: The root directory of the repo of the board.
    ///   - identity: The identity of the repo directory of the board.
    /// - Returns: The watch.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when the watcher cannot start.
    private func makeUnloadableWatch(
        of root: URL,
        _ identity: FolderIdentity
    ) async throws(BoardWatcherError) -> BoardWatch {
        let started = try await BoardWatcher.started(onBoardAt: root, in: folderStreams)
        return BoardWatch(of: started, heldWeaklyBy: self) { host, _ in
            await host.unloadableBoardDidChange(identity, at: root)
        }
    }

    /// Forgets the mark of a board that could not load, because its file watcher saw a change: the next related load
    /// of the board reads its files again. The watcher then stops.
    ///
    /// - Parameters:
    ///   - identity: The identity of the repo directory of the board.
    ///   - root: The root directory of the repo of the board.
    private func unloadableBoardDidChange(_ identity: FolderIdentity, at root: URL) async {
        guard let board = unloadableBoards.removeValue(forKey: identity) else {
            return
        }
        configuration.loadObserver?.unreadableBoardDidChange(at: root)
        await board.watch.watcher.stop()
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

    /// Gives the copy of each loaded board with a key, for `undo` and `redo` of a transaction that changed a board with
    /// that key (plan.md §6.5, many boards; divergence.md X5). Each worktree of a repo has its own board with the same
    /// key, so one key can give more than one copy. A board that is still loading is not in the list.
    ///
    /// - Parameter key: The key, with the host in lowercase. Each name of a board matches (``BoardNames``,
    ///   divergence.md M9), so an old git key in the `boards` value of an old event still finds its board.
    /// - Returns: The copies, in the sort order of the path of their root directory.
    func loadedCopies(withKey key: String) async -> [BoardCopy] {
        var copies: [BoardCopy] = []
        for engine in loadedEngines {
            let copy = await engine.session.copy(at: engine.root)
            if copy.names.contains(key) {
                copies.append(copy)
            }
        }
        return copies.sorted { lhs, rhs in lhs.directory.canonicalPath < rhs.directory.canonicalPath }
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

    /// Gives the index of the last scan of the places around a repo, current or not, or `nil` before the first scan
    /// (plan.md §6.6, index life). A ref that this index has resolves with no scan.
    ///
    /// - Parameter root: The top folder of the worktree of the current board of a session.
    /// - Returns: The index.
    func scanIndex(around root: URL) -> BoardIndex? {
        scanCache.index(ofPlaces: Self.placesKey(of: locator.places(around: root)))
    }

    /// Gives the current index of the places around a repo, and scans only when the index is not current
    /// (divergence.md §16, Gap 1).
    ///
    /// The index is current after a scan while the file watcher of each place runs, until the watcher sees a new or
    /// removed repo folder, a new `.git`, a changed git config, or a new board log in a place. Thus a ref that names no
    /// board of a current index is not found, with no scan and no `git`. A new scan reuses each key that no change
    /// made unknown, and does not read again a key whose read failed.
    ///
    /// One scan of the places runs at a time. A call that needs the index while a scan of the same places runs, for
    /// example a parallel request of the same GraphQL call, waits for that scan and uses its index. When that scan
    /// gives no index, for example because a cancel stopped it, the waiting call checks the index again, and scans
    /// when the index is still not current.
    ///
    /// - Parameter root: The top folder of the worktree of the current board of a session.
    /// - Returns: The current index.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during a scan, or during the
    ///   wait for a running scan. Then the host keeps the earlier index.
    func currentScanIndex(around root: URL) async throws(BoardKeyError) -> BoardIndex {
        let places = locator.places(around: root)
        let key = Self.placesKey(of: places)
        while true {
            if isWatching(key), let index = scanCache.currentIndex(ofPlaces: key) {
                return index
            }
            guard let running = runningScans[key] else {
                return try await rescan(around: root, inPlaces: places)
            }
            if let index = try await index(of: running, inPlaces: places) {
                return index
            }
        }
    }

    /// Waits for the index of a scan of the places that runs now.
    ///
    /// - Parameters:
    ///   - running: The scan that runs now.
    ///   - places: The places of the scan, in scan order.
    /// - Returns: The index of the scan, or `nil` when the scan gave no index.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during the wait. The scan goes
    ///   on for the other calls.
    private func index(of running: RunningScan, inPlaces places: [URL]) async throws(BoardKeyError) -> BoardIndex? {
        configuration.scanObserver?.scanWaitDidStart(inPlaces: places)
        if let index = await running.index() {
            return index
        }
        guard !Task.isCancelled else {
            throw .gitCancelled(arguments: [])
        }
        return nil
    }

    /// Scans the places around a repo for repos, and records the new index. While the scan runs, each other call
    /// that needs the index of the places waits for it (``runningScans``).
    ///
    /// - Parameters:
    ///   - root: The top folder of the worktree of the current board of a session.
    ///   - places: The places of the scan, in scan order.
    /// - Returns: The new index.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during the scan. Then the host
    ///   keeps the earlier index.
    private func rescan(around root: URL, inPlaces places: [URL]) async throws(BoardKeyError) -> BoardIndex {
        let key = Self.placesKey(of: places)
        let running = RunningScan()
        runningScans[key] = running
        let outcome = await scanOutcome(around: root, inPlaces: places)
        runningScans[key] = nil
        running.finish(giving: try? outcome.get())
        return try outcome.get()
    }

    /// Runs one scan of the places around a repo, and records the new index in the scan cache. The file watcher of
    /// each place starts before the scan, so a change during the scan is not lost.
    ///
    /// - Parameters:
    ///   - root: The top folder of the worktree of the current board of a session.
    ///   - places: The places of the scan, in scan order.
    /// - Returns: The new index, or ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during the
    ///   scan. Then the cache keeps the earlier index.
    private func scanOutcome(around root: URL, inPlaces places: [URL]) async -> Result<BoardIndex, BoardKeyError> {
        let key = Self.placesKey(of: places)
        await watch(places)
        configuration.scanObserver?.scanDidStart(inPlaces: places)
        let earlier = scanCache.beginScan(ofPlaces: key)
        do {
            let scanned = try await locator.scan(
                around: root,
                reusing: earlier,
                readingKeysWith: configuration.boardKeyReader
            )
            return .success(scanCache.finishScan(scanned, ofPlaces: key, isWatched: isWatching(key)))
        } catch {
            scanCache.abandonScan(ofPlaces: key)
            return .failure(error)
        }
    }

    /// Starts the file watcher of each place that has none yet. A closed host starts no watcher. A place whose
    /// watcher cannot start has no watcher: its indexes are never current, so each call that needs more than the
    /// index scans again, and the host records the failure with swift-log. The host can run other calls while a
    /// watcher starts, so it checks the state again after each start (``keepPlaceWatch(_:at:)``). When the start of
    /// the watcher of a place runs now, a second call waits for that start. It does not start a second watcher.
    ///
    /// - Parameter places: The places.
    private func watch(_ places: [URL]) async {
        for place in places where placeWatches[place.canonicalPath] == nil {
            guard !isClosed else {
                return
            }
            let path = place.canonicalPath
            if let start = placeWatchStarts[path] {
                await start.value
                continue
            }
            let start = Task { await self.startPlaceWatch(of: place) }
            placeWatchStarts[path] = start
            await start.value
            placeWatchStarts[path] = nil
        }
    }

    /// Starts the file watcher of one scan place and keeps it (``keepPlaceWatch(_:at:)``). When the watcher cannot
    /// start, the host records the failure with swift-log.
    ///
    /// - Parameter place: The place.
    private func startPlaceWatch(of place: URL) async {
        do {
            await keepPlaceWatch(try await makePlaceWatch(of: place), at: place.canonicalPath)
        } catch {
            Self.logWatchFailure(
                "The host cannot watch a scan place, so a board ref that names no board scans again",
                path: place.path,
                error: error
            )
        }
    }

    /// Keeps the file watcher of a scan place that started. A close or a parallel call can come during the start:
    /// then the host stops the new watcher, so that each place has one watcher, and no watcher runs after ``close()``.
    ///
    /// - Parameters:
    ///   - watch: The watch that started.
    ///   - path: The canonical path of the place.
    private func keepPlaceWatch(_ watch: BoardWatch, at path: String) async {
        guard !isClosed, placeWatches[path] == nil else {
            await watch.end()
            return
        }
        placeWatches[path] = watch
    }

    /// Makes the watch of a scan place: a file watcher on the place, and a task that gives each of its batches to
    /// ``placeDidChange(_:in:)``. The task holds the host weakly, so the watcher does not keep the host alive.
    ///
    /// - Parameter place: The place.
    /// - Returns: The watch.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when the watcher cannot start.
    private func makePlaceWatch(of place: URL) async throws(BoardWatcherError) -> BoardWatch {
        let watched = WatchedPlace(watching: place)
        return try await makeFolderWatch(of: place) { host, paths in
            await host.placeDidChange(watched, in: paths)
        }
    }

    /// Applies the changes of one batch of the file watcher of a scan place to the scan indexes.
    ///
    /// - Parameters:
    ///   - place: The place.
    ///   - paths: The changed paths of the batch.
    private func placeDidChange(_ place: WatchedPlace, in paths: [URL]) {
        for change in place.changes(in: paths) {
            scanCache.apply(change, inPlace: place.path)
            configuration.scanObserver?.scanPlaceDidChange(change)
        }
    }

    /// Tells if each place of a list of scan places has a running file watcher, so that a change reaches the cache.
    ///
    /// - Parameter places: The canonical path of each place.
    /// - Returns: `true` when each place has a watcher.
    private func isWatching(_ places: [String]) -> Bool {
        places.allSatisfy { place in placeWatches[place] != nil }
    }

    /// Gives the key of a list of scan places in the table of the scan indexes.
    ///
    /// - Parameter places: The places, in scan order.
    /// - Returns: The canonical path of each place, in scan order.
    private static func placesKey(of places: [URL]) -> [String] {
        places.map(\.canonicalPath)
    }

    // MARK: - Folders that a path ref named

    /// Gives what git tells about the folder that a path ref names: from memory after the first call with the folder,
    /// so that a later call runs no `git` (divergence.md §16, Gap 1).
    ///
    /// The first call reads the mark of the folder (``RepoMark``), then reads git with
    /// ``BoardLocator/board(ofFolderAt:readingKeysWith:findingTopsWith:)``, and records the result with
    /// ``recordBoard(_:ofFolderAt:folderMark:)``. The mark comes before the read of git, so that a change during the
    /// read makes the record out of date. A board that it records also resolves by its key in a later ref
    /// (``pathCopy(namedBy:)``, divergence.md X4).
    ///
    /// - Parameter folder: The folder, from ``BoardLocator/folder(namedBy:currentRoot:)``.
    /// - Returns: The board of the folder (a board in a git repo, or a board outside git), or
    ///   ``FolderBoard/unreadableKey(top:)``.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during a read of git. Each
    ///   other ``BoardKeyError`` of the read of the top folder. The host records no result then.
    func board(ofFolderAt folder: URL) async throws(BoardKeyError) -> FolderBoard {
        if let known = knownFolders[folder.canonicalPath] {
            return known.record.board
        }
        let mark = RepoMark(ofRepoAt: folder)
        let board = try await BoardLocator.board(
            ofFolderAt: folder,
            readingKeysWith: configuration.boardKeyReader,
            findingTopsWith: configuration.topReader
        )
        await recordBoard(board, ofFolderAt: folder, folderMark: mark)
        return board
    }

    /// Records what git told about a folder that a path ref named. A path can name a folder outside the scan places,
    /// and the scan index does not have such a folder.
    ///
    /// The record starts a file watcher on the parent folder of the watched repo
    /// (``FolderBoard/watchedRepo(ofFolderAt:)``). The host forgets the record when the watcher sees a change that makes
    /// it out of date (``PathRefRecord/isExpired(by:)``): for example a `git init` in the folder, or a new `origin`.
    /// Thus the next call reads git again. A late event of files that did not change since the record keeps the
    /// record. The watcher sees only the watched repo: a new repo in a folder between the named folder and the top
    /// folder of its worktree, or in a parent folder of a folder that is not in a git repo, does not show.
    ///
    /// The mark of the record is `mark` when the watched repo is the folder itself. Else the watched repo is the top
    /// folder of the worktree, which is known only after the read of git, and the record reads its mark now
    /// (``PathRefRecord/init(board:ofFolderAt:folderMark:)``).
    ///
    /// A second record of the same folder with the same watched repo replaces the result and its mark, and keeps the
    /// watcher. A record with a different watched repo replaces the watcher too. A closed host records nothing, because
    /// no watcher can keep the result current. When the watcher cannot start, the host records nothing, and it records
    /// the failure with swift-log. The host can run other calls while the watcher starts, so it checks the state again
    /// after the start (``keepKnownFolder(_:at:)``). Then the new watcher gives one compare batch, so the record compares
    /// the mark of its watched repo one time: a change between the read of git and the start of the watcher gives no
    /// event, and the compare finds it (``BoardWatcher/compareEachFile()``).
    ///
    /// - Parameters:
    ///   - board: What git told about the folder.
    ///   - folder: The folder that the path ref named.
    ///   - mark: The mark of the folder, read before the read of git.
    private func recordBoard(_ board: FolderBoard, ofFolderAt folder: URL, folderMark mark: RepoMark?) async {
        let path = folder.canonicalPath
        let record = PathRefRecord(board: board, ofFolderAt: folder, folderMark: mark)
        if knownFolders[path]?.record.repo == record.repo {
            knownFolders[path]?.record = record
            return
        }
        let repo = board.watchedRepo(ofFolderAt: folder)
        let replaced = knownFolders.removeValue(forKey: path)
        if !isClosed {
            do {
                let watch = try await makeKnownFolderWatch(of: path, watchingRepoAt: repo)
                await keepKnownFolder(KnownFolder(record: record, watch: watch), at: path)
                watch.watcher.compareEachFile()
            } catch {
                Self.logWatchFailure(
                    "The host cannot watch a folder that a path ref named, so each call with the path ref runs git",
                    path: repo.path,
                    error: error
                )
            }
        }
        await replaced?.watch.end()
    }

    /// Keeps what git told about a folder that a path ref named, with its file watcher that started. A close or a
    /// parallel record can come during the start. After a close, the host stops the new watcher and records nothing.
    /// After a parallel record, the new record replaces it, and the host stops the watcher of the replaced record.
    ///
    /// - Parameters:
    ///   - known: The record and its watcher.
    ///   - path: The canonical path of the folder that the path ref named.
    private func keepKnownFolder(_ known: KnownFolder, at path: String) async {
        guard !isClosed else {
            await known.watch.end()
            return
        }
        await knownFolders.updateValue(known, forKey: path)?.watch.end()
    }

    /// Makes the watch of a folder that a path ref named: a file watcher on the parent folder of its watched repo, and a
    /// task that gives each batch to ``knownFolderDidChange(_:in:at:)``. The task holds the host weakly.
    ///
    /// - Parameters:
    ///   - path: The canonical path of the folder that the path ref named.
    ///   - repo: The watched repo folder.
    /// - Returns: The watch.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when the watcher cannot start.
    private func makeKnownFolderWatch(
        of path: String,
        watchingRepoAt repo: URL
    ) async throws(BoardWatcherError) -> BoardWatch {
        try await makeParentWatch(ofRepoAt: repo) { host, parent, paths in
            await host.knownFolderDidChange(path, in: parent, at: paths)
        }
    }

    /// Forgets what git told about a folder that a path ref named, when one batch of its file watcher makes it out of
    /// date. The watcher then stops.
    ///
    /// - Parameters:
    ///   - path: The canonical path of the folder that the path ref named.
    ///   - parent: The watched parent folder of the watched repo.
    ///   - paths: The changed paths of the batch.
    private func knownFolderDidChange(_ path: String, in parent: WatchedPlace, at paths: [URL]) async {
        guard let known = knownFolders[path],
            let change = parent.changes(in: paths).first(where: { change in
                known.record.isExpired(by: change)
            })
        else {
            return
        }
        knownFolders[path] = nil
        configuration.scanObserver?.pathRefDidChange(change)
        await known.watch.watcher.stop()
    }

    /// Finds the copy that a key ref names among the boards that calls reached by a path (divergence.md X4). Copies
    /// with the same key obey the rule of the scan: the key gives the first copy in a fixed order, here the sort order
    /// of the canonical path of the top folder of its worktree (plan.md §6.6, many copies of one repo). A copy whose
    /// folder is not there any more is not a match. Each name of a board matches (divergence.md M9). The record of a
    /// folder keeps no file watcher on the board log, so the match reads the names from the board log now: a board ID
    /// that a later write added matches too.
    ///
    /// - Parameter reference: The board ref: a name of a board, or the URI of a board. White space at the two ends is
    ///   ignored.
    /// - Returns: The copy, or `nil` when the ref is not a key, or when no copy has the name.
    func pathCopy(namedBy reference: String) -> BoardCopy? {
        guard let key = BoardIndex.boardKey(in: reference.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let copies = knownFolders.values.compactMap { known in
            known.record.board.copy.map { copy in (path: known.record.repo, copy: copy) }
        }
        return copies.sorted { lhs, rhs in lhs.path < rhs.path }.lazy.map(\.copy).first { copy in
            FileManager.default.fileExists(atPath: copy.directory.path)
                && BoardNames.read(fromRepoAt: copy.directory, key: copy.key).contains(key)
        }
    }

    // MARK: - Current boards outside git

    /// Watches the folder of the current board of a session outside git for a `git init`, so that the board takes the
    /// git key with no restart, and a read runs no `git` (divergence.md M9).
    ///
    /// The watch is a file watcher on the parent folder of the root directory of the board
    /// (``bareBoardDidChange(_:in:at:)``). After the start, the watcher gives one compare batch, so a `git init`
    /// between the key read of the load and the start of the watcher shows too.
    ///
    /// The host watches only an engine whose key is a board ID, and it starts one watcher for each engine. A closed
    /// host starts no watcher. When the watcher cannot start, the board keeps its board ID key after a `git init`, and
    /// the host records the failure with swift-log. The host can run other calls while the watcher starts, so it
    /// checks the state again after the start. It stops the new watcher when a close, a parallel start, or a retire
    /// came first.
    ///
    /// - Parameter engine: The engine of the current board of a session.
    private func watchGitInit(of engine: BoardEngine) async {
        guard !isClosed, bareBoardWatches[engine.identity] == nil, await engine.key.isBoardID else {
            return
        }
        let identity = engine.identity
        let watch: BoardWatch
        do {
            watch = try await makeParentWatch(ofRepoAt: engine.root) { host, parent, paths in
                await host.bareBoardDidChange(identity, in: parent, at: paths)
            }
        } catch {
            Self.logWatchFailure(
                "The host cannot watch the folder of a board outside git, so a git init does not change its key",
                path: engine.root.path,
                error: error
            )
            return
        }
        guard !isClosed, bareBoardWatches[identity] == nil, isLoaded(engine) else {
            await watch.end()
            return
        }
        bareBoardWatches[identity] = watch
        watch.watcher.compareEachFile()
    }

    /// Gives the current board of a session outside git the key that git gives now, after one batch of the watcher of
    /// its parent folder (divergence.md M9).
    ///
    /// The host reads the key only when the batch can show a `git init` in the root directory of the board
    /// (``gitInitChange(in:ofBoardAt:inside:)``), and the root directory has a `.git` entry now. A change of a
    /// different folder in the parent folder runs no `git`. When git gives a git key, the engine takes it
    /// (``BoardEngine/changeKey(to:)``), the watcher stops, and the scan observer gets the change. When git still gives
    /// a board ID, or the read fails, the watcher stays, so that a later change reads the key again.
    ///
    /// The method runs in the task of the watch, so it stops the watcher with no wait for the end of that task
    /// (``BoardWatch/stop()``).
    ///
    /// - Parameters:
    ///   - identity: The identity of the root directory of the board.
    ///   - parent: The watched parent folder of the root directory.
    ///   - paths: The changed paths of the batch.
    private func bareBoardDidChange(_ identity: FolderIdentity, in parent: WatchedPlace, at paths: [URL]) async {
        guard
            bareBoardWatches[identity] != nil,
            case .loaded(let engine) = engines[identity],
            let change = Self.gitInitChange(in: parent.changes(in: paths), ofBoardAt: engine.root, inside: parent),
            BoardLocator.hasGitEntry(engine.root),
            let key = await gitKey(ofBoardAt: engine.root)
        else {
            return
        }
        await engine.changeKey(to: key)
        await bareBoardWatches.removeValue(forKey: identity)?.stop()
        configuration.scanObserver?.bareBoardDidChange(change)
    }

    /// Gives the first change of a batch that can show a `git init` in the root directory of a board: a change of the
    /// root directory, of its `.git` entry, or of its git config, or a change of the parent folder itself (for
    /// example the compare batch after the start of the watcher).
    ///
    /// - Parameters:
    ///   - changes: The changes of the batch.
    ///   - root: The root directory of the board.
    ///   - parent: The watched parent folder of the root directory.
    /// - Returns: The change, or `nil` when no change of the batch can show a `git init` in the root directory.
    private static func gitInitChange(
        in changes: [ScanChange],
        ofBoardAt root: URL,
        inside parent: WatchedPlace
    ) -> ScanChange? {
        changes.first { change in change == .repo(root.canonicalPath) || change == .place(parent.path) }
    }

    /// Reads the key of a board outside git again, after a change of its folder.
    ///
    /// - Parameter root: The root directory of the board.
    /// - Returns: The git key, or `nil` when git gives no git key: the folder is still outside git, or the read failed.
    ///   The host records a failed read with swift-log.
    private func gitKey(ofBoardAt root: URL) async -> BoardKey? {
        do {
            let key = try await configuration.boardKeyReader(root)
            return key.isBoardID ? nil : key
        } catch {
            Log.kanban.warning(
                "The host cannot read the git key of a board outside git, so the board keeps its board ID key",
                metadata: ["path": "\(root.path)", "error": "\(error)"]
            )
            return nil
        }
    }

    /// Tells whether an engine is the loaded engine of its folder in the table of the host.
    ///
    /// - Parameter engine: The engine.
    /// - Returns: `true` when the table has this engine, loaded, for the identity of its folder.
    private func isLoaded(_ engine: BoardEngine) -> Bool {
        guard case .loaded(let loaded) = engines[engine.identity] else {
            return false
        }
        return loaded === engine
    }

    // MARK: - File watches

    /// Starts a file watcher on the parent folder of a repo folder, and makes its watch: the watcher of a folder that a
    /// path ref named, or of the folder of a current board outside git. Each batch goes to a receiver with the watched
    /// parent folder, so that the receiver can read the changes of the batch (``WatchedPlace/changes(in:)``). The
    /// watch holds the host weakly.
    ///
    /// - Parameters:
    ///   - repo: The repo folder.
    ///   - receive: Gets the host, the watched parent folder, and the changed paths of each batch.
    /// - Returns: The watch.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when the watcher cannot start.
    private func makeParentWatch(
        ofRepoAt repo: URL,
        sendingBatchesTo receive: @escaping @Sendable (KanbanHost, WatchedPlace, [URL]) async -> Void
    ) async throws(BoardWatcherError) -> BoardWatch {
        let parent = repo.deletingLastPathComponent()
        let watched = WatchedPlace(watching: parent)
        return try await makeFolderWatch(of: parent) { host, paths in
            await receive(host, watched, paths)
        }
    }

    /// Starts a file watcher on one folder, and makes its watch with
    /// ``BoardWatch/init(of:heldWeaklyBy:sendingBatchesTo:)``. The watch holds the host weakly.
    ///
    /// - Parameters:
    ///   - folder: The folder to watch.
    ///   - receive: Gets the host and the changed paths of each batch.
    /// - Returns: The watch.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when the watcher cannot start.
    private func makeFolderWatch(
        of folder: URL,
        sendingBatchesTo receive: @escaping @Sendable (KanbanHost, [URL]) async -> Void
    ) async throws(BoardWatcherError) -> BoardWatch {
        let started = try await StartedWatcher(watching: folder, in: folderStreams)
        return BoardWatch(of: started, heldWeaklyBy: self, sendingBatchesTo: receive)
    }

    /// Records with swift-log that a file watcher of the host cannot start.
    ///
    /// - Parameters:
    ///   - message: What the host cannot do, and the result of the failure.
    ///   - path: The path of the folder that the watcher was to watch.
    ///   - error: The error of the start.
    private static func logWatchFailure(_ message: Logger.Message, path: String, error: any Error) {
        Log.kanban.warning(message, metadata: ["path": "\(path)", "error": "\(error)"])
    }

    // MARK: - Views

    /// Records a session view, so that it gets the changes of the boards. A view records itself when it finds its
    /// board and when a subscription of the view starts. A second record of a view changes nothing.
    ///
    /// - Parameter view: The view.
    func register(_ view: KanbanGraph) {
        views[ObjectIdentifier(view)] = Weak(object: view)
    }

    /// Forgets a session view: it gets no more changes.
    ///
    /// - Parameter view: The view.
    func unregister(_ view: KanbanGraph) {
        views[ObjectIdentifier(view)] = nil
    }

    /// Tells whether a session view gets the changes of the boards. A test reads it to prove that a subscription
    /// registers its view before it adds its subscriber.
    ///
    /// - Parameter view: The view.
    /// - Returns: `true` when the host has the view registered.
    func hasView(_ view: KanbanGraph) -> Bool {
        views[ObjectIdentifier(view)]?.object === view
    }

    /// Sends the changes of some boards to each session view, so that each view sends them to its own subscribers
    /// (plan.md §6.7).
    ///
    /// - Parameter changed: The changes of each board that changed, by the canonical path of its repo directory.
    func publish(_ changed: [String: BoardChanges]) async {
        views.removeGoneObjects()
        for view in views.values.compactMap(\.object) {
            await view.publish(changed)
        }
    }

    // MARK: - Close

    /// Stops the file watcher of each board, of each scan place, of each board that could not load, of each folder
    /// that a path ref named, and of the folder of each current board outside git, and ends each subscription. The
    /// boards stay in memory, and a board that loads later has no watcher. A `git init` in the folder of a board
    /// outside git then does not change its key. With no watcher on its places, a scan index is not current any more.
    /// A board that could not load loads again at its next related load. The host forgets what git told about each
    /// folder that a path ref named: a ref with the key of such a board does not find it, and each path ref reads git
    /// again. The shared host stays open for the life of the process; a test closes its own host. Each retired engine
    /// that is still alive closes too, so that its subscriptions end.
    func close() async {
        isClosed = true
        let watches =
            Array(placeWatches.values) + unloadableBoards.values.map(\.watch) + knownFolders.values.map(\.watch)
            + Array(bareBoardWatches.values)
        placeWatches = [:]
        unloadableBoards = [:]
        knownFolders = [:]
        bareBoardWatches = [:]
        for watch in watches {
            await watch.end()
        }
        for slot in engines.values {
            switch slot {
            case .loaded(let engine):
                await engine.close()
            case .loading(let load):
                await (try? load.value)?.close()
            }
        }
        let retired = retiredEngines.compactMap(\.object)
        retiredEngines = []
        for engine in retired {
            await engine.close()
        }
    }
}

// MARK: - Configuration

/// The parts of a ``KanbanHost`` that a test can change: the readers of git, the clock, the ULID source, the
/// locator, the embedder, the writer of the logs, the observers, and the FSEvents calls.
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

    /// Gets a call when a scan for the related boards starts, when the file watcher of a scan place sees a change,
    /// when the host forgets what git told about a folder that a path ref named, and when a current board outside git
    /// gets its git key, or `nil` for no calls.
    let scanObserver: (any BoardScanObserver)?

    /// The FSEvents calls of the file watchers of the host. A test gives a fake, for example a service whose stream
    /// start waits.
    let folderEvents: any FolderEventService

    /// The board IDs that the host gave to the boards outside git whose log has no board ID yet (divergence.md M9).
    let bareBoardIDs = BareBoardIDs(mintingFrom: SystemULIDSource())

    /// Reads the key of the board of a root directory: the git key from ``keyReader``, or the board ID of a board
    /// outside git when git tells that the folder is not in a git repo (divergence.md M9). The engine, the scan, and
    /// the path refs read each key with it.
    var boardKeyReader: BoardKeyReader {
        { [keyReader, bareBoardIDs] root throws(BoardKeyError) in
            do throws(BoardKeyError) {
                return try await keyReader(root)
            } catch .notARepo {
                return bareBoardIDs.key(ofBoardAt: root)
            }
        }
    }

    /// Makes a configuration. Each default is the value of the process: git, the system clock, random ULIDs, the log
    /// files, and the FSEvents service of the system.
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
    ///   - scanObserver: Gets a call when a scan starts, when the file watcher of a scan place sees a change, when the
    ///     host forgets what git told about a folder that a path ref named, and when a current board outside git gets
    ///     its git key, or `nil` for no calls.
    ///   - folderEvents: The FSEvents calls of the file watchers of the host.
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
        workerObserver: (any LoaderWorkerObserver)? = nil,
        scanObserver: (any BoardScanObserver)? = nil,
        folderEvents: any FolderEventService = SystemFolderEvents()
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
        self.scanObserver = scanObserver
        self.folderEvents = folderEvents
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

/// A related board that could not load (divergence.md Q7): the error of its last load, and the file watcher whose
/// first batch makes the host load the board again.
private struct UnloadableBoard {
    /// The error of the last load of the board.
    let error: any Error

    /// The file watcher of the `.kanban/` directory of the board, or of its repo directory.
    let watch: BoardWatch
}

/// A folder that a path ref named (divergence.md §16, Gap 1; divergence.md X4): what git told about it, and the file
/// watcher whose change of the watched repo makes the host forget it.
private struct KnownFolder {
    /// What git told about the folder, its watched repo, and the mark of its watched repo.
    var record: PathRefRecord

    /// The file watcher of the parent folder of the watched repo folder.
    let watch: BoardWatch
}

/// An object that the host does not keep alive: a session view, or a retired engine (divergence.md §16, Gap 6).
private struct Weak<Object: AnyObject> {
    /// The object, or `nil` after the object is gone.
    weak var object: Object?

    /// `true` while the object is alive.
    var isAlive: Bool {
        object != nil
    }
}

extension Array {
    /// Removes each entry whose object is gone, so that the list of objects that the host does not keep alive does
    /// not grow with dead entries.
    fileprivate mutating func removeGoneObjects<Object>() where Element == Weak<Object> {
        removeAll { entry in !entry.isAlive }
    }
}

extension Dictionary {
    /// Removes each entry whose object is gone, so that the table of objects that the host does not keep alive does
    /// not grow with dead entries.
    fileprivate mutating func removeGoneObjects<Object>() where Value == Weak<Object> {
        self = filter { _, entry in entry.isAlive }
    }
}
