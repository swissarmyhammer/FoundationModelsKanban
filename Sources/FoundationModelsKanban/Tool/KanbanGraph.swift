import Foundation
import FoundationModelsExtras
import GraphQL

/// The session view of the kanban tool: one GraphQL endpoint for one session, over the board of its working
/// directory (plan.md §7.2, divergence.md §16, M9). In a git repo, the board is in the `.kanban/` directory of the top
/// folder of the worktree of the working directory. Outside git, the board is in the nearest folder, from the working
/// directory up, that has a `.kanban/`, else in the working directory.
///
/// Get a view from the host of the process: ``KanbanHost/session(workingDirectory:actor:)``. The tool, a GUI, and the
/// tests use the same view. Each view has its own session actor and its own default board, and a call that names no
/// board goes to that board. The boards themselves are in the ``KanbanHost``: one engine for each board in the
/// process, with one live graph, one file watcher, one serial gate, one search, and one change feed. Many views share
/// one engine, so a write in one session shows at once in a read of each other session.
///
/// Each call runs on a working copy of the live graph of its board. A call that keeps patches commits them at the end
/// of the call, under the lock of the board, and the working copy then becomes the live graph (plan.md §5.4, write
/// through). Each call holds the serial gate of each board that it can write, so a call never sees a half-applied
/// batch of a file watcher, and two calls never write one board at the same time (plan.md §7.2). A call that writes
/// many boards takes their gates in a fixed order, so two sessions cannot wait for each other.
///
/// The view also reads the related boards: the boards of the other repos that the ``BoardLocator`` finds (plan.md
/// §6.6). A call loads a related board when it names the board (`Query.board(id:)`, `Query.boards`, `node(id:)` with
/// a URI of the board) or when a cross-board dependency reads it. The host keeps the board in memory after that.
public actor KanbanGraph {
    /// The working directory of the session. The board is in the `.kanban/` directory of the top folder of its
    /// worktree, or outside git in the nearest folder up that has a `.kanban/` (divergence.md §16, M9).
    private let workingDirectory: URL

    /// The host that holds the engine of each board.
    private let host: KanbanHost

    /// `true` for a view that a test made with its own host: ``close()`` then closes the host too.
    private let ownsHost: Bool

    /// The session actor: the actor of each event that a call writes.
    private let sessionActor: SessionActor

    /// Finds the related boards (plan.md §6.6).
    private let locator: BoardLocator

    /// Gets a call when each call starts and ends, or `nil` for no calls.
    private let observer: (any KanbanCallObserver)?

    /// The public schema that each call runs against.
    private let schema: PublicSchema

    /// The change feed of each board that the view loaded. The subscribers of the view are in them (plan.md §6.7).
    private let feeds = SessionFeeds()

    /// The board of the working directory: not found yet, or found.
    private var boardState = ViewBoardState.unresolved

    /// The board in a subfolder of the repo of the working directory that the calls do not read, or `nil` when there
    /// is none or the view did not find its board yet (divergence.md M9).
    private var subfolderBoard: SubfolderBoard? {
        guard case .resolved(_, let subfolderBoard) = boardState else {
            return nil
        }
        return subfolderBoard
    }

    /// The engine of each related board that a call of the view loaded, by the canonical path of its repo directory.
    private var relatedBoards: [String: BoardEngine] = [:]

    /// The public schema in the GraphQL schema definition language (SDL), generated from the Graphiti schema.
    public static var schemaSDL: String {
        do {
            return try PublicSchema().sdl
        } catch {
            preconditionFailure("The Graphiti types of the public schema are not valid: \(error)")
        }
    }

    /// Makes the view of one session. The view finds its board at its first call, or when the host prepares it.
    ///
    /// - Parameters:
    ///   - host: The host that holds the engine of each board.
    ///   - ownsHost: `true` for a view of a test with its own host: ``close()`` then closes the host too.
    ///   - workingDirectory: The working directory of the session.
    ///   - actor: The session actor.
    ///   - locator: Finds the related boards.
    ///   - observer: Gets a call when each call starts and ends, or `nil` for no calls.
    ///   - extend: Adds test fields to the public schema. The default adds no field.
    /// - Throws: An error from Graphiti when a type of the public schema is not valid.
    init(
        host: KanbanHost,
        owningHost ownsHost: Bool,
        workingDirectory: URL,
        actingAs actor: SessionActor,
        locatedBy locator: BoardLocator,
        reportingTo observer: (any KanbanCallObserver)? = nil,
        extendingSchemaWith extend: SchemaExtension = PublicSchema.noExtension
    ) throws {
        self.host = host
        self.ownsHost = ownsHost
        self.workingDirectory = workingDirectory
        sessionActor = actor
        self.locator = locator
        self.observer = observer
        schema = try PublicSchema(extendedWith: extend)
    }

    /// Makes a view with its own host, with a key reader, a clock, a session actor, a ULID source, a locator, an
    /// embedder, and observers that a test gives. The view finds and loads its board at its first call. ``close()``
    /// closes the host of the view, so that its file watchers stop.
    ///
    /// - Parameters:
    ///   - root: The working directory.
    ///   - keyReader: Reads the key of the board of a repo: the current repo and each related repo.
    ///   - topReader: Reads the top folder of the worktree of a folder: the working directory and the folder of each
    ///     path ref.
    ///   - clock: Gives the time of a change.
    ///   - actor: The session actor.
    ///   - ids: The source of the transaction ULIDs and the event ids.
    ///   - locator: Finds the related boards. The default looks only in the parent directory of the repo.
    ///   - embedder: The embedder of `searchTasks`, or `nil` for BM25 and trigram only.
    ///   - observer: Gets a call when each call starts and ends, or `nil` for no calls.
    ///   - batchObserver: Gets a call when a file watcher applies a batch, or `nil` for no calls.
    ///   - logWriter: The writer of the appends of each commit. The default writes the log files.
    ///   - extend: Adds test fields to the public schema, for example a field that adds a warning. The default adds no
    ///     field.
    /// - Throws: An error from Graphiti when a type of the public schema is not valid.
    init(
        root: URL,
        readingKeyWith keyReader: @escaping BoardKeyReader,
        findingTopWith topReader: @escaping WorktreeTopReader,
        timedBy clock: @escaping @Sendable () -> DateTime,
        actingAs actor: SessionActor,
        mintingFrom ids: any ULIDSource,
        locatedBy locator: BoardLocator = .default,
        embeddingWith embedder: (any PooledEmbedding)? = nil,
        reportingTo observer: (any KanbanCallObserver)? = nil,
        observingBatchesWith batchObserver: (any LiveGraphObserver)? = nil,
        writingLogsWith logWriter: any EventLogWriter = FileEventLogWriter(),
        extendingSchemaWith extend: SchemaExtension = PublicSchema.noExtension
    ) throws {
        let configuration = HostConfiguration(
            keyReader: keyReader,
            topReader: topReader,
            clock: clock,
            ids: ids,
            locator: locator,
            embedder: embedder,
            batchObserver: batchObserver,
            logWriter: logWriter
        )
        try self.init(
            host: KanbanHost(configuration: configuration),
            owningHost: true,
            workingDirectory: root,
            actingAs: actor,
            locatedBy: locator,
            reportingTo: observer,
            extendingSchemaWith: extend
        )
    }

    /// Gives the session actor of a name: the actor whose slug is the slug of the name, with the name (plan.md §6).
    ///
    /// - Parameter name: The name of the actor, or `nil` for the name of the OS user.
    /// - Returns: The session actor.
    /// - Throws: ``KanbanError/invalidSlug(name:)`` when the name gives an empty slug.
    ///   ``KanbanError/reservedSlug(type:)`` when the name gives the slug ``Slug/reservedForBoard``.
    static func sessionActor(named name: String?) throws(KanbanError) -> SessionActor {
        let actorName = name ?? NSUserName()
        let ref = LocalRef.actor(slug: try Slug(columnOrActorName: actorName).value)
        try ref.checkSlugIsNotReserved()
        return SessionActor(ref: ref, name: actorName)
    }

    /// The file watcher of the board of the working directory while it runs, or `nil` before the board loads and
    /// after the host closes. A test reads it to prove which directory the engine watches, and that a close stopped
    /// the watcher.
    var activeWatch: BoardWatch? {
        get async {
            guard case .resolved(let engine, _) = boardState else {
                return nil
            }
            return await engine.activeWatch
        }
    }

    // MARK: - Public API

    /// Runs one GraphQL document against the board (plan.md §5.4).
    ///
    /// The call waits until each earlier call on its boards is done. A GraphQL error does not throw: the response has
    /// it in `errors`. When a log of the board changed before each commit attempt, the response has the one error
    /// `BOARD_BUSY` and the warnings of the last run in `extensions.warnings`, and the call wrote nothing.
    ///
    /// - Parameters:
    ///   - query: The GraphQL document.
    ///   - variables: The values of the variables of the document.
    ///   - operationName: The operation of the document to run, or `nil` when the document has one operation.
    /// - Returns: The GraphQL response (`{data, errors}`) as JSON text with sorted keys.
    /// - Throws: An I/O fault only: a ``BoardKeyError`` when git cannot give the board key, an ``EventLogError``
    ///   when a log file cannot be read, locked, or written, or a ``BoardWatcherError`` when the file watcher of a
    ///   board cannot start.
    public func execute(query: String, variables: [String: Map], operationName: String?) async throws -> String {
        try await execute(query: query, variables: variables, operationName: operationName, postingPlansTo: nil)
    }

    /// Runs one GraphQL document against the board, as ``execute(query:variables:operationName:)`` does, and posts
    /// the agent plan of each board whose tasks the call changed to a tool context (plan.md §7.3).
    ///
    /// A tool reads its ``ToolContext`` one time and gives it here. With no context, the call does no plan work.
    ///
    /// - Parameters:
    ///   - query: The GraphQL document.
    ///   - variables: The values of the variables of the document.
    ///   - operationName: The operation of the document to run, or `nil` when the document has one operation.
    ///   - context: The context of the tool call that gets the plans, or `nil` for no post.
    /// - Returns: The GraphQL response (`{data, errors}`) as JSON text with sorted keys.
    /// - Throws: An I/O fault only, the same as ``execute(query:variables:operationName:)``.
    func execute(
        query: String,
        variables: [String: Map],
        operationName: String?,
        postingPlansTo context: ToolContext?
    ) async throws -> String {
        try await runningOnBoard(postingPlansTo: context) { board, held in
            try await self.respond(
                to: query,
                variables: variables,
                operationName: operationName,
                on: board,
                holding: held
            )
        }
    }

    /// Starts one GraphQL subscription against the board (plan.md §6.7, §7.2).
    ///
    /// The start goes through the serial gate of the board, and it loads each board that its `dependsOn` edges reach.
    /// The stream does not hold the gate. Each change goes to the stream as one GraphQL response: a commit of this
    /// process at once, also a commit of a different session, and a change of a log file when the file watcher of its
    /// board applies it. Each response reads the board as the engine read it through the gate. A document that does
    /// not parse or validate, and a subscription that cannot start, give a stream with one response with the errors,
    /// and the stream then ends. ``close()`` ends the stream.
    ///
    /// A subscription that starts after ``close()`` gets the changes again: the view registers with the host again,
    /// so that the commits of each session and the batches of each file watcher reach the new stream. The view
    /// registers before it takes the gate, and thus before it adds the subscriber, so the stream gets each change
    /// that a commit or a file watcher publishes after the start.
    ///
    /// - Parameters:
    ///   - query: The subscription document.
    ///   - variables: The values of the variables of the document.
    ///   - operationName: The operation of the document to run, or `nil` when the document has one operation.
    /// - Returns: The GraphQL response (`{data, errors}`) of each event, as JSON text with sorted keys.
    /// - Throws: An I/O fault only, the same as ``execute(query:variables:operationName:)``.
    public func subscribe(
        query: String,
        variables: [String: Map],
        operationName: String?
    ) async throws -> AsyncThrowingStream<String, Error> {
        await host.register(self)
        return try await runningOnBoard(postingPlansTo: nil) { board, held in
            try await self.startSubscription(
                to: query,
                variables: variables,
                operationName: operationName,
                on: board,
                holding: held
            )
        }
    }

    /// Ends each subscription of this session view that runs now, and takes the view out of the host until its next
    /// subscription (plan.md §7.2, divergence.md §16).
    ///
    /// The boards stay loaded in the host, with their file watchers, for each other session and for a later session.
    /// A later call of this view still runs, and a later ``subscribe(query:variables:operationName:)`` starts a
    /// subscription that gets the changes of each session and of each file watcher. A view that a test made with its
    /// own host also closes that host: its file watchers stop, its subscriptions end, and its graphs stay in memory
    /// but do not follow the files any more.
    public func close() async {
        feeds.finish()
        await host.unregister(self)
        if ownsHost {
            await host.close()
        }
    }

    // MARK: - Board of the working directory

    /// Finds and loads the board of the working directory, when the view did not find it yet (divergence.md §16,
    /// Gap 2).
    ///
    /// - Throws: A ``BoardKeyError``, an ``EventLogError``, or a ``BoardWatcherError`` when the board cannot load.
    func prepareBoard() async throws {
        guard case .unresolved = boardState else {
            return
        }
        _ = try await resolveBoard()
    }

    /// Gives the engine of the board of the working directory, or the error that stops each call.
    ///
    /// - Returns: The engine, or the error.
    private func resolvedBoard() async -> Result<BoardEngine, any Error> {
        do {
            return .success(try await currentBoard())
        } catch {
            return .failure(error)
        }
    }

    /// Gives the engine of the board of the working directory. The first call finds the root directory of the board,
    /// and the host gives the engine of its board: it loads the board when no session loaded it yet.
    ///
    /// - Returns: The engine.
    /// - Throws: A ``BoardKeyError``, an ``EventLogError``, or a ``BoardWatcherError`` when the board cannot load. The
    ///   next call then tries again.
    private func currentBoard() async throws -> BoardEngine {
        if case .resolved(let engine, _) = boardState {
            return engine
        }
        return try await resolveBoard()
    }

    /// Finds the board of the working directory and the engine of that board (divergence.md §16, M9). The view then
    /// gets the changes of the board.
    ///
    /// - In a git repo, the board is at the top folder of the worktree. A `.kanban/` in a subfolder between the
    ///   working directory and the top folder is not read: each response of the view warns about it
    ///   (``SubfolderBoard``).
    /// - Outside git, the board is at the nearest folder, from the working directory up, that has a `.kanban/`, or at
    ///   the working directory itself (``BareBoard/root(of:)``). The first write makes its `.kanban/`.
    ///
    /// - Returns: The engine of the board.
    /// - Throws: A ``BoardKeyError`` other than ``BoardKeyError/notARepo(path:)``, an ``EventLogError``, or a
    ///   ``BoardWatcherError`` when the board cannot load. Then the view stays unresolved.
    private func resolveBoard() async throws -> BoardEngine {
        let root: URL
        let subfolderBoard: SubfolderBoard?
        do throws(BoardKeyError) {
            root = try await host.configuration.topReader(workingDirectory)
            subfolderBoard = SubfolderBoard.nearest(from: workingDirectory, below: root)
        } catch .notARepo {
            root = BareBoard.root(of: workingDirectory)
            subfolderBoard = nil
        }
        let engine = try await host.engine(ofBoardAt: root)
        feeds.replace(engine.feed, forBoardAt: engine.root.canonicalPath)
        await host.register(self)
        boardState = .resolved(engine, subfolderBoard: subfolderBoard)
        return engine
    }

    // MARK: - Moved boards

    /// Runs an operation on the board of the working directory, after the view follows each board whose folder moved
    /// away from its path (divergence.md §16, Gap 6). When the folder of a board moves during the operation, the commit
    /// of the operation stops before it writes (``MovedBoards``); the view follows the move and runs the operation
    /// again, so that the write goes to the board that is now at the path.
    ///
    /// - Parameter operation: The operation. It gets the board of the working directory, or the error that stops each
    ///   call.
    /// - Returns: The value of the operation.
    /// - Throws: The error of the operation. ``EventLogError/fileSystem(path:detail:)`` when a folder of the operation
    ///   moved during each of ``movedBoardRuns`` runs. Then the operation wrote nothing.
    private func followingMovedBoards<Value: Sendable>(
        _ operation: (Result<BoardEngine, any Error>) async throws -> Value
    ) async throws -> Value {
        var moved: [URL] = []
        for _ in 1...Self.movedBoardRuns {
            await followMovedBoards()
            do {
                return try await operation(await resolvedBoard())
            } catch let error as MovedBoards {
                moved = error.roots
            }
        }
        throw EventLogError.fileSystem(
            path: moved.map(\.path).joined(separator: ", "),
            detail: "The repo folder at the path changed during each of \(Self.movedBoardRuns) runs of the call"
        )
    }

    /// The number of runs of a call whose board moves away from its path during each run, before the call stops.
    private static let movedBoardRuns = 3

    /// Puts the engine of the folder that is now at each path in the place of each engine of the view whose folder
    /// moved away from its path, for example when a user moved the repo away and made a new repo at the same path
    /// (divergence.md §16, Gap 6). Thus no read and no write of the view goes to an engine whose folder is not at its
    /// path. The board of the working directory resolves again. A related board takes the engine of the folder that
    /// is now at its path, and the subscribers of the view move to that engine (``record(_:)``). A related board that
    /// cannot load at its path any more goes away from the view, and the streams of its subscribers end.
    private func followMovedBoards() async {
        if case .resolved(let current, _) = boardState, !current.isAtRoot {
            boardState = .unresolved
            _ = try? await resolveBoard()
        }
        for (path, engine) in relatedBoards where !engine.isAtRoot {
            await followMovedRelatedBoard(at: path)
        }
    }

    /// Puts the engine of the folder that is now at the path of a related board in the place of the engine of the
    /// view, or takes the board away from the view when no board loads at the path (divergence.md §16, Gap 6).
    ///
    /// - Parameter path: The canonical path of the repo directory of the related board.
    private func followMovedRelatedBoard(at path: String) async {
        let folder = URL(filePath: path, directoryHint: .isDirectory)
        guard
            let engine = try? await host.relatedEngine(ofBoardAt: folder, knownKey: nil),
            engine.root.canonicalPath == path,
            !isCurrentBoard(engine)
        else {
            forgetRelatedBoard(at: path)
            return
        }
        record(engine)
    }

    /// Takes a related board away from the view, and ends the streams of the subscribers of the view on it. The feed
    /// of the path stays when it is the feed of the board of the working directory.
    ///
    /// - Parameter path: The canonical path of the repo directory of the related board.
    private func forgetRelatedBoard(at path: String) {
        relatedBoards[path] = nil
        if case .resolved(let current, _) = boardState, current.root.canonicalPath == path {
            return
        }
        feeds.remove(forBoardAt: path)
    }

    /// Tells whether an engine is the engine of the board of the working directory.
    ///
    /// - Parameter engine: The engine.
    /// - Returns: `true` when the view found its board, and that board has the identity of the engine.
    private func isCurrentBoard(_ engine: BoardEngine) -> Bool {
        guard case .resolved(let current, _) = boardState else {
            return false
        }
        return current.identity == engine.identity
    }

    // MARK: - Calls

    /// Runs an operation on the board of the working directory: the view follows each moved board
    /// (``followingMovedBoards(_:)``), holds the serial gate of each board that the operation can write
    /// (``holdingGates(startingWith:_:)``), and sends the changes of those boards after the operation
    /// (``publishingChanges(of:postingPlansTo:_:)``). Each call of the view and each start of a subscription goes
    /// through this order of steps.
    ///
    /// - Parameters:
    ///   - context: The context of the tool call that gets the plans, or `nil` for no post.
    ///   - operation: The operation. It gets the board of the working directory, or the error that stops each call,
    ///     and the gates that it holds.
    /// - Returns: The value of the result of the operation.
    /// - Throws: The error of the operation, or the error of ``followingMovedBoards(_:)``.
    private func runningOnBoard<Value: Sendable>(
        postingPlansTo context: ToolContext?,
        _ operation: @Sendable (Result<BoardEngine, any Error>, HeldGates) async throws -> CallResult<Value>
    ) async throws -> Value {
        try await followingMovedBoards { board in
            try await holdingGates(startingWith: board) { held in
                try await self.publishingChanges(of: held, postingPlansTo: context) {
                    try await operation(board, held)
                }
            }
        }
    }

    /// Runs an operation while it holds the serial gate of each board that it can write, in the sort order of the
    /// board identities (divergence.md §16, locks across boards).
    ///
    /// The first run holds the gate of the board of the working directory. A run that needs one more board throws
    /// ``GateShortfall`` before it writes. The view then gives back each gate, takes the larger set in order, and runs
    /// the operation again.
    ///
    /// - Parameters:
    ///   - board: The board of the working directory, or the error that stops each call.
    ///   - operation: The operation. It gets the gates that it holds.
    /// - Returns: The value of the operation.
    /// - Throws: The error of the operation.
    private func holdingGates<Value: Sendable>(
        startingWith board: Result<BoardEngine, any Error>,
        _ operation: @Sendable (HeldGates) async throws -> Value
    ) async throws -> Value {
        var gates = HeldGates(of: (try? board.get()).map { engine in [engine] } ?? [])
        while true {
            do {
                return try await gates.run(operation)
            } catch let shortfall as GateShortfall {
                let larger = gates.adding(shortfall.engines)
                guard larger.engines.count > gates.engines.count else {
                    assertionFailure("A call asked again for gates that it holds")
                    Log.kanban.error("A call asked again for the gates of boards that it holds; the call stops")
                    throw shortfall
                }
                gates = larger
            }
        }
    }

    /// Runs one document inside the serial gates, and commits the patches that its mutation fields kept.
    ///
    /// - Parameters:
    ///   - query: The GraphQL document.
    ///   - variables: The values of the variables of the document.
    ///   - operationName: The operation of the document to run, or `nil`.
    ///   - board: The board of the working directory, or the error that stops each call.
    ///   - held: The gates that the call holds.
    /// - Returns: The result of the call. Its value is the response as JSON text with sorted keys.
    /// - Throws: A ``BoardKeyError``, a ``BoardWatcherError``, or an ``EventLogError`` when a board cannot load or a
    ///   commit cannot write. ``GateShortfall`` when the call needs one more gate.
    private func respond(
        to query: String,
        variables: [String: Map],
        operationName: String?,
        on board: Result<BoardEngine, any Error>,
        holding held: HeldGates
    ) async throws -> CallResult<String> {
        let answer: (KanbanError, [ResponseWarning]) throws -> String = { failure, warnings in
            try failure.responseJSON(warnings: warnings)
        }
        return try await runSchemaCall(on: board, holding: held, answeringFailureWith: answer) { schema, context in
            try await schema.respond(
                to: query,
                variables: variables,
                operationName: operationName,
                formattedWith: .sortedKeys,
                context: context
            )
        }
    }

    /// Starts one subscription document inside the serial gates (plan.md §6.7).
    ///
    /// - Parameters:
    ///   - query: The subscription document.
    ///   - variables: The values of the variables of the document.
    ///   - operationName: The operation of the document to run, or `nil`.
    ///   - board: The board of the working directory, or the error that stops each call.
    ///   - held: The gates that the call holds.
    /// - Returns: The result of the start. Its value is the response of each event as JSON text with sorted keys. A
    ///   subscription that cannot start gives a stream with one response with the error.
    /// - Throws: A ``BoardKeyError``, a ``BoardWatcherError``, or an ``EventLogError`` when a board cannot load.
    private func startSubscription(
        to query: String,
        variables: [String: Map],
        operationName: String?,
        on board: Result<BoardEngine, any Error>,
        holding held: HeldGates
    ) async throws -> CallResult<AsyncThrowingStream<String, Error>> {
        // The warnings list of plan.md §4.4 is for a call: a response of a subscription has no warnings.
        let answer: (KanbanError, [ResponseWarning]) throws -> AsyncThrowingStream<String, Error> = { failure, _ in
            .single(try failure.responseJSON())
        }
        return try await runSchemaCall(on: board, holding: held, answeringFailureWith: answer) { schema, context in
            try await schema.subscribe(
                to: query,
                variables: variables,
                operationName: operationName,
                formattedWith: .sortedKeys,
                context: context
            )
        }
    }

    /// Runs one call of the public schema on the board of the working directory, and gives a ``KanbanError`` of the
    /// run or of the commit as one error response (plan.md §4.4, §5.4). A `.kanban/` with Rust files, of the current
    /// board or of a related board that the call names, gives `INCOMPATIBLE_BOARD` (divergence.md Q6).
    ///
    /// - Parameters:
    ///   - board: The board of the working directory, or the error that stops each call.
    ///   - held: The gates that the call holds.
    ///   - answer: Gives the output of a ``KanbanError`` that fails the call as a whole, from the error and the
    ///     warnings that the last run of the call collected (plan.md §4.4), for example the warnings of the removed
    ///     Rust parameters of a call that fails with `BOARD_BUSY`.
    ///   - call: Runs the document against the schema and the context of one run, and gives the output.
    /// - Returns: ``CallResult/completed(_:)`` with the output of the run that committed or kept no patch, or
    ///   ``CallResult/failed(_:)`` with the output of `answer`.
    /// - Throws: A ``BoardKeyError``, a ``BoardWatcherError``, or an ``EventLogError`` when a board cannot load or a
    ///   commit cannot write. ``GateShortfall`` when the call needs one more gate. An error from the JSON encoder.
    private func runSchemaCall<Output: Sendable>(
        on board: Result<BoardEngine, any Error>,
        holding held: HeldGates,
        answeringFailureWith answer: (KanbanError, [ResponseWarning]) throws -> Output,
        _ call: @Sendable (PublicSchema, KanbanContext) async throws -> Output
    ) async throws -> CallResult<Output> {
        let schema = schema
        let lastRun = LastRunWarnings()
        do {
            return .completed(
                try await runCall(on: board, holding: held, recordingWarningsIn: lastRun) { context in
                    try await call(schema, context)
                }
            )
        } catch {
            guard let failure = KanbanError(callFailure: error) else {
                throw error
            }
            return .failed(try answer(failure, await lastRun.warnings))
        }
    }

    /// Runs one call on a copy of the session of the board of the working directory, and commits the patches that its
    /// mutation fields kept (plan.md §5.4). The call loads the related boards that it asks for. A related board that
    /// cannot be read gives one warning in the response (divergence.md Q7). A related board of the old Rust kanban that
    /// the call names stops the call with `INCOMPATIBLE_BOARD`, and one that only the list of `Query.boards` reaches
    /// gives one warning (divergence.md Q6). The new session goes
    /// back to the engine while the call holds the gate, also when the call fails, because a commit check can apply
    /// the changed files of a different process before the call fails.
    ///
    /// - Parameters:
    ///   - board: The board of the working directory, or the error that stops each call.
    ///   - held: The gates that the call holds.
    ///   - lastRun: Gets the warnings collector of each run when the run starts, so that it holds the collector of the
    ///     last run when the call fails as a whole.
    ///   - call: Runs the document against the context of one run, and gives the response.
    /// - Returns: The response of the run that committed, or of the run that kept no patch.
    /// - Throws: The error of `board`. ``GateShortfall`` when the call does not hold the gate of a board that it
    ///   commits. A ``BoardKeyError``, a ``BoardWatcherError``, or an ``EventLogError`` when a board cannot load or a
    ///   commit cannot write. A ``KanbanError`` of the commit, for example ``KanbanError/boardBusy(attempts:)``.
    private func runCall<Response: Sendable>(
        on board: Result<BoardEngine, any Error>,
        holding held: HeldGates,
        recordingWarningsIn lastRun: LastRunWarnings,
        _ call: @Sendable (KanbanContext) async throws -> Response
    ) async throws -> Response {
        let engine = try board.get()
        guard held.holds(engine) else {
            throw GateShortfall(engines: [engine])
        }
        await observer?.callDidStart()
        defer { observer?.callDidFinish() }
        var session = await engine.session
        let copy = session.copy(at: engine.root)
        let (clock, search, feeds) = (host.configuration.clock, session.source.search, feeds)
        let subfolderBoard = subfolderBoard
        do {
            let response = try await session.run(
                actingAs: sessionActor,
                readingRelatedBoardsWith: { related, requests in
                    try await self.relatedBoards(updating: related, toAnswer: requests, current: copy)
                },
                storingRelatedBoardsWith: { sessions, related in
                    await self.storeRelatedBoards(sessions, in: related, around: copy.directory)
                },
                admittingCommitsWith: { paths in
                    try await self.admit(paths, holding: held, current: engine)
                },
                { store in
                    let context = KanbanContext(store: store, clock: clock, search: search, feed: feeds)
                    await lastRun.record(context.warnings)
                    try await Self.checkUnreadableBoards(of: store, in: context)
                    await Self.addPlaceWarnings(of: store, subfolderBoard: subfolderBoard, in: context)
                    await Self.addOldNameWarnings(of: store, in: context)
                    return try await call(context)
                }
            )
            await engine.replaceSession(with: session)
            return response
        } catch {
            await engine.replaceSession(with: session)
            throw error
        }
    }

    /// Checks the related boards that a run reached and that cannot be read (divergence.md Q7). A board that stops each
    /// call, for example a board of the old Rust kanban that the call names (divergence.md Q6), stops the run with its
    /// error. Else the response of the run gets one warning for each of these boards, with the code of the board, its
    /// key, its `.kanban/` directory, and the reason.
    ///
    /// - Parameters:
    ///   - store: The store of the run. Its related boards are answered for each request of the run.
    ///   - context: The context of the run, whose warnings become `extensions.warnings` of the response.
    /// - Throws: The ``UnreadableBoard/callFailure`` of the first board in the sort order of the path that has one,
    ///   for example ``KanbanError/incompatibleBoard(directory:)``.
    private static func checkUnreadableBoards(
        of store: BoardStore,
        in context: KanbanContext
    ) async throws(KanbanError) {
        let boards = await store.unreadableBoards
        if let failure = boards.lazy.compactMap(\.callFailure).first {
            throw failure
        }
        for board in boards {
            await context.warnings.add(board.warningMessage, code: board.warningCode)
        }
    }

    /// Adds the warnings of the places of the boards to the response of a run (divergence.md M9): one warning for the
    /// board in a subfolder of the repo that the calls do not read, and one warning for each board ID that more than
    /// one board outside git has in the scan index that the run read.
    ///
    /// - Parameters:
    ///   - store: The store of the run. Its related boards hold the shared board IDs.
    ///   - subfolderBoard: The board in a subfolder of the repo of the view, or `nil` when there is none.
    ///   - context: The context of the run, whose warnings become `extensions.warnings` of the response.
    private static func addPlaceWarnings(
        of store: BoardStore,
        subfolderBoard: SubfolderBoard?,
        in context: KanbanContext
    ) async {
        if let subfolderBoard {
            await context.warnings.add(subfolderBoard.warningMessage, code: SubfolderBoard.warningCode)
        }
        for shared in await store.sharedBoardIDs {
            await context.warnings.add(shared.warningMessage, code: SharedBoardID.warningCode)
        }
    }

    /// Adds one warning to the response of a run for each old board name that a board ref or a stored link of the
    /// run used (divergence.md M9). The ref works: it reads the board that has the old name now.
    ///
    /// - Parameters:
    ///   - store: The store of the run. Its related boards hold the resolved board refs.
    ///   - context: The context of the run, whose warnings become `extensions.warnings` of the response.
    private static func addOldNameWarnings(of store: BoardStore, in context: KanbanContext) async {
        for oldName in await store.oldBoardNames {
            await context.warnings.add(oldName.warningMessage, code: OldBoardName.warningCode)
        }
    }

    /// Checks that a call holds the gate of each board of a commit attempt (divergence.md §16, locks across boards),
    /// and that the folder of each of these boards is still at its path (divergence.md §16, Gap 6). Thus an engine
    /// whose folder moved away never reads or writes the files of a new repo at its path.
    ///
    /// - Parameters:
    ///   - paths: The canonical paths of the repo directories of the boards of the commit.
    ///   - held: The gates that the call holds.
    ///   - current: The engine of the board of the working directory.
    /// - Throws: ``MovedBoards`` with the root directory of each board whose folder moved away from it.
    ///   ``GateShortfall`` with the engines whose gates the call does not hold.
    private func admit(_ paths: Set<String>, holding held: HeldGates, current: BoardEngine) throws {
        let engines = paths.sorted().compactMap { (path: String) -> BoardEngine? in
            guard let engine = path == current.root.canonicalPath ? current : relatedBoards[path] else {
                assertionFailure("A commit names the board at \(path), and the view did not load it")
                Log.kanban.error("A commit names a board that the view did not load", metadata: ["path": "\(path)"])
                return nil
            }
            return engine
        }
        let moved = engines.filter { engine in !engine.isAtRoot }
        guard moved.isEmpty else {
            throw MovedBoards(roots: moved.map(\.root))
        }
        let missing = engines.filter { engine in !held.holds(engine) }
        guard missing.isEmpty else {
            throw GateShortfall(engines: missing)
        }
    }

    // MARK: - Change feed

    /// Runs one operation inside the serial gates, and then sends the changes of the boards of the gates to each
    /// session view of the process (plan.md §6.7). The changes go out also when the operation throws, because a
    /// commit check can apply the changes of a different process before the call fails.
    ///
    /// When the operation completes and a tool context is given, the same changes also give the agent plan of each
    /// board whose tasks changed (plan.md §7.3). The view decides from the result of the operation: an operation that
    /// throws, and an operation whose commit fails (``CallResult/failed(_:)``, for example `BOARD_BUSY`), post no
    /// plan, because the call wrote nothing.
    ///
    /// - Parameters:
    ///   - held: The gates that the operation holds. Only these boards can change in the operation.
    ///   - context: The context of the tool call that gets the plans, or `nil` for no post.
    ///   - operation: The operation.
    /// - Returns: The value of the result of the operation.
    /// - Throws: The error of the operation.
    private func publishingChanges<Value: Sendable>(
        of held: HeldGates,
        postingPlansTo context: ToolContext?,
        _ operation: @Sendable () async throws -> CallResult<Value>
    ) async throws -> Value {
        let result: CallResult<Value>
        do {
            result = try await operation()
        } catch {
            await host.publish(await Self.takeLiveChanges(of: held))
            throw error
        }
        let changed = await Self.takeLiveChanges(of: held)
        await host.publish(changed)
        if case .completed = result {
            await context?.postAgentPlans(of: changed)
        }
        return result.value
    }

    /// Takes the changes of the live graph of each board whose gate an operation holds.
    ///
    /// - Parameter held: The gates that the operation holds.
    /// - Returns: The changes of each board that changed, by the canonical path of its repo directory.
    private static func takeLiveChanges(of held: HeldGates) async -> [String: BoardChanges] {
        var changed: [String: BoardChanges] = [:]
        for engine in held.engines {
            changed[engine.root.canonicalPath] = await engine.takeLiveChanges()
        }
        return changed
    }

    /// Sends the changes of some boards to the subscribers of this view (plan.md §6.7). The host calls it after each
    /// operation of each session and after each batch of a file watcher. A view with no subscriber does nothing.
    ///
    /// Before it makes the changes, the view loads each board that a `dependsOn` edge of its board reaches, and each
    /// board of an assignee that is an actor of a different board (divergence.md Q21), so that the derived fields read
    /// the tasks and the actors of those boards. A related board that cannot load, also a board of the old Rust
    /// kanban, does not stop the changes (divergence.md Q7, X12): the derived fields read no task of that board, and
    /// the changes of the boards that load go out. Only a cancel of the task is recorded with swift-log, and the
    /// changes are then not sent.
    ///
    /// First the view follows each board whose folder moved away from its path (divergence.md §16, Gap 6), so that a
    /// subscriber from before a new repo replaced its repo gets the changes of the new repo.
    ///
    /// - Parameter changed: The changes of each board that changed, by the canonical path of its repo directory.
    func publish(_ changed: [String: BoardChanges]) async {
        await followMovedBoards()
        let subscribed = feeds.subscribedBoards
        guard !changed.isEmpty, !subscribed.isEmpty, case .resolved(let current, _) = boardState else {
            return
        }
        let currentSession = await current.session
        let copy = currentSession.copy(at: current.root)
        let related: RelatedBoards
        do {
            let requests = RelatedBoards.loadable.crossBoardRequests(
                of: currentSession.live.graph,
                inBoard: copy.key.description
            )
            related = try await relatedBoards(updating: .loadable, toAnswer: requests, current: copy)
        } catch {
            Log.kanban.error(
                "The change feed stopped while it read the boards of the dependencies; the changes are not sent",
                metadata: ["error": "\(error)"]
            )
            return
        }
        let sessions = await loadedSessions(current: current)
        let round = ChangeRound(
            of: changesOfLoadedEngines(in: changed, amongBoards: sessions, current: current),
            amongBoards: sessions,
            currentPath: copy.directory.canonicalPath,
            reading: related
        )
        for path in subscribed.sorted() {
            guard let session = sessions[path] else {
                assertionFailure("A subscriber observes the board at \(path), and the view did not load it")
                Log.kanban.error("A subscriber observes a board that the view did not load", metadata: ["path": "\(path)"])
                continue
            }
            feeds.publish(
                round.changes(of: session, atPath: path),
                toBoardAt: path,
                readingNodesOf: round.view(of: session),
                resolvingIn: eventBoard(
                    of: session,
                    reading: eventRelatedBoards(ofBoardAt: path, in: round, current: copy)
                )
            )
        }
    }

    /// Keeps the changes of each board that the view loaded, and only when the engine that the view holds for the path
    /// made them. When a new repo replaced the repo at a path, the engine of the old repo keeps that path, and its
    /// changes are not changes of the board of the view (divergence.md §16).
    ///
    /// - Parameters:
    ///   - changed: The changes of each board that changed, by the canonical path of its repo directory.
    ///   - sessions: The session of each board that the view loaded, by the canonical path of its repo directory.
    ///   - current: The engine of the board of the working directory.
    /// - Returns: The changes that the view sends to its subscribers.
    private func changesOfLoadedEngines(
        in changed: [String: BoardChanges],
        amongBoards sessions: [String: CommitSession],
        current: BoardEngine
    ) -> [String: BoardChanges] {
        var identities = relatedBoards.mapValues(\.identity)
        identities[current.root.canonicalPath] = current.identity
        return changed.filter { path, changes in
            sessions[path] != nil && identities[path] == changes.identity
        }
    }

    /// The session of each board that the view loaded: the board of the working directory and each related board, by
    /// the canonical path of its repo directory.
    ///
    /// - Parameter current: The engine of the board of the working directory.
    /// - Returns: The sessions.
    private func loadedSessions(current: BoardEngine) async -> [String: CommitSession] {
        var sessions = await relatedSessions
        sessions[current.root.canonicalPath] = await current.session
        return sessions
    }

    /// The session of each related board that the view loaded, by the canonical path of its repo directory.
    private var relatedSessions: [String: CommitSession] {
        get async {
            var sessions: [String: CommitSession] = [:]
            for (path, engine) in relatedBoards {
                sessions[path] = await engine.session
            }
            return sessions
        }
    }

    /// Gives the other boards that the resolvers of the events of a board read: the boards after the operation, as
    /// that board sees them. For a related board, the related board is the current board of the value, and the
    /// current board of the view is a related board (plan.md §6.7). Thus each key reads the board that it names.
    ///
    /// - Parameters:
    ///   - path: The canonical path of the repo directory of the board of the events.
    ///   - round: The changes of the operation.
    ///   - current: The copy of the current board: the top folder of its worktree and its current key.
    /// - Returns: The other boards.
    private func eventRelatedBoards(
        ofBoardAt path: String,
        in round: ChangeRound,
        current: BoardCopy
    ) -> RelatedBoards {
        guard path != current.directory.canonicalPath else {
            return round.after
        }
        return round.after.centered(onBoardAt: path, movingCurrentTo: current)
    }

    /// Gives the board that the resolvers of the events of a board read.
    ///
    /// - Parameters:
    ///   - session: The session of the board.
    ///   - related: The other boards as the reads see them after the operation.
    /// - Returns: The board.
    private func eventBoard(of session: CommitSession, reading related: RelatedBoards) -> EventBoard {
        EventBoard(
            work: session.makeWorkingCopy(
                stampedBy: EventStamp(
                    actingAs: sessionActor.ref,
                    mintingFrom: host.configuration.ids,
                    after: session.live.largestEventID
                )
            ),
            key: session.key.description,
            source: session.source,
            related: related
        )
    }

    // MARK: - Related boards

    /// Loads the related boards that a run of a call asks for, and gives the related boards of the next run (plan.md
    /// §6.6). The loop also loads each board that a cross-board dependency or assignee of a loaded board names, so
    /// that the readiness of a task of a related board reads its own dependencies, and its assignees read their own
    /// boards. The result holds each related board that the view loaded, also when the run asks for no board, because
    /// `undo` and `redo` with no `txn` search the loaded boards (plan.md §6.5, scope).
    ///
    /// Each round of the loop answers its open requests at the same time (divergence.md §16, L5). Each load goes
    /// through the table of the host, so two requests for the same board wait for one load.
    ///
    /// - Parameters:
    ///   - related: The related boards of the run.
    ///   - requests: The requests of the run.
    ///   - current: The copy of the current board: the top folder of its worktree and its current key.
    /// - Returns: The related boards with an answer for each request, and with each loaded related board. A board that
    ///   cannot load is ``BoardResolution/unreadable(_:)`` (divergence.md Q7).
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during a scan or a load.
    private func relatedBoards(
        updating related: RelatedBoards,
        toAnswer requests: Set<BoardRequest>,
        current: BoardCopy
    ) async throws -> RelatedBoards {
        var updated = await withLoadedBoards(related, around: current.directory)
        var pending = requests.union(updated.loadedCrossBoardRequests)
        while !pending.isEmpty {
            let open = pending.filter { request in !updated.satisfies([request]) }
            let answers = try await Array(open).concurrentMap { request in
                try await self.answer(request, current: current)
            }
            for answer in answers {
                answer.record(in: &updated)
            }
            updated = await withLoadedBoards(updated, around: current.directory)
            pending = updated.loadedCrossBoardRequests.filter { request in !updated.satisfies([request]) }
        }
        if requests.contains(where: \.readsScanIndex), let index = await host.scanIndex(around: current.directory) {
            updated.record(sharedBoardIDs: SharedBoardID.shared(among: index.copies))
        }
        return updated
    }

    /// Stores the sessions of the related boards after a commit attempt of a call (plan.md §5.4 step 5, §6.6), and
    /// gives the related boards of the next run. The call holds the gate of each of these boards.
    ///
    /// After a commit, the session holds the new live graph and the new file signatures, so that the file watcher of
    /// the board finds no change for the write of this process. After a changed log, the session holds the changed
    /// files, so that the next run reads them.
    ///
    /// - Parameters:
    ///   - sessions: The session of each related board that the call changed, by the canonical path of its repo
    ///     directory.
    ///   - related: The related boards of the run.
    ///   - root: The top folder of the worktree of the current board.
    /// - Returns: The related boards with the stored sessions.
    private func storeRelatedBoards(
        _ sessions: [String: CommitSession],
        in related: RelatedBoards,
        around root: URL
    ) async -> RelatedBoards {
        for (path, session) in sessions {
            guard let engine = relatedBoards[path] else {
                assertionFailure("A call changed the related board at \(path), and the view did not load it")
                Log.kanban.error(
                    "A call changed a related board that the view did not load",
                    metadata: ["path": "\(path)"]
                )
                continue
            }
            await engine.replaceSession(with: session)
            await session.updateSearch()
        }
        return await withLoadedBoards(related, around: root)
    }

    /// Gives the related boards of a run with the session of each loaded related board and the places of the scan.
    ///
    /// - Parameters:
    ///   - related: The related boards of the run.
    ///   - root: The top folder of the worktree of the current board.
    /// - Returns: The related boards with the loaded boards.
    private func withLoadedBoards(_ related: RelatedBoards, around root: URL) async -> RelatedBoards {
        var updated = related
        updated.install(boards: await relatedSessions, searchRoots: locator.places(around: root))
        return updated
    }

    /// Answers one request: resolves the board ref or scans for the list, and loads each board that the answer
    /// names.
    ///
    /// - Parameters:
    ///   - request: The request.
    ///   - current: The copy of the current board: the top folder of its worktree and its current key.
    /// - Returns: The answer, for the related boards of the next run.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during the scan or a load.
    private func answer(_ request: BoardRequest, current: BoardCopy) async throws -> BoardAnswer {
        switch request {
        case .board(let reference):
            .board(reference, try await loadBoard(named: reference, current: current))
        case .allCopies:
            .listing(try await loadEachCopy(around: current.directory))
        case .loadedCopies(let key):
            .loadedCopies(key, try await loadedCopies(withKey: key))
        }
    }

    /// Gives each copy with a key that the table of the host has loaded, and records each one as a board of this view
    /// (plan.md §6.5, many boards; divergence.md X5). The list has no load of a board that the host did not load.
    ///
    /// - Parameter key: The key, with the host in lowercase.
    /// - Returns: The copies: ``BoardResolution/current`` for the board of the working directory, else the copy at the
    ///   root directory of its engine. A board that cannot load is ``BoardResolution/unreadable(_:)``.
    /// - Throws: The error of a load when the task is cancelled.
    private func loadedCopies(withKey key: String) async throws -> [BoardResolution] {
        try await host.loadedCopies(withKey: key).concurrentMap { copy in
            try await self.loadRelatedBoard(copy)
        }
    }

    /// Finds the board that a board ref names, and loads it when it is a related board.
    ///
    /// - Parameters:
    ///   - reference: The board ref.
    ///   - current: The copy of the current board: the top folder of its worktree and its current key.
    /// - Returns: The board. A board that cannot load is ``BoardResolution/unreadable(_:)``.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during the scan or the load.
    private func loadBoard(named reference: String, current: BoardCopy) async throws -> BoardResolution {
        let resolution = try await resolution(of: reference, current: current)
        guard case .copy(let copy) = resolution else {
            return resolution ?? .notFound
        }
        return try await loadRelatedBoard(copy)
    }

    /// Finds the board that a board ref names in the index of the scan of the host (plan.md §6.6, index life, board
    /// refs). The first call scans. A path to a folder that the index does not have gives the board at the top folder
    /// of the worktree of that folder, with no scan (divergence.md §16). The host keeps what git told about that folder
    /// in memory, so that a later call with the same path ref runs no `git`, and a later ref with the key of its board
    /// resolves to it (divergence.md §16, Gap 1; divergence.md X4). A later call whose ref names no copy of the index
    /// and no folder scans again only when a file watcher of a scan place saw a change since the last scan
    /// (divergence.md §16, Gap 1). A key that no copy of the current index has then gives the first board with that
    /// key that a call reached by a path. Else the ref is not found, with no scan and no `git`.
    ///
    /// - Parameters:
    ///   - reference: The board ref.
    ///   - current: The copy of the current board: the top folder of its worktree and its current key.
    /// - Returns: The board (for a path to a folder outside git, the board outside git of that folder), or `nil` when
    ///   no copy of the index, no folder, and no board that a call reached by a path has the ref.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during the scan or during a
    ///   read of git for a folder. Each other ``BoardKeyError`` of the read of the top folder of a folder.
    private func resolution(
        of reference: String,
        current: BoardCopy
    ) async throws(BoardKeyError) -> BoardResolution? {
        let resolve = { (index: BoardIndex) in
            index.resolution(of: reference, currentRoot: current.directory, currentNames: current.names)
        }
        if let index = await host.scanIndex(around: current.directory), let found = resolve(index) {
            return found
        }
        if let folder = BoardLocator.folder(namedBy: reference, currentRoot: current.directory),
            let found = try await host.board(ofFolderAt: folder).resolution(currentRoot: current.directory)
        {
            return found
        }
        if let found = resolve(try await host.currentScanIndex(around: current.directory)) {
            return found
        }
        return await host.pathCopy(namedBy: reference).map { copy in
            BoardResolution(of: copy, currentRoot: current.directory)
        }
    }

    /// Gives the copies of `Query.boards` from the current scan index of the host, and loads each copy that is not the
    /// current repo. The host scans only when the index is not current (divergence.md §16, Gap 1). The copies load at
    /// the same time (divergence.md §16, L5).
    ///
    /// - Parameter root: The top folder of the worktree of the current board.
    /// - Returns: The copies, in scan order. A copy whose board cannot load is ``BoardResolution/unreadable(_:)``.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during the scan or a load.
    private func loadEachCopy(around root: URL) async throws -> [ListedCopy] {
        let index = try await host.currentScanIndex(around: root)
        return try await index.copies.concurrentMap { copy in
            try await self.listedCopy(of: copy, currentRoot: root)
        }
    }

    /// Gives one copy of the list of `Query.boards`, and loads the copy when it is not the current repo.
    ///
    /// A copy of the old Rust kanban does not stop the call (divergence.md Q6): the load stops at the check of its
    /// `.kanban/` directory before it reads a file, and the list leaves out the copy with a `BOARD_INCOMPATIBLE`
    /// warning. A call that also names the board still stops with `INCOMPATIBLE_BOARD`.
    ///
    /// - Parameters:
    ///   - copy: The copy that the scan found.
    ///   - root: The top folder of the worktree of the current board.
    /// - Returns: The copy in the list. A copy whose board cannot load is ``BoardResolution/unreadable(_:)``.
    /// - Throws: The error of the load when the task is cancelled.
    private func listedCopy(of copy: BoardCopy, currentRoot root: URL) async throws -> ListedCopy {
        let resolution = BoardResolution(of: copy, currentRoot: root)
        guard case .copy(let related) = resolution else {
            return ListedCopy(board: resolution, isEnabled: copy.isEnabled)
        }
        return ListedCopy(board: try await loadRelatedBoard(related).listed, isEnabled: copy.isEnabled)
    }

    /// Gets the engine of a related board from the host, which loads the board when no session loaded it yet, and
    /// records it as a board of this view.
    ///
    /// The host finds the engine by the identity of the folder. Thus a copy that is the board of the working directory
    /// by a different path gives ``BoardResolution/current``, and a copy whose engine has a different path text gives
    /// the copy at the path of the engine.
    ///
    /// A board that cannot load, for example a log file with no read permission, is
    /// ``BoardResolution/unreadable(_:)`` (divergence.md Q7): a call continues with a warning that names it, and the
    /// change feed continues without it. A board of the old Rust kanban keeps its error as the
    /// ``UnreadableBoard/callFailure``, so it still stops each call that names it with `INCOMPATIBLE_BOARD`
    /// (divergence.md Q6). The list of `Query.boards` changes that error to a warning (``BoardResolution/listed``).
    ///
    /// - Parameter copy: The copy of the related repo.
    /// - Returns: The board: the copy at the root directory of its engine, ``BoardResolution/current``, or
    ///   ``BoardResolution/unreadable(_:)`` when the board cannot load.
    /// - Throws: The error of the load when the task is cancelled.
    private func loadRelatedBoard(_ copy: BoardCopy) async throws -> BoardResolution {
        let engine: BoardEngine
        do {
            engine = try await host.relatedEngine(ofBoardAt: copy.directory, knownKey: copy.key)
        } catch {
            guard !Task.isCancelled else {
                throw error
            }
            let board = UnreadableBoard(
                copy: copy,
                reason: String(describing: error),
                effect: KanbanError(callFailure: error).map(UnreadableBoard.Effect.callFailure) ?? .warning
            )
            return .unreadable(board)
        }
        if case .resolved(let current, _) = boardState, current.identity == engine.identity {
            return .current
        }
        record(engine)
        return .copy(BoardCopy(directory: engine.root, key: copy.key, isEnabled: copy.isEnabled, names: copy.names))
    }

    /// Records the engine of a related board as the board of its path. A path has one engine in the view. When a new
    /// repo replaced the repo at the path, the engine has a new identity: it replaces the old engine, and the
    /// subscribers of the view on the old board move to the feed of the new board (divergence.md §16). The same engine
    /// again changes nothing.
    ///
    /// - Parameter engine: The engine of the related board.
    private func record(_ engine: BoardEngine) {
        let path = engine.root.canonicalPath
        guard let old = relatedBoards[path] else {
            relatedBoards[path] = engine
            feeds.add(engine.feed, forBoardAt: path)
            return
        }
        guard old.identity != engine.identity else {
            return
        }
        relatedBoards[path] = engine
        feeds.replace(engine.feed, forBoardAt: path)
    }
}

