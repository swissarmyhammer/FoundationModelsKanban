import Foundation
import FoundationModelsExtras
import GraphQL

/// The engine of the kanban tool: one GraphQL endpoint over the board of a repo (plan.md §7.2).
///
/// The tool, the CLI, a GUI, and the tests use the same engine. The host makes one engine and gives it to each client
/// in the process, so that all clients share one live graph and one serial gate.
///
/// The first call that needs the board reads the board key from git, and loads the board from its logs with the
/// parallel loader (plan.md §5.3). The engine then keeps the graph in memory. A repo with no `.kanban/` directory
/// gives an empty board with the name of the repo directory, and a query writes no file.
///
/// Each call runs on a working copy of the live graph. A call that keeps patches commits them at the end of the call,
/// under the lock of the board, and the working copy then becomes the live graph (plan.md §5.4).
///
/// The engine is an actor, so its state is safe. An actor can start a second call at each `await`, so the actor alone
/// does not make calls run one at a time. Thus each call also goes through a serial gate (plan.md §7.2).
///
/// When the engine loads a board, it also starts a file watcher on the `.kanban/` directory of the board, or on the
/// repo directory until `.kanban/` appears. The watcher runs until ``close()``, also when no client subscribes. Each
/// batch of changed files goes through the serial gate, so a call never sees a half-applied batch (plan.md §5.6).
///
/// The engine also reads the related boards: the boards of the other repos that the ``BoardLocator`` finds (plan.md
/// §6.6). A call loads a related board when it names the board (`Query.board(id:)`, `Query.boards`, `node(id:)` with
/// a URI of the board) or when a cross-board dependency reads it. A loaded related board stays live, with its own
/// file watcher.
public actor KanbanGraph {
    /// The root directory of the repo of the current board.
    private let root: URL

    /// Reads the key of the board from the repo.
    private let keyReader: BoardKeyReader

    /// The clock that gives the time of a change. A test gives a fixed clock (plan.md §11).
    private let clock: @Sendable () -> DateTime

    /// The session actor: the actor of each event that a call writes.
    private let sessionActor: SessionActor

    /// The source of the transaction ULIDs and the event ids, until the first call loads the board. The session of
    /// the board then continues it.
    private let idSource: any ULIDSource

    /// Finds the related boards (plan.md §6.6).
    private let locator: BoardLocator

    /// The embedder of the search of each related board, or `nil` for BM25 and trigram only.
    private let embedder: (any PooledEmbedding)?

    /// Gets a call when each call starts and ends, or `nil` for no calls.
    private let observer: (any KanbanCallObserver)?

    /// The public schema that each call runs against.
    private let schema: PublicSchema

    /// The gate that lets one call run at a time.
    private let gate = SerialGate()

    /// The subscribers of the changes of the loaded boards (plan.md §6.7).
    private let feed = ChangeFeed()

    /// The ranked search over the tasks of the current board, for the life of the engine (plan.md §6.4).
    private let search: TaskSearch

    /// Gets a call when a file watcher applies a batch, or `nil` for no calls.
    private let batchObserver: (any LiveGraphObserver)?

    /// The load state of the current board: its live graph and its commit path after the first call loads it.
    private var loadState = LoadState.notLoaded

    /// The state of the file watcher of the current board.
    private var watchState = WatchState.notStarted

    /// The state of the scan for related boards: the index of the last scan after the first scan (plan.md §6.6,
    /// index life).
    private var scanState = ScanState.notScanned

    /// The loaded related boards, by the canonical path of their repo directory.
    private var relatedBoards: [String: RelatedBoard] = [:]

    /// The file watcher of the current board while it runs, or `nil` before the first load and after ``close()``. A
    /// test also reads it to prove which directory the engine watches, and that ``close()`` stopped the watcher.
    var activeWatch: BoardWatch? {
        guard case .watching(let watch) = watchState else {
            return nil
        }
        return watch
    }

    /// `true` after ``close()``: no file watcher starts.
    private var isClosed: Bool {
        guard case .closed = watchState else {
            return false
        }
        return true
    }

    /// The public schema in the GraphQL schema definition language (SDL), generated from the Graphiti schema.
    public static var schemaSDL: String {
        do {
            return try PublicSchema().sdl
        } catch {
            preconditionFailure("The Graphiti types of the public schema are not valid: \(error)")
        }
    }

    /// Makes an engine for the board of a repo. The engine reads nothing until the first call.
    ///
    /// - Parameters:
    ///   - root: The root directory of the repo.
    ///   - actor: The name of the session actor of the mutations, or `nil` for the name of the OS user.
    ///   - locator: Finds the related boards: it holds the extra search roots (plan.md §6.6).
    ///   - embedder: The embedder of `searchTasks`, for example a `PooledEmbedder`, or `nil` for a search with BM25
    ///     and trigram only, which needs no model (plan.md §6.4).
    /// - Throws: An error from Graphiti when a type of the public schema is not valid.
    ///   ``KanbanError/invalidSlug(name:)`` when the actor name gives an empty slug.
    public init(
        root: URL,
        actor: String?,
        locator: BoardLocator = .default,
        embedder: (any PooledEmbedding)? = nil
    ) throws {
        try self.init(
            root: root,
            readingKeyWith: BoardKey.read(fromRepoAt:),
            timedBy: { DateTime(Date()) },
            actingAs: Self.sessionActor(named: actor),
            mintingFrom: SystemULIDSource(),
            locatedBy: locator,
            embeddingWith: embedder
        )
    }

    /// Makes an engine with a key reader, a clock, a session actor, a ULID source, a locator, an embedder, and
    /// observers that a test gives.
    ///
    /// - Parameters:
    ///   - root: The root directory of the repo.
    ///   - keyReader: Reads the key of the board of a repo: the current repo and each related repo.
    ///   - clock: Gives the time of a change.
    ///   - actor: The session actor.
    ///   - ids: The source of the transaction ULIDs and the event ids.
    ///   - locator: Finds the related boards. The default looks only in the parent directory of the repo.
    ///   - embedder: The embedder of `searchTasks`, or `nil` for BM25 and trigram only.
    ///   - observer: Gets a call when each call starts and ends, or `nil` for no calls.
    ///   - batchObserver: Gets a call when a file watcher applies a batch, or `nil` for no calls.
    /// - Throws: An error from Graphiti when a type of the public schema is not valid.
    init(
        root: URL,
        readingKeyWith keyReader: @escaping BoardKeyReader,
        timedBy clock: @escaping @Sendable () -> DateTime,
        actingAs actor: SessionActor,
        mintingFrom ids: any ULIDSource,
        locatedBy locator: BoardLocator = .default,
        embeddingWith embedder: (any PooledEmbedding)? = nil,
        reportingTo observer: (any KanbanCallObserver)? = nil,
        observingBatchesWith batchObserver: (any LiveGraphObserver)? = nil
    ) throws {
        self.root = root
        self.keyReader = keyReader
        self.clock = clock
        sessionActor = actor
        idSource = ids
        self.locator = locator
        self.embedder = embedder
        search = TaskSearch(embeddingWith: embedder)
        self.observer = observer
        self.batchObserver = batchObserver
        schema = try PublicSchema()
    }

    /// Gives the session actor of a name: the actor whose slug is the slug of the name, with the name (plan.md §6).
    ///
    /// - Parameter name: The name of the actor, or `nil` for the name of the OS user.
    /// - Returns: The session actor.
    /// - Throws: ``KanbanError/invalidSlug(name:)`` when the name gives an empty slug.
    static func sessionActor(named name: String?) throws(KanbanError) -> SessionActor {
        let actorName = name ?? NSUserName()
        return SessionActor(ref: .actor(slug: try Slug(columnOrActorName: actorName).value), name: actorName)
    }

    /// Runs one GraphQL document against the board (plan.md §5.4).
    ///
    /// The call waits until each earlier call of the engine is done. A GraphQL error does not throw: the response has
    /// it in `errors`. When a log of the board changed before each commit attempt, the response has the one error
    /// `BOARD_BUSY`, and the call wrote nothing.
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
        try await gate.run {
            try await self.publishingChanges(postingPlansTo: context) {
                try await self.respond(to: query, variables: variables, operationName: operationName)
            }
        }
    }

    /// Starts one GraphQL subscription against the board (plan.md §6.7, §7.2).
    ///
    /// The start goes through the serial gate, and it loads the board and each board that its `dependsOn` edges
    /// reach. The stream does not hold the gate. Each change goes to the stream as one GraphQL response: a commit of
    /// this process at once, and a change of a log file when the file watcher of its board applies it. Each response
    /// reads the board as the engine read it through the gate. A document that does not parse or validate, and a
    /// subscription that cannot start, give a stream with one response with the errors, and the stream then ends.
    /// ``close()`` ends the stream.
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
        try await gate.run {
            try await self.publishingChanges(postingPlansTo: nil) {
                try await self.startSubscription(to: query, variables: variables, operationName: operationName)
            }
        }
    }

    /// Stops all file watchers and ends all subscriptions (plan.md §7.2): the watcher of the current board and the
    /// watcher of each related board. After the call returns, a change of a file applies nothing. A later call still
    /// reads the graphs in memory, but the graphs do not follow the files any more.
    public func close() async {
        feed.finish()
        let watches = [activeWatch] + relatedBoards.values.map(\.watch)
        watchState = .closed
        for path in relatedBoards.keys {
            relatedBoards[path]?.watch = nil
        }
        for watch in watches.compactMap(\.self) {
            await watch.end()
        }
    }

    /// Runs one document inside the serial gate, and commits the patches that its mutation fields kept.
    ///
    /// - Parameters:
    ///   - query: The GraphQL document.
    ///   - variables: The values of the variables of the document.
    ///   - operationName: The operation of the document to run, or `nil`.
    /// - Returns: The response as JSON text with sorted keys.
    /// - Throws: A ``BoardKeyError``, a ``BoardWatcherError``, or an ``EventLogError`` when a board cannot load or a
    ///   commit cannot write.
    private func respond(
        to query: String,
        variables: [String: Map],
        operationName: String?
    ) async throws -> String {
        try await runSchemaCall(answeringFailureWith: { $0 }) { schema, context in
            try await schema.respond(
                to: query,
                variables: variables,
                operationName: operationName,
                formattedWith: .sortedKeys,
                context: context
            )
        }
    }

    /// Starts one subscription document inside the serial gate (plan.md §6.7).
    ///
    /// - Parameters:
    ///   - query: The subscription document.
    ///   - variables: The values of the variables of the document.
    ///   - operationName: The operation of the document to run, or `nil`.
    /// - Returns: The response of each event as JSON text with sorted keys. A subscription that cannot start gives a
    ///   stream with one response with the error.
    /// - Throws: A ``BoardKeyError``, a ``BoardWatcherError``, or an ``EventLogError`` when a board cannot load.
    private func startSubscription(
        to query: String,
        variables: [String: Map],
        operationName: String?
    ) async throws -> AsyncThrowingStream<String, Error> {
        try await runSchemaCall(answeringFailureWith: AsyncThrowingStream.single) { schema, context in
            try await schema.subscribe(
                to: query,
                variables: variables,
                operationName: operationName,
                formattedWith: .sortedKeys,
                context: context
            )
        }
    }

    /// Runs one call of the public schema on the session of the current board, and gives a ``KanbanError`` of the run
    /// or of the commit as one error response (plan.md §4.4, §5.4).
    ///
    /// - Parameters:
    ///   - wrap: Gives the output of the response JSON text of a ``KanbanError``.
    ///   - call: Runs the document against the schema and the context of one run, and gives the output.
    /// - Returns: The output of the run that committed or kept no patch, or the wrapped error response.
    /// - Throws: A ``BoardKeyError``, a ``BoardWatcherError``, or an ``EventLogError`` when a board cannot load or a
    ///   commit cannot write.
    private func runSchemaCall<Output: Sendable>(
        answeringFailureWith wrap: (String) -> Output,
        _ call: @Sendable (PublicSchema, KanbanContext) async throws -> Output
    ) async throws -> Output {
        let schema = schema
        do {
            return try await runCall { context in
                try await call(schema, context)
            }
        } catch let error as KanbanError {
            return wrap(try error.responseJSON())
        }
    }

    /// Runs one call on the session of the current board, and commits the patches that its mutation fields kept
    /// (plan.md §5.4). The call loads the related boards that it asks for.
    ///
    /// - Parameter call: Runs the document against the context of one run, and gives the response.
    /// - Returns: The response of the run that committed, or of the run that kept no patch.
    /// - Throws: A ``BoardKeyError``, a ``BoardWatcherError``, or an ``EventLogError`` when a board cannot load or a
    ///   commit cannot write. A ``KanbanError`` of the commit, for example ``KanbanError/boardBusy(attempts:)``.
    private func runCall<Response: Sendable>(
        _ call: @Sendable (KanbanContext) async throws -> Response
    ) async throws -> Response {
        await observer?.callDidStart()
        defer { observer?.callDidFinish() }
        var session = try await loadedSession()
        defer { loadState = .loaded(session) }
        let (clock, search, feed, key) = (clock, search, feed, session.key)
        return try await session.run(
            readingRelatedBoardsWith: { related, requests in
                try await self.relatedBoards(updating: related, toAnswer: requests, currentKey: key)
            },
            storingRelatedBoardsWith: { sessions, related in
                await self.storeRelatedBoards(sessions, in: related)
            },
            { store in
                try await call(KanbanContext(store: store, clock: clock, search: search, feed: feed))
            }
        )
    }

    // MARK: - Change feed

    /// Runs one operation inside the serial gate, and then sends the changes of the live graphs to the subscribers
    /// (plan.md §6.7). The changes go out also when the operation throws, because a commit check can apply the
    /// changes of a different process before the call fails.
    ///
    /// When the operation returns and a tool context is given, the same changes also give the agent plan of each
    /// board whose tasks changed (plan.md §7.3). An operation that throws posts no plan.
    ///
    /// - Parameters:
    ///   - context: The context of the tool call that gets the plans, or `nil` for no post.
    ///   - operation: The operation.
    /// - Returns: The value of the operation.
    /// - Throws: The error of the operation.
    private func publishingChanges<Value: Sendable>(
        postingPlansTo context: ToolContext?,
        _ operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        let value: Value
        do {
            value = try await operation()
        } catch {
            await publishLiveChanges(takeLiveChanges())
            throw error
        }
        let changed = takeLiveChanges()
        await publishLiveChanges(changed)
        await context?.postAgentPlans(of: changed)
        return value
    }

    /// Sends the changes of the live graph of each loaded board to the subscribers of the change feed (plan.md
    /// §6.7). With no subscriber, the changes are only dropped.
    ///
    /// Before it makes the changes, the engine loads each board that a `dependsOn` edge of a loaded board reaches, so
    /// that the derived fields read the tasks of those boards. A board that cannot load is recorded with swift-log,
    /// and the changes of the operation are then not sent.
    ///
    /// - Parameter changed: The changes of each loaded board that changed, by the canonical path of its repo
    ///   directory (``takeLiveChanges()``).
    private func publishLiveChanges(_ changed: [String: BoardChanges]) async {
        let subscribed = feed.subscribedBoards
        guard !changed.isEmpty, !subscribed.isEmpty, case .loaded(let current) = loadState else {
            return
        }
        let related: RelatedBoards
        do {
            let requests = RelatedBoards.loadable.dependencyRequests(
                of: current.live.graph,
                inBoard: current.key.description
            )
            related = try await relatedBoards(updating: .loadable, toAnswer: requests, currentKey: current.key)
        } catch {
            Log.kanban.error(
                "The change feed cannot load the boards that the dependencies reach; the changes are not sent",
                metadata: ["error": "\(error)"]
            )
            return
        }
        let sessions = loadedSessions
        let round = ChangeRound(of: changed, amongBoards: sessions, currentPath: root.canonicalPath, reading: related)
        for path in subscribed.sorted() {
            guard let session = sessions[path] else {
                assertionFailure("A subscriber observes the board at \(path), and the engine did not load it")
                Log.kanban.error(
                    "A subscriber observes a board that the engine did not load",
                    metadata: ["path": "\(path)"]
                )
                continue
            }
            feed.publish(
                round.changes(of: session, atPath: path),
                toBoardAt: path,
                readingNodesOf: round.view(of: session),
                resolvingIn: eventBoard(
                    of: session,
                    reading: eventRelatedBoards(ofBoardAt: path, in: round, currentKey: current.key)
                )
            )
        }
    }

    /// Takes the changes of the live graph of each loaded board that added events since the last call.
    ///
    /// - Returns: The changes of each board that changed, by the canonical path of its repo directory.
    private func takeLiveChanges() -> [String: BoardChanges] {
        var changed: [String: BoardChanges] = [:]
        if case .loaded(var session) = loadState {
            let changes = session.takeLiveChanges()
            loadState = .loaded(session)
            changed[root.canonicalPath] = BoardChanges(of: session, changes: changes)
        }
        for (path, board) in relatedBoards {
            var session = board.session
            let changes = session.takeLiveChanges()
            relatedBoards[path]?.session = session
            changed[path] = BoardChanges(of: session, changes: changes)
        }
        return changed
    }

    /// The session of each loaded board: the current board and each loaded related board, by the canonical path of
    /// its repo directory.
    private var loadedSessions: [String: CommitSession] {
        var sessions = relatedBoards.mapValues(\.session)
        if case .loaded(let session) = loadState {
            sessions[root.canonicalPath] = session
        }
        return sessions
    }

    /// Gives the other boards that the resolvers of the events of a board read: the boards after the operation, as
    /// that board sees them. For a related board, the related board is the current board of the value, and the
    /// current board of the engine is a related board (plan.md §6.7). Thus each key reads the board that it names.
    ///
    /// - Parameters:
    ///   - path: The canonical path of the repo directory of the board of the events.
    ///   - round: The changes of the operation.
    ///   - key: The current key of the current board.
    /// - Returns: The other boards.
    private func eventRelatedBoards(
        ofBoardAt path: String,
        in round: ChangeRound,
        currentKey key: BoardKey
    ) -> RelatedBoards {
        guard path != root.canonicalPath else {
            return round.after
        }
        return round.after.centered(onBoardAt: path, movingCurrentTo: BoardCopy(directory: root, key: key))
    }

    /// Gives the board that the resolvers of the events of a board read.
    ///
    /// - Parameters:
    ///   - session: The session of the board.
    ///   - related: The other boards as the reads see them after the operation.
    /// - Returns: The board.
    private func eventBoard(of session: CommitSession, reading related: RelatedBoards) -> EventBoard {
        EventBoard(
            work: session.makeWorkingCopy(stampedBy: EventStamp(actingAs: sessionActor.ref, mintingFrom: idSource)),
            key: session.key.description,
            source: session.source,
            related: related
        )
    }

    /// Gives the session of the current board. The first call reads the board key, starts the file watcher of the
    /// board, loads the board, and gives its tasks to the search.
    ///
    /// The watcher starts before the load. Thus, a change between the load and the start of the watcher is not lost:
    /// its batch waits for the serial gate, and then compares the files with the signatures of the load.
    ///
    /// - Returns: The session of the board.
    /// - Throws: A ``BoardKeyError`` when git cannot give the key, a ``BoardWatcherError`` when the watcher cannot
    ///   start, or an ``EventLogError`` when a log file cannot be read. The next call then tries again.
    private func loadedSession() async throws -> CommitSession {
        if case .loaded(let session) = loadState {
            return session
        }
        let key = try await keyReader(root)
        if case .notStarted = watchState {
            watchState = .watching(try startWatch(ofBoardAt: root))
        }
        return try await loadSession(at: root, key: key, searchingWith: search)
    }

    /// Loads the board of a repo, and gives its tasks to its search.
    ///
    /// - Parameters:
    ///   - directory: The root directory of the repo.
    ///   - key: The current key of the board.
    ///   - search: The ranked search over the tasks of the board.
    /// - Returns: The session of the board.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a directory or a file cannot be read.
    private func loadSession(
        at directory: URL,
        key: BoardKey,
        searchingWith search: TaskSearch
    ) async throws(EventLogError) -> CommitSession {
        let live = try await LiveGraph.load(using: BoardLoader(reading: EventLog(repositoryAt: directory)))
        let loaded = CommitSession(
            of: live,
            inBoard: key,
            actingAs: sessionActor,
            mintingFrom: idSource,
            timedBy: clock,
            searchingWith: search
        )
        await loaded.updateSearch()
        return loaded
    }

    // MARK: - Related boards

    /// Loads the related boards that a run of a call asks for, and gives the related boards of the next run (plan.md
    /// §6.6). The loop also loads each board that a cross-board dependency of a loaded board names, so that the
    /// readiness of a task of a related board reads its own dependencies. The result holds each loaded related board,
    /// also when the run asks for no board, because `undo` and `redo` with no `txn` search the loaded boards (plan.md
    /// §6.5, scope).
    ///
    /// - Parameters:
    ///   - related: The related boards of the run.
    ///   - requests: The requests of the run.
    ///   - key: The current key of the current board.
    /// - Returns: The related boards with an answer for each request, and with each loaded related board.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during a scan. A
    ///   ``BoardWatcherError`` when the watcher of a board cannot start, or an ``EventLogError`` when a log file cannot
    ///   be read.
    private func relatedBoards(
        updating related: RelatedBoards,
        toAnswer requests: Set<BoardRequest>,
        currentKey key: BoardKey
    ) async throws -> RelatedBoards {
        var updated = withLoadedBoards(related)
        var pending = requests.union(updated.loadedDependencyRequests)
        while !pending.isEmpty {
            for request in pending where !updated.satisfies([request]) {
                try await answer(request, in: &updated, currentKey: key)
            }
            updated = withLoadedBoards(updated)
            pending = updated.loadedDependencyRequests.filter { request in !updated.satisfies([request]) }
        }
        return updated
    }

    /// Stores the sessions of the related boards after a commit attempt of a call (plan.md §5.4 step 5, §6.6), and
    /// gives the related boards of the next run.
    ///
    /// After a commit, the session holds the new live graph and the new file signatures, so that the file watcher of
    /// the board finds no change for the write of this process. After a changed log, the session holds the changed
    /// files, so that the next run reads them.
    ///
    /// - Parameters:
    ///   - sessions: The session of each related board that the call changed, by the canonical path of its repo
    ///     directory.
    ///   - related: The related boards of the run.
    /// - Returns: The related boards with the stored sessions.
    private func storeRelatedBoards(
        _ sessions: [String: CommitSession],
        in related: RelatedBoards
    ) async -> RelatedBoards {
        for (path, session) in sessions {
            guard relatedBoards[path] != nil else {
                assertionFailure("A call changed the related board at \(path), and the engine did not load it")
                Log.kanban.error(
                    "A call changed a related board that the engine did not load",
                    metadata: ["path": "\(path)"]
                )
                continue
            }
            relatedBoards[path]?.session = session
            await session.updateSearch()
        }
        return withLoadedBoards(related)
    }

    /// Gives the related boards of a run with the session of each loaded related board and the places of the scan.
    ///
    /// - Parameter related: The related boards of the run.
    /// - Returns: The related boards with the loaded boards.
    private func withLoadedBoards(_ related: RelatedBoards) -> RelatedBoards {
        var updated = related
        updated.install(boards: relatedBoards.mapValues(\.session), searchRoots: locator.places(around: root))
        return updated
    }

    /// Answers one request: resolves the board ref or scans for the list, and loads each board that the answer
    /// names.
    ///
    /// - Parameters:
    ///   - request: The request.
    ///   - related: The related boards that get the answer.
    ///   - key: The current key of the current board.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during the scan. A
    ///   ``BoardWatcherError`` or an ``EventLogError`` when a board cannot load.
    private func answer(
        _ request: BoardRequest,
        in related: inout RelatedBoards,
        currentKey key: BoardKey
    ) async throws {
        switch request {
        case .board(let reference):
            related.record(try await loadBoard(named: reference, currentKey: key), forBoard: reference)
        case .allCopies:
            related.record(listing: try await loadEachCopy())
        }
    }

    /// Finds the board that a board ref names, and loads it when it is a related board.
    ///
    /// - Parameters:
    ///   - reference: The board ref.
    ///   - key: The current key of the current board.
    /// - Returns: The board.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during the scan. A
    ///   ``BoardWatcherError`` or an ``EventLogError`` when the board cannot load.
    private func loadBoard(named reference: String, currentKey key: BoardKey) async throws -> BoardResolution {
        let resolution = try await resolution(of: reference, currentKey: key)
        if case .copy(let copy) = resolution {
            try await loadRelatedBoard(copy)
        }
        return resolution ?? .notFound
    }

    /// Finds the board that a board ref names in the index of the scan (plan.md §6.6, index life). The first call
    /// scans. A later call whose ref names no copy of the index scans one more time.
    ///
    /// - Parameters:
    ///   - reference: The board ref.
    ///   - key: The current key of the current board.
    /// - Returns: The board, or `nil` when no copy of the index has the ref.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during the scan.
    private func resolution(
        of reference: String,
        currentKey key: BoardKey
    ) async throws(BoardKeyError) -> BoardResolution? {
        let root = root
        let resolve = { (index: BoardIndex) in index.resolution(of: reference, currentRoot: root, currentKey: key) }
        if case .scanned(let index) = scanState, let found = resolve(index) {
            return found
        }
        return resolve(try await rescan())
    }

    /// Scans for the copies of `Query.boards`, and loads each copy that is not the current repo.
    ///
    /// - Returns: The copies, in scan order.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during the scan. A
    ///   ``BoardWatcherError`` or an ``EventLogError`` when a board cannot load.
    private func loadEachCopy() async throws -> [ListedCopy] {
        let index = try await rescan()
        let resolutions = index.copies.map { copy in index.resolution(of: copy, currentRoot: root) }
        for case .copy(let copy) in resolutions {
            try await loadRelatedBoard(copy)
        }
        return zip(resolutions, index.copies).map { resolution, copy in
            ListedCopy(board: resolution, isEnabled: copy.isEnabled)
        }
    }

    /// Scans the places for repos, and records the new index. A repo of the earlier scan keeps its key.
    ///
    /// - Returns: The new index.
    /// - Throws: ``BoardKeyError/gitCancelled(arguments:)`` when the task is cancelled during the scan. Then the
    ///   engine keeps the earlier index, and the next scan reads each key that the cancel stopped.
    private func rescan() async throws(BoardKeyError) -> BoardIndex {
        let earlier: BoardIndex? =
            switch scanState {
            case .notScanned: nil
            case .scanned(let index): index
            }
        let scanned = try await locator.scan(around: root, reusing: earlier, readingKeysWith: keyReader)
        scanState = .scanned(scanned)
        return scanned
    }

    /// Loads a related board and starts its file watcher, when the board is not loaded yet. After ``close()``, the
    /// board loads with no watcher.
    ///
    /// - Parameter copy: The copy of the related repo.
    /// - Throws: A ``BoardWatcherError`` when the watcher cannot start, or an ``EventLogError`` when a log file cannot
    ///   be read. Then the board is not loaded.
    private func loadRelatedBoard(_ copy: BoardCopy) async throws {
        let path = copy.directory.canonicalPath
        guard relatedBoards[path] == nil else {
            return
        }
        let watch = isClosed ? nil : try startWatch(ofBoardAt: copy.directory)
        do {
            let search = TaskSearch(embeddingWith: embedder)
            let session = try await loadSession(at: copy.directory, key: copy.key, searchingWith: search)
            relatedBoards[path] = RelatedBoard(session: session, watch: watch)
        } catch {
            await watch?.end()
            throw error
        }
    }

    // MARK: - File watcher

    /// Starts a file watcher on a board: on its `.kanban/` directory, or on the repo directory when `.kanban/` is not
    /// there.
    ///
    /// - Parameter directory: The root directory of the repo of the board.
    /// - Returns: The watch.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when the watcher cannot start.
    private func startWatch(ofBoardAt directory: URL) throws(BoardWatcherError) -> BoardWatch {
        try startWatch(on: Self.existingBoardDirectory(ofBoardAt: directory) ?? directory, ofBoardAt: directory)
    }

    /// Gives the `.kanban/` directory of a board when it is there.
    ///
    /// - Parameter directory: The root directory of the repo of the board.
    /// - Returns: The `.kanban/` directory, or `nil` when the repo has no `.kanban/` directory yet.
    private static func existingBoardDirectory(ofBoardAt directory: URL) -> URL? {
        let boardDirectory = EventLog(repositoryAt: directory).directory
        guard FileManager.default.fileExists(atPath: boardDirectory.path) else {
            return nil
        }
        return boardDirectory
    }

    /// Starts a file watcher on a directory of a board, and a task that gives each batch of the watcher to
    /// ``receive(_:ofBoardAt:)``. The task holds the engine weakly, so the watcher does not keep the engine alive.
    ///
    /// - Parameters:
    ///   - directory: The `.kanban/` directory of the board, or the repo directory when `.kanban/` is not there.
    ///   - root: The root directory of the repo of the board.
    /// - Returns: The watch.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when the watcher cannot start.
    private func startWatch(on directory: URL, ofBoardAt root: URL) throws(BoardWatcherError) -> BoardWatch {
        let watcher = try BoardWatcher(watching: directory)
        let batches = watcher.batches
        let consumer = Task { [weak self] in
            for await paths in batches {
                await self?.receive(paths, ofBoardAt: root)
            }
        }
        return BoardWatch(watcher: watcher, directory: directory, consumer: consumer)
    }

    /// Gives one batch of a file watcher to the serial gate (plan.md §5.6, batch). A batch that cannot apply is
    /// recorded with swift-log. The live graph then does not change, and the commit check still finds the change.
    ///
    /// - Parameters:
    ///   - paths: The changed paths of the batch.
    ///   - directory: The root directory of the repo of the board of the watcher.
    private func receive(_ paths: [URL], ofBoardAt directory: URL) async {
        do {
            try await gate.run {
                try await self.publishingChanges(postingPlansTo: nil) {
                    try await self.applyBatch(paths, ofBoardAt: directory)
                }
            }
        } catch {
            Log.kanban.error(
                "The file watcher cannot apply a batch of changed files",
                metadata: ["paths": "\(paths.map(\.path))", "error": "\(error)"]
            )
        }
    }

    /// Applies one batch of a file watcher to the live graph of its board, inside the serial gate (plan.md §5.6).
    ///
    /// - Parameters:
    ///   - paths: The changed paths of the batch.
    ///   - directory: The root directory of the repo of the board of the watcher.
    /// - Throws: A ``BoardWatcherError`` when the watcher cannot move, or an ``EventLogError`` when a file cannot be
    ///   read.
    private func applyBatch(_ paths: [URL], ofBoardAt directory: URL) async throws {
        guard directory != root else {
            return try await applyCurrentBatch(paths)
        }
        let path = directory.canonicalPath
        guard var board = relatedBoards[path], let watch = board.watch else {
            return
        }
        try await apply(paths, to: &board.session, watchedBy: watch, ofBoardAt: directory) { moved in
            relatedBoards[path]?.watch = moved
        }
        relatedBoards[path]?.session = board.session
    }

    /// Applies one batch of the file watcher of the current board.
    ///
    /// - Parameter paths: The changed paths of the batch.
    /// - Throws: A ``BoardWatcherError`` when the watcher cannot move, or an ``EventLogError`` when a file cannot be
    ///   read.
    private func applyCurrentBatch(_ paths: [URL]) async throws {
        guard let watch = activeWatch, case .loaded(var session) = loadState else {
            return
        }
        defer { loadState = .loaded(session) }
        try await apply(paths, to: &session, watchedBy: watch, ofBoardAt: root) { moved in
            watchState = .watching(moved)
        }
    }

    /// Moves the file watcher of a board to `.kanban/` when `.kanban/` appeared, and then applies one batch to the
    /// session of the board.
    ///
    /// The engine stores the new watch before the apply, so the new watch stays also when the apply fails.
    ///
    /// - Parameters:
    ///   - paths: The changed paths of the batch.
    ///   - session: The session of the board.
    ///   - watch: The watch of the board.
    ///   - directory: The root directory of the repo of the board.
    ///   - store: Stores the new watch of the board when the watcher moved.
    /// - Throws: A ``BoardWatcherError`` when the watcher cannot move, or an ``EventLogError`` when a file cannot be
    ///   read.
    private func apply(
        _ paths: [URL],
        to session: inout CommitSession,
        watchedBy watch: BoardWatch,
        ofBoardAt directory: URL,
        storingMovedWatchWith store: (BoardWatch) -> Void
    ) async throws {
        let moved = try await movedWatch(watch, ofBoardAt: directory)
        if let moved {
            store(moved)
        }
        try await apply(paths, to: &session, afterMove: moved != nil)
    }

    /// Applies the changed paths of one batch to the session of a board, and tells the batch observer.
    ///
    /// When the watcher moved to `.kanban/`, the batch also holds the `.kanban/` directory, so that it compares each
    /// file of the board.
    ///
    /// - Parameters:
    ///   - paths: The changed paths of the batch.
    ///   - session: The session of the board.
    ///   - didMove: `true` when the watcher of the board moved to `.kanban/` for this batch.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a file cannot be read.
    private func apply(
        _ paths: [URL],
        to session: inout CommitSession,
        afterMove didMove: Bool
    ) async throws(EventLogError) {
        let boardDirectory = session.live.log.directory
        let applied = try await session.apply(watchedPaths: didMove ? paths + [boardDirectory] : paths)
        guard !applied.isEmpty else {
            return
        }
        batchObserver?.didApply(changedPaths: applied)
    }

    /// Moves a file watcher from the repo directory to the `.kanban/` directory, when the watcher watches the repo
    /// directory and `.kanban/` is there now (plan.md §5.6, a repo with no `.kanban/` yet). The new watcher starts
    /// before the old one stops, so no change is lost.
    ///
    /// - Parameters:
    ///   - watch: The watch of the board.
    ///   - directory: The root directory of the repo of the board.
    /// - Returns: The new watch, or `nil` when the watcher did not move.
    /// - Throws: ``BoardWatcherError/streamNotStarted(path:)`` when the new watcher cannot start. Then the old
    ///   watcher stays.
    private func movedWatch(
        _ watch: BoardWatch,
        ofBoardAt directory: URL
    ) async throws(BoardWatcherError) -> BoardWatch? {
        guard
            watch.directory == directory,
            let boardDirectory = Self.existingBoardDirectory(ofBoardAt: directory)
        else {
            return nil
        }
        let moved = try startWatch(on: boardDirectory, ofBoardAt: directory)
        await watch.watcher.stop()
        return moved
    }
}

