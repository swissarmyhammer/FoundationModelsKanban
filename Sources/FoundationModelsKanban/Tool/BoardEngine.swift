import Foundation
import FoundationModelsExtras

/// Sends the changes of the live graphs of some boards to the session views of the process (plan.md §6.7,
/// divergence.md §16). The changes are by the canonical path of the repo directory of each board.
typealias ChangePublisher = @Sendable ([String: BoardChanges]) async -> Void

/// Tells the host that an engine retired because its folder moved away from its root path, so that the host lets go
/// of the engine (divergence.md §16, Gap 6). The call does not wait for an engine gate.
typealias EngineRetirement = @Sendable (BoardEngine) async -> Void

/// Gets a call when the file load of a board starts and when it ends.
///
/// A test uses it to count the loads of a board, to prove that the key read and the file load run at the same time
/// (divergence.md §16, L1), and to make a load slow, so that it can prove that two related boards load at the same
/// time (divergence.md §16, L5).
protocol BoardLoadObserver: Sendable {
    /// Tells that the file load of a board started. The load waits until this method returns.
    ///
    /// - Parameter root: The root directory of the repo of the board.
    func boardLoadDidStart(at root: URL) async

    /// Tells that the file load of a board ended.
    ///
    /// - Parameter root: The root directory of the repo of the board.
    func boardLoadDidFinish(at root: URL)

    /// Tells that the merge of the event lists of a loaded board starts. The merge waits until this method returns.
    ///
    /// A test uses it to hold the merge, so that it can prove that the search update starts before the merge ends
    /// (divergence.md §16, L4).
    ///
    /// - Parameter root: The root directory of the repo of the board.
    func boardEventsWillMerge(at root: URL) async

    /// Tells that the file watcher of a board that could not load saw a change, so the next call that reaches the
    /// board loads it again (divergence.md Q7).
    ///
    /// A test uses it to wait for the change, and then for its effect.
    ///
    /// - Parameter root: The root directory of the repo of the board.
    func unreadableBoardDidChange(at root: URL)
}

extension BoardLoadObserver {
    /// Does nothing. An observer that records only the file loads does not hold the merge.
    ///
    /// - Parameter root: The root directory of the repo of the board.
    func boardEventsWillMerge(at root: URL) async {}

    /// Does nothing. An observer that records only the file loads does not wait for a change of a board that could
    /// not load.
    ///
    /// - Parameter root: The root directory of the repo of the board.
    func unreadableBoardDidChange(at root: URL) {}
}