// MARK: - Board state

/// The board of the working directory of a ``KanbanGraph``.
private enum ViewBoardState {
    /// No call and no preparation found the board yet.
    case unresolved

    /// The view found the engine of the board, and the board in a subfolder of the repo that the calls do not read,
    /// or `nil` when there is none (divergence.md M9).
    case resolved(BoardEngine, subfolderBoard: SubfolderBoard?)
}

// MARK: - Related board answers

/// The answer to one ``BoardRequest`` of a run. The view answers the requests of a round at the same time, and then
/// records each answer in the related boards of the next run.
private enum BoardAnswer: Sendable {
    /// The board that a board ref names, by the ref as the call wrote it.
    case board(String, BoardResolution)

    /// The list of `Query.boards`, in scan order.
    case listing([ListedCopy])

    /// The copies with a key that the table of the host has loaded, by the key.
    case loadedCopies(String, [BoardResolution])

    /// Records the answer in the related boards of a run.
    ///
    /// - Parameter related: The related boards that get the answer.
    func record(in related: inout RelatedBoards) {
        switch self {
        case .board(let reference, let resolution):
            related.record(resolution, forBoard: reference)
        case .listing(let copies):
            related.record(listing: copies)
        case .loadedCopies(let key, let copies):
            related.record(loadedCopies: copies, ofKey: key)
        }
    }
}