// MARK: - Load state

/// The load state of the current board of a ``KanbanGraph`` (plan.md §5.3).
private enum LoadState {
    /// No call loaded the board yet.
    case notLoaded

    /// A call loaded the board: the live graph of the board and its commit path.
    case loaded(CommitSession)
}

// MARK: - Scan state

/// The state of the scan for the related boards of a ``KanbanGraph`` (plan.md §6.6, index life).
private enum ScanState {
    /// No call scanned yet.
    case notScanned

    /// A call scanned: the index of the last scan.
    case scanned(BoardIndex)
}

// MARK: - Watch state

/// The state of the file watcher of the current board of a ``KanbanGraph`` (plan.md §5.6).
private enum WatchState {
    /// No call loaded the board yet, so no watcher runs.
    case notStarted

    /// The watcher runs.
    case watching(BoardWatch)

    /// ``KanbanGraph/close()`` stopped the watchers. No watcher starts again, and a batch that comes now changes
    /// nothing.
    case closed
}

// MARK: - Related board

/// A loaded related board of a ``KanbanGraph``, and its file watcher (plan.md §5.6, §6.6).
private struct RelatedBoard {
    /// The live graph of the board and its commit path.
    var session: CommitSession

    /// The file watcher of the board, or `nil` after ``KanbanGraph/close()``.
    var watch: BoardWatch?
}