/// The engine of one board in a process: its live graph and commit path, its file watcher, its serial gate, its
/// search, and its change feed (plan.md §5.4, §5.6, §6.4, §6.7, divergence.md §16).
///
/// The ``KanbanHost`` makes one engine for each board, and gives it to each session view whose current board or
/// related board it is. The engine owns its watcher: the watcher starts when the engine loads, and stops only when
/// the engine closes. A board with no `.kanban/` directory yet has a watcher on its repo directory; the watcher moves
/// to `.kanban/` when the directory appears (X13).
///
/// The board stays in memory until the host closes. A session view that reads the board reads ``readSession()``: the
/// session with the cursor of the change log of the board; it reads no file. A call that writes holds ``gate``, runs
/// on a copy of the session, and gives the new session back with ``replaceSession(with:)`` while it still holds the
/// gate (write through). The watcher brings each change from outside the process into memory, inside the gate.
///
/// A user can move the repo away and make a new repo at the same path. The folder at ``root`` then is not the folder
/// of the engine (``isAtRoot``), and the engine reads and writes no file at the path: it retires (``retire()``), and
/// the host lets go of it (divergence.md §16, Gap 6).
actor BoardEngine {
    /// The identity of the repo directory of the board: the key of the engine in the host.
    nonisolated let identity: FolderIdentity

    /// The root directory of the repo of the board, as the first load found it.
    nonisolated let root: URL

    /// The gate that lets one operation of the board run at a time: a call of a session view, or a batch of the
    /// watcher.
    nonisolated let gate = SerialGate()

    /// The change log of the board and its subscribers (plan.md §6.7, KANBAN-7): one log for the engine, which each
    /// session view of the board reads.
    nonisolated let feed: ChangeFeed

    /// The live graph of the board and its commit path.
    private(set) var session: CommitSession

    /// The gate that lets one write of the change log run at a time: an append of the changes of a round, or a new
    /// log. Thus ``newestCursor`` follows the writes of the log in their order.
    private let logGate = SerialGate()

    /// The cursor of the newest change of the change log, as the last write of the log left it (KANBAN-7).
    private var newestCursor: String

    /// The session of the board as the change log holds it, with its cursor (KANBAN-7): each change of the board in
    /// this session is in the log at or before the cursor, and each change of the board after the cursor is not in
    /// this session. ``readSession()`` gives it.
    private var loggedSession: CommitSession

    /// `true` from the take of the changes of an operation (``takeLiveChanges()``) until the operation has put them
    /// into the change log (``finishLogging()``). ``loggedSession`` then stays the session before the operation.
    private var isLogging = false

    /// The state of the file watcher of the board.
    private var watchState: EngineWatchState

    /// Gets a call when the watcher applies a batch, or `nil` for no calls.
    private let batchObserver: (any LiveGraphObserver)?

    /// Sends the changes of a batch of the watcher to the session views.
    private let publish: ChangePublisher

    /// Tells the host that the engine retired.
    private let reportRetirement: EngineRetirement

    /// Makes the engine of a loaded board.
    ///
    /// - Parameters:
    ///   - identity: The identity of the repo directory of the board.
    ///   - root: The root directory of the repo of the board.
    ///   - session: The loaded session of the board.
    ///   - capacity: The number of the newest changes that the change log of the board keeps.
    ///   - batchObserver: Gets a call when the watcher applies a batch, or `nil` for no calls.
    ///   - publish: Sends the changes of a batch of the watcher to the session views.
    ///   - reportRetirement: Tells the host that the engine retired.
    private init(
        identity: FolderIdentity,
        root: URL,
        session: CommitSession,
        keepingChanges capacity: Int,
        observingBatchesWith batchObserver: (any LiveGraphObserver)?,
        publishingTo publish: @escaping ChangePublisher,
        reportingRetirementTo reportRetirement: @escaping EngineRetirement
    ) async {
        let feed = ChangeFeed(capacity: capacity)
        let cursor = await feed.cursor
        self.identity = identity
        self.root = root
        self.session = session
        self.feed = feed
        newestCursor = cursor
        loggedSession = session.read(atCursor: cursor)
        self.batchObserver = batchObserver
        self.publish = publish
        self.reportRetirement = reportRetirement
        watchState = .unwatched
    }

    /// `true` while the folder at ``root`` is the folder of the engine. When a user moved the repo away and made a
    /// new repo at the same path, the folder at the path has a different identity, or the path holds no folder. The
    /// engine then must not read or write a file at the path (divergence.md §16, Gap 6). The check reads the identity
    /// of the folder with one `stat`.
    nonisolated var isAtRoot: Bool {
        (try? FolderIdentity(of: root)) == identity
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

    /// Loads a board: it starts the file watcher, and reads the key and the log files of the board, all at the same
    /// time (divergence.md §16, L1). The log does not store the key, so the file load does not wait for it.
    ///
    /// The load does not wait for the start of the watcher. Each watcher start of the host runs on one serial queue,
    /// and each start is a synchronous FSEvents call that can take a long time. Thus a load that waits for its watcher
    /// also waits for the watcher starts of the other loads, and the boards do not load at the same time. A change
    /// during the load is not lost: after the load and the start, the watcher gives one batch that holds its
    /// directory, so the engine compares each file of the board with the signatures of the load. A change after the
    /// start gives its own batch, which waits until the engine is made.
    ///
    /// The load checks first that the `.kanban/` directory is not a board of the old Rust kanban (divergence.md Q6),
    /// so the engine reads and writes nothing of an incompatible board. When the load fails, the watcher stops. When
    /// the watcher cannot start, the load fails.
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
        async let starting = startedWatcher(for: request)
        let session: CommitSession
        do {
            session = try await request.session()
        } catch {
            await (try? await starting)?.watcher.stop()
            throw error
        }
        let started = try await starting
        let engine = await BoardEngine(
            identity: request.identity,
            root: request.root,
            session: session,
            keepingChanges: request.configuration.changeLogCapacity,
            observingBatchesWith: request.configuration.batchObserver,
            publishingTo: request.publish,
            reportingRetirementTo: request.reportRetirement
        )
        if let started {
            await engine.consume(started)
            started.watcher.compareEachFile()
        }
        return engine
    }

    /// Starts the file watcher of a board that loads, when the load starts a watcher.
    ///
    /// - Parameter request: What to load, and the parts of the host that the engine uses.
    /// - Returns: The started watcher, or `nil` when the load starts no watcher.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when the watcher cannot start.
    private static func startedWatcher(for request: EngineLoad) async throws(BoardWatcherError) -> StartedWatcher? {
        guard request.startsWatcher else {
            return nil
        }
        return try await BoardWatcher.started(onBoardAt: request.root, in: request.folderStreams)
    }

    // MARK: - Session

    /// Gives the new session of the board after a call. The caller must hold ``gate``. The new session keeps the
    /// current key of the board, because ``changeKey(to:)`` does not wait for the gate: a call that started before a
    /// key change gives a session with the key before the change.
    ///
    /// - Parameter newSession: The session after the call.
    func replaceSession(with newSession: CommitSession) {
        storeKeepingKey(newSession)
    }

    /// Gives the board the key that git gives now, when it is not the current key (divergence.md M9). For example, a
    /// `git init` in the folder of a board outside git changes its key from its board ID to the git key, and the host
    /// then reads the new key from git with no restart. The next write records the key before the change as a name of
    /// the board (``CommitSession/changeKey(to:)``).
    ///
    /// The change does not wait for ``gate``: a caller can hold the gate of this engine while it loads a related
    /// board. A call or a batch that runs now keeps the change when it gives back its session
    /// (``replaceSession(with:)``).
    ///
    /// - Parameter key: The key that git gives now.
    func changeKey(to key: BoardKey) {
        session.changeKey(to: key)
        loggedSession.changeKey(to: key)
    }

    /// The current key of the board: the git key, or the board ID of a board outside git (divergence.md M9).
    var key: BoardKey {
        session.key
    }

    /// Gives the session of the board for a read that does not hold ``gate``, with the cursor of the change log at the
    /// same point (KANBAN-7): the session that the log holds, and the cursor of the newest change of the log.
    ///
    /// The engine keeps the two as one value, and the read takes it with no wait, so no change goes into the log
    /// between the read of the session and the read of the cursor. While an operation of the board puts its changes
    /// into the log, the read gives the session and the cursor from before the operation. Thus `changes(after:)` with
    /// the cursor gives each change of the board after the read, with none lost and none repeated.
    ///
    /// - Returns: The session, with the cursor of the read.
    func readSession() -> CommitSession {
        loggedSession
    }

    /// Gives the session of the board for a read that holds ``gate``, with the cursor of the newest change of the
    /// change log (KANBAN-7). Each change of the board goes into the log inside the gate, so the log holds each change
    /// of the session when the holder starts. A change that the holder makes later is after the cursor.
    ///
    /// - Returns: The newest session, with the cursor of the read.
    func readSessionHoldingGate() -> CommitSession {
        session.read(atCursor: newestCursor)
    }

    /// Puts the changes of one round into the change log of the board
    /// (``ChangeFeed/append(_:readingNodesOf:resolvingIn:)``). The writes of the log run one at a time.
    ///
    /// - Parameters:
    ///   - changes: The changes, each of one transaction, in the order of their transactions.
    ///   - view: The read view of the board after the round. The filter of each subscriber tests its nodes.
    ///   - board: The board that the resolvers of the changes read.
    func log(_ changes: [Change], readingNodesOf view: BoardView, resolvingIn board: EventBoard) async {
        await writeLog { feed in
            await feed.append(changes, readingNodesOf: view, resolvingIn: board)
        }
    }

    /// Puts a new, empty change log in the place of the log of the board, when no session view could log the changes
    /// of a round (``ChangeFeed/restart()``). A cursor of the old log then gives `RESYNC_REQUIRED`.
    func restartLog() async {
        await writeLog { feed in
            feed.restart()
        }
    }

    /// Records that an operation of the board put the changes that it took into the change log, or that no session
    /// view could log them and the log restarted. A read that does not hold ``gate`` then gets the session of the
    /// operation, with the cursor of the newest change of the log. The caller must hold ``gate``.
    func finishLogging() {
        isLogging = false
        loggedSession = session.read(atCursor: newestCursor)
    }

    /// Runs one write of the change log while it holds ``logGate``, and then records the cursor of the newest change
    /// of the log.
    ///
    /// - Parameter write: The write: it gets the feed of the board.
    private func writeLog(_ write: @Sendable (ChangeFeed) async -> Void) async {
        let feed = feed
        await logGate.run {
            await write(feed)
            await self.recordNewest(await feed.cursor)
        }
    }

    /// Records the cursor of the newest change of the change log after a write. While no operation of the board puts
    /// its changes into the log, the session that the log holds stays, and a read gets the new cursor: only an
    /// operation of the board changes the session, and it takes its changes before it puts them into the log.
    ///
    /// - Parameter cursor: The cursor of the newest change of the log.
    private func recordNewest(_ cursor: String) {
        newestCursor = cursor
        guard !isLogging else {
            return
        }
        loggedSession = loggedSession.read(atCursor: cursor)
    }

    /// Stores a new session of the board with the key and the former keys of the current session, so that a key
    /// change during the call or the batch that made the new session stays. The stored session holds no cursor:
    /// ``readSession()`` and ``readSessionHoldingGate()`` give the cursor of each read.
    ///
    /// - Parameter newSession: The new session.
    private func storeKeepingKey(_ newSession: CommitSession) {
        var kept = newSession.read(atCursor: nil)
        kept.takeKey(of: session)
        session = kept
    }

    /// Takes the changes of the live graph that added events since the last take, and forgets them. The caller must
    /// hold ``gate``. When the board changed, the caller puts the changes into the change log and then calls
    /// ``finishLogging()``; until then ``readSession()`` gives the session from before the changes. When the board did
    /// not change, the log holds each change of the session, and ``readSession()`` gives the session now.
    ///
    /// - Returns: The changes, or `nil` when the board did not change.
    func takeLiveChanges() -> BoardChanges? {
        let changes = session.takeLiveChanges()
        guard let taken = BoardChanges(of: session, changes: changes, madeBy: identity) else {
            if !isLogging {
                finishLogging()
            }
            return nil
        }
        isLogging = true
        return taken
    }

    /// Stops the file watcher, ends each subscription of the board, and cancels the embeddings of the search in the
    /// background. After the call returns, a change of a file applies nothing. The board stays in memory, and a
    /// search uses the keyword index. A second call does nothing. A retired engine closes too: its subscriptions end.
    func close() async {
        feed.finish()
        let watch = activeWatch
        watchState = .closed
        await session.source.search.stopEmbedding()
        await watch?.end()
    }

    /// Stops the file watcher of an engine whose folder is not at its root path any more (divergence.md §16, Gap 6).
    /// After the call returns, a change of a file at the path applies nothing. The feed stays open: each session view
    /// that holds the engine moves its subscribers to the engine of the folder that is now at the path, or ends them.
    /// A stopped engine (closed or retired) stays as it is.
    ///
    /// The caller can hold ``gate``, and the task of the watch can wait for the gate to give a batch. Thus the engine
    /// does not wait for the end of that task (``BoardWatch/stop()``, not ``BoardWatch/end()``).
    func retire() async {
        guard !isStopped else {
            return
        }
        let watch = activeWatch
        watchState = .retired
        await watch?.stop()
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
        watchState = .watching(BoardWatch(of: started, heldWeaklyBy: self, sendingBatchesTo: Self.batchDidArrive))
    }

    /// Gives one batch of the watcher of an engine to ``receive(_:)``. It is the receiver of each watch of an engine,
    /// for ``BoardWatch/init(of:heldWeaklyBy:sendingBatchesTo:)``.
    ///
    /// - Parameters:
    ///   - engine: The engine.
    ///   - paths: The changed paths of the batch.
    private static func batchDidArrive(in engine: BoardEngine, changing paths: [URL]) async {
        await engine.receive(paths)
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
    /// The batch observer gets its call after the change log holds the changes, so a read of the board that does not
    /// hold the gate (``readSession()``) then sees the batch.
    ///
    /// - Parameter paths: The changed paths of the batch.
    /// - Throws: A ``BoardWatcherError`` when the watcher cannot move, or an ``EventLogError`` when a file cannot be
    ///   read.
    private func applyPublishing(_ paths: [URL]) async throws {
        let applied: [URL]
        do {
            applied = try await apply(paths)
        } catch {
            await publishChanges()
            throw error
        }
        await publishChanges()
        guard !applied.isEmpty else {
            return
        }
        batchObserver?.didApply(changedPaths: applied)
    }

    /// Sends the changes of the live graph since the last take to the session views, which put them into the change
    /// log of the board, and then records that the log holds them (``finishLogging()``).
    private func publishChanges() async {
        guard let changes = takeLiveChanges() else {
            return
        }
        await publish([root.canonicalPath: changes])
        finishLogging()
    }

    /// Moves the watcher to `.kanban/` when `.kanban/` appeared, and then applies one batch to the session of the
    /// board (plan.md §5.6). The engine stores the new watch before the apply, so the new watch stays also when the
    /// apply fails.
    ///
    /// When the watcher moved, the batch also holds the `.kanban/` directory, so that it compares each file of the
    /// board.
    ///
    /// ``close()`` can run during each wait of the apply. After each wait, a closed engine stores nothing: it keeps
    /// no moved watch and no applied session, so a change applies nothing after ``close()``.
    ///
    /// The apply reads files at the root path only while the folder of the engine is at that path, before the read and
    /// after it (divergence.md §16, Gap 6). When a new repo is at the path, the engine retires and stores nothing.
    ///
    /// - Parameter paths: The changed paths of the batch.
    /// - Returns: The node files that the apply read again, in the sort order of their refs. The list is empty when the
    ///   engine stored nothing.
    /// - Throws: A ``BoardWatcherError`` when the watcher cannot move, or an ``EventLogError`` when a file cannot be
    ///   read.
    private func apply(_ paths: [URL]) async throws -> [URL] {
        guard let watch = activeWatch, await readsRoot() else {
            return []
        }
        let moved = try await movedWatch(watch)
        if let moved, await !adopt(moved) {
            return []
        }
        var updated = session
        let boardDirectory = updated.live.log.directory
        let applied = try await updated.apply(watchedPaths: moved == nil ? paths : paths + [boardDirectory])
        guard await readsRoot() else {
            return []
        }
        storeKeepingKey(updated)
        return applied
    }

    /// Tells whether the engine still reads the files at its root path: the engine is not stopped, and its folder is
    /// still at the path. An engine whose folder moved away tells the host, which lets go of the engine and retires it
    /// (divergence.md §16, Gap 6). Then the engine retires, also when no host holds it; a second retire does nothing.
    /// The host lets go of the engine before the watcher stops, so no caller sees a stopped watch of an engine that
    /// the host still holds. The caller holds ``gate``; the host does not wait for an engine gate.
    ///
    /// - Returns: `true` when the engine reads the files at its root path.
    private func readsRoot() async -> Bool {
        guard !isStopped else {
            return false
        }
        guard isAtRoot else {
            await reportRetirement(self)
            await retire()
            return false
        }
        return true
    }

    /// Stores the watch that a move of the watcher made, when the engine is not stopped. A stopped engine (closed or
    /// retired) keeps no watch: it stops the moved watch, so that no watcher runs after ``close()`` or ``retire()``.
    ///
    /// The caller holds ``gate``, and the task of the moved watch can wait for the gate to give a batch. Thus a stopped
    /// engine does not wait for the end of that task (``BoardWatch/stop()``, not ``BoardWatch/end()``). The task
    /// gets the gate after the caller, and its batch applies nothing, because the engine is stopped.
    ///
    /// - Parameter moved: The new watch.
    /// - Returns: `true` when the engine keeps the watch, or `false` when the engine is stopped.
    func adopt(_ moved: BoardWatch) async -> Bool {
        guard !isStopped else {
            await moved.stop()
            return false
        }
        watchState = .watching(moved)
        return true
    }

    /// `true` after ``close()`` or ``retire()``: the engine applies no batch and keeps no watch.
    private var isStopped: Bool {
        switch watchState {
        case .closed, .retired:
            true
        case .unwatched, .watching:
            false
        }
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
        let moved = BoardWatch(
            of: try await StartedWatcher(watching: boardDirectory, in: watch.watcher.folderStreams),
            heldWeaklyBy: self,
            sendingBatchesTo: Self.batchDidArrive
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

    /// The one FSEvents stream of the host, which watches the directory of the board (divergence.md §16).
    let folderStreams: FolderStreams

    /// Sends the changes of a batch of the watcher to the session views.
    let publish: ChangePublisher

    /// Tells the host that the engine retired because its folder moved away from its root path.
    let reportRetirement: EngineRetirement

    /// Gives the key of the board: the known key, the key that git gives (with the first commit of a repo with no
    /// commit, divergence.md §16 M8), or the board ID of a board outside git (divergence.md M9).
    ///
    /// - Returns: The key.
    /// - Throws: A ``BoardKeyError`` when git cannot give the key.
    func key() async throws(BoardKeyError) -> BoardKey {
        if let knownKey {
            return knownKey
        }
        return try await configuration.boardKeyReader(root)
    }

    /// Loads the session of the board. The key read and the file load run at the same time (divergence.md §16, L1).
    ///
    /// When the task nodes are joined, the search update starts at the same time as the merge of the event lists
    /// (divergence.md §16, L4). The session is ready when the graph, the event list, and the keyword index (BM25 and
    /// trigram) are ready. The embeddings finish in the background.
    ///
    /// - Returns: The session, with the board in memory and its keyword index updated.
    /// - Throws: ``EventLogError/incompatibleBoard(directory:)`` when the `.kanban/` directory has Rust files. An
    ///   ``EventLogError`` when a file cannot be read, or a ``BoardKeyError`` when git cannot give the key.
    func session() async throws -> CommitSession {
        async let key = key()
        let joined = try await joinedGraph()
        async let live = liveGraph(mergingEventsOf: joined)
        let boardKey = try await key
        let search = TaskSearch(embeddingWith: embedder)
        await search.update(from: BoardView(of: joined.graph, inBoard: boardKey.description))
        return CommitSession(
            of: await live,
            inBoard: boardKey,
            mintingFrom: configuration.ids,
            timedBy: configuration.clock,
            searchingWith: search,
            writingWith: configuration.logWriter
        )
    }

    /// Checks that the `.kanban/` directory is not a Rust board, and reads and joins the log files of the board with
    /// the parallel loader (plan.md §5.3). The event lists of the files are not merged yet.
    ///
    /// The load observer gets the end of each load that started, also of a load that fails.
    ///
    /// - Returns: The joined board.
    /// - Throws: ``EventLogError/incompatibleBoard(directory:)`` when the `.kanban/` directory has Rust files.
    ///   ``EventLogError/fileSystem(path:detail:)`` when a directory or a file cannot be read.
    private func joinedGraph() async throws(EventLogError) -> LiveGraph.Joined {
        let log = EventLog(repositoryAt: root)
        try log.checkCompatibility()
        await configuration.loadObserver?.boardLoadDidStart(at: root)
        defer { configuration.loadObserver?.boardLoadDidFinish(at: root) }
        return try await LiveGraph.join(using: BoardLoader(reading: log, reportingTo: configuration.workerObserver))
    }

    /// Merges the event lists of a joined board into the global event list, and makes the live graph. The load
    /// observer gets a call before the merge.
    ///
    /// - Parameter joined: The joined board.
    /// - Returns: The live graph.
    private func liveGraph(mergingEventsOf joined: LiveGraph.Joined) async -> LiveGraph {
        await configuration.loadObserver?.boardEventsWillMerge(at: root)
        return joined.merged()
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

    /// ``BoardEngine/retire()`` stopped the watcher, because the folder of the board moved away from its root path
    /// (divergence.md §16, Gap 6). No watcher starts again, and a batch that comes now changes nothing. The change
    /// feed stays open until ``BoardEngine/close()``.
    case retired
}

/// A file watcher that started before its engine exists, and the directory that it watches. Its batches wait in the
/// stream of the watcher until the engine reads them.
struct StartedWatcher: Sendable {
    /// The watcher.
    let watcher: BoardWatcher

    /// The watched directory: the `.kanban/` directory of the board, or the repo directory until `.kanban/` appears.
    let directory: URL

    /// Starts a file watcher on one directory.
    ///
    /// - Parameters:
    ///   - directory: The directory to watch.
    ///   - folderStreams: The FSEvents stream of the host.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when the watcher cannot start.
    init(watching directory: URL, in folderStreams: FolderStreams) async throws(BoardWatcherError) {
        watcher = try await BoardWatcher(watching: directory, in: folderStreams)
        self.directory = directory
    }
}

extension BoardWatcher {
    /// Starts a file watcher on a board: on its `.kanban/` directory, or on the repo directory when `.kanban/` is not
    /// there.
    ///
    /// - Parameters:
    ///   - root: The root directory of the repo of the board.
    ///   - folderStreams: The FSEvents stream of the host.
    /// - Returns: The started watcher.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when the watcher cannot start.
    static func started(
        onBoardAt root: URL,
        in folderStreams: FolderStreams
    ) async throws(BoardWatcherError) -> StartedWatcher {
        try await StartedWatcher(watching: existingBoardDirectory(ofBoardAt: root) ?? root, in: folderStreams)
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

/// The file watcher of one directory, and the task that gives its batches to their receiver (plan.md §5.6): the engine
/// of a loaded board, the host for a scan place (divergence.md §16, Gap 1), or the host for a board that could not
/// load (divergence.md Q7).
struct BoardWatch: Sendable {
    /// The watcher.
    let watcher: BoardWatcher

    /// The watched directory: the `.kanban/` directory of a board, the repo directory of a board until `.kanban/`
    /// appears, or a scan place.
    let directory: URL

    /// The task that gives each batch of the watcher to its receiver. It ends when the batches of the watcher end.
    let consumer: Task<Void, Never>

    /// Stops the watcher, and waits until the task ends. After the call returns, the watch applies no batch.
    ///
    /// A caller that holds the serial gate of the engine of the watch must use ``stop()``: the task can wait for the
    /// same gate, so this wait never ends.
    func end() async {
        await stop()
        await consumer.value
    }

    /// Stops the watcher and cancels the task, with no wait for the end of the task. The watcher gives no more
    /// batches, but the task can still give a batch that it has to its receiver.
    func stop() async {
        await watcher.stop()
        consumer.cancel()
    }
}

extension BoardWatch {
    /// Makes the watch of a started watcher for its owner: the watcher, and a task that gives each of its batches to a
    /// receiver, with the owner. This is the only place that wires a watcher to its owner: the engine of a board, or
    /// the host. The task holds the owner weakly, so the watcher does not keep the owner alive. After the owner is
    /// gone, the task gives no batch. The task ends when the batches of the watcher end.
    ///
    /// - Parameters:
    ///   - started: The started watcher and its directory.
    ///   - owner: The owner of the watch.
    ///   - receive: Gets the owner and the changed paths of each batch.
    init<Owner: AnyObject & Sendable>(
        of started: StartedWatcher,
        heldWeaklyBy owner: Owner,
        sendingBatchesTo receive: @escaping @Sendable (Owner, [URL]) async -> Void
    ) {
        let batches = started.watcher.batches
        let consumer = Task { [weak owner] in
            for await paths in batches {
                guard let owner else {
                    continue
                }
                await receive(owner, paths)
            }
        }
        self.init(watcher: started.watcher, directory: started.directory, consumer: consumer)
    }
}