extension Array where Element: Sendable {
    /// Runs an operation on each element at the same time, and gives the results in the order of the elements.
    /// Each operation runs to its end, also when the operation of a different element throws.
    ///
    /// - Parameter transform: The operation.
    /// - Returns: The result of the operation for each element, in the order of the elements.
    /// - Throws: The error of the first element, in the order of the elements, whose operation throws.
    fileprivate func concurrentMap<Value: Sendable>(
        _ transform: @escaping @Sendable (Element) async throws -> Value
    ) async throws -> [Value] {
        let results = await withTaskGroup(of: (position: Int, result: Result<Value, any Error>).self) { group in
            for (position, element) in enumerated() {
                group.addTask {
                    do {
                        return (position, .success(try await transform(element)))
                    } catch {
                        return (position, .failure(error))
                    }
                }
            }
            return await group.reduce(into: []) { results, entry in results.append(entry) }
        }
        return try results.sorted { lhs, rhs in lhs.position < rhs.position }.map { entry in try entry.result.get() }
    }
}

// MARK: - Call result

/// The result of one operation of a ``KanbanGraph`` inside the serial gates: a call or the start of a subscription.
/// The result tells the agent plan if the operation wrote its changes (plan.md §7.3).
private enum CallResult<Value: Sendable>: Sendable {
    /// The operation committed its patches, or it kept no patch.
    case completed(Value)