// MARK: - Board watch

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

// MARK: - Session actor

/// The session actor of an engine: the actor of each event that a call writes (plan.md §6).
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

/// Gets a call when a file watcher of a ``KanbanGraph`` applies a batch to a live graph, inside the serial gate.
///
/// A test uses it to count the applies and to wait for a batch. A batch whose files all have their recorded
/// signatures (for example the write of this process) applies nothing and gives no call.
protocol LiveGraphObserver: Sendable {
    /// Tells that a batch changed a live graph.
    ///
    /// - Parameter paths: The node files that the apply read again, in the sort order of their refs.
    func didApply(changedPaths paths: [URL])
}

/// An async queue that runs one operation at a time, in the order that the operations arrive (plan.md §7.2).
///
/// An actor alone does not do this: it can start a second call at each `await` of the first call. The gate keeps
/// the operations that wait in a queue, and starts the next one only when the current one ends.
actor SerialGate {
    /// `true` while an operation runs.
    private var isBusy = false

    /// The operations that wait, in the order that they arrived.
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Runs an operation after each earlier operation of the gate ends.
    ///
    /// - Parameter operation: The operation.
    /// - Returns: The result of the operation.
    /// - Throws: The error of the operation. The gate then lets the next operation run.
    func run<Value: Sendable>(serially operation: @Sendable () async throws -> Value) async rethrows -> Value {
        await enter()
        defer { leave() }
        return try await operation()
    }

    /// Waits until no operation runs, then marks the gate busy.
    private func enter() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiter in waiters.append(waiter) }
    }

    /// Gives the gate to the next operation that waits, or marks the gate free.
    private func leave() {
        guard !waiters.isEmpty else {
            isBusy = false
            return
        }
        waiters.removeFirst().resume()
    }
}