    /// A ``KanbanError`` of the run or of the commit failed the call as a whole, for example `BOARD_BUSY`. The call
    /// wrote nothing. The value holds the error response.
    case failed(Value)

    /// The value of the operation: its output, or the error response of a failed call.
    var value: Value {
        switch self {
        case .completed(let value), .failed(let value):
            value
        }
    }
}

// MARK: - Warnings of the last run

/// The warnings collector of the last run of one call (plan.md §4.4).
///
/// Each run of a call gets a new ``KanbanContext``, and thus a new collector. A call that fails as a whole after its
/// runs, for example with `BOARD_BUSY`, gives an error response in place of the response of its last run. The error
/// response reads the warnings of the last run here, so that the agent sees them on this path too.
actor LastRunWarnings {
    /// The collector of the run that started last, or `nil` before the first run.
    private var collector: ResponseWarnings?

    /// Records the collector of a run that starts. It replaces the collector of the run before it.
    ///
    /// - Parameter warnings: The collector of the context of the run.
    func record(_ warnings: ResponseWarnings) {
        collector = warnings
    }

    /// The warnings of the last run, in the order that the run added them, or no warning when no run started.
    var warnings: [ResponseWarning] {
        get async {
            await collector?.list ?? []
        }
    }
}

// MARK: - Session actor

/// The session actor of a session view: the actor of each event that a call of the view writes (plan.md §6).
///
/// A call that writes to a board makes sure that the actor exists in that board. When the actor is new, the call
/// writes an actor `set` patch with ``name``.
struct SessionActor: Equatable, Sendable {
    /// The local ref of the actor, for example `actor/claude-code`.
    let ref: LocalRef

    /// The name of the actor, for example `Claude Code`.
    let name: String
}

// MARK: - Serial gate

/// Gets a call when each call of a ``KanbanGraph`` starts and ends, inside the serial gate.
///
/// A test uses it to record the order of the calls.
protocol KanbanCallObserver: Sendable {
    /// Tells that a call started. The call waits until this method returns.
    func callDidStart() async

    /// Tells that a call ended.
    func callDidFinish()
}

/// Gets a call when a file watcher of a board engine applies a batch to a live graph, inside the serial gate.
///
/// A test uses it to count the applies and to wait for a batch. A batch whose files all have their recorded
/// signatures (for example the write of this process) applies nothing and gives no call.
protocol LiveGraphObserver: Sendable {
    /// Tells that a batch changed a live graph.
    ///
    /// - Parameter paths: The node files that the apply read again, in the sort order of their refs.
    func didApply(changedPaths paths: [URL])
}

/// An async queue that runs a fixed number of operations at a time, in the order that the operations arrive.
///
/// The gate of a board engine has one slot, so it runs one operation at a time (plan.md §7.2). An actor alone does not
/// do this: it can start a second call at each `await` of the first call. The gate keeps the operations that wait in
/// a queue, and starts the next one only when a running one ends.
actor SerialGate {
    /// The number of slots of the gate of an engine: one operation at a time.
    static let serialSlots = 1

    /// The number of slots that no operation holds.
    private var freeSlots: Int

    /// The operations that wait, in the order that they arrived.
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Makes a gate.
    ///
    /// - Parameter slots: The number of operations that can run at the same time. It must be one or more.
    init(slots: Int = serialSlots) {
        precondition(slots > 0, "A gate needs one slot or more, not \(slots)")
        freeSlots = slots
    }

    /// Runs an operation while it holds one slot of the gate. The operation starts after each earlier operation got
    /// a slot.
    ///
    /// - Parameter operation: The operation.
    /// - Returns: The result of the operation.
    /// - Throws: The error of the operation. The gate then gives the slot to the next operation.
    func run<Value: Sendable>(inSlot operation: @Sendable () async throws -> Value) async rethrows -> Value {
        await enter()
        defer { leave() }
        return try await operation()
    }

    /// Takes one free slot, or waits until a running operation gives its slot.
    private func enter() async {
        guard freeSlots == 0 else {
            freeSlots -= 1
            return
        }
        await withCheckedContinuation { waiter in waiters.append(waiter) }
    }

    /// Gives the slot to the next operation that waits, or marks the slot free.
    private func leave() {
        guard !waiters.isEmpty else {
            freeSlots += 1
            return
        }
        waiters.removeFirst().resume()
    }
}
