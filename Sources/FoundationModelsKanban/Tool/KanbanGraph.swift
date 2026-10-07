import Foundation
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
public actor KanbanGraph {
    /// The root directory of the repo of the current board.
    private let root: URL

    /// Reads the key of the board from the repo.
    private let keyReader: @Sendable (URL) throws(BoardKeyError) -> BoardKey

    /// The clock that gives the time of a change. A test gives a fixed clock (plan.md §11).
    private let clock: @Sendable () -> DateTime

    /// The session actor: the actor of each event that a call writes.
    private let sessionActor: SessionActor

    /// The source of the transaction ULIDs and the event ids, until the first call loads the board. The session of
    /// the board then continues it.
    private let idSource: any ULIDSource

    /// Gets a call when each call starts and ends, or `nil` for no calls.
    private let observer: (any KanbanCallObserver)?

    /// The public schema that each call runs against.
    private let schema: PublicSchema

    /// The gate that lets one call run at a time.
    private let gate = SerialGate()

    /// The live graph of the current board and its commit path, or `nil` until the first call loads the board.
    private var session: CommitSession?

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
    /// - Throws: An error from Graphiti when a type of the public schema is not valid.
    ///   ``KanbanError/invalidSlug(name:)`` when the actor name gives an empty slug.
    public init(root: URL, actor: String?) throws {
        try self.init(
            root: root,
            readingKeyWith: BoardKey.read(fromRepoAt:),
            timedBy: { DateTime(Date()) },
            actingAs: Self.sessionActor(named: actor),
            mintingFrom: SystemULIDSource()
        )
    }

    /// Makes an engine with a key reader, a clock, a session actor, a ULID source, and an observer that a test gives.
    ///
    /// - Parameters:
    ///   - root: The root directory of the repo.
    ///   - keyReader: Reads the key of the board from the repo.
    ///   - clock: Gives the time of a change.
    ///   - actor: The session actor.
    ///   - ids: The source of the transaction ULIDs and the event ids.
    ///   - observer: Gets a call when each call starts and ends, or `nil` for no calls.
    /// - Throws: An error from Graphiti when a type of the public schema is not valid.
    init(
        root: URL,
        readingKeyWith keyReader: @escaping @Sendable (URL) throws(BoardKeyError) -> BoardKey,
        timedBy clock: @escaping @Sendable () -> DateTime,
        actingAs actor: SessionActor,
        mintingFrom ids: any ULIDSource,
        reportingTo observer: (any KanbanCallObserver)? = nil
    ) throws {
        self.root = root
        self.keyReader = keyReader
        self.clock = clock
        sessionActor = actor
        idSource = ids
        self.observer = observer
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
    /// - Throws: An I/O fault only: a ``BoardKeyError`` when git cannot give the board key, or an ``EventLogError``
    ///   when a log file cannot be read, locked, or written.
    public func execute(query: String, variables: [String: Map], operationName: String?) async throws -> String {
        try await gate.run {
            try await self.respond(to: query, variables: variables, operationName: operationName)
        }
    }

    /// Runs one document inside the serial gate, and commits the patches that its mutation fields kept.
    ///
    /// - Parameters:
    ///   - query: The GraphQL document.
    ///   - variables: The values of the variables of the document.
    ///   - operationName: The operation of the document to run, or `nil`.
    /// - Returns: The response as JSON text with sorted keys.
    /// - Throws: A ``BoardKeyError`` or an ``EventLogError`` when the board cannot load or a commit cannot write.
    private func respond(
        to query: String,
        variables: [String: Map],
        operationName: String?
    ) async throws -> String {
        await observer?.callDidStart()
        defer { observer?.callDidFinish() }
        var session = try await loadedSession()
        defer { self.session = session }
        let schema = schema
        let clock = clock
        do {
            return try await session.run { store in
                try await schema.respond(
                    to: query,
                    variables: variables,
                    operationName: operationName,
                    formattedWith: .sortedKeys,
                    context: KanbanContext(store: store, clock: clock)
                )
            }
        } catch let error as KanbanError {
            return try error.responseJSON()
        }
    }

    /// Gives the session of the current board. The first call reads the board key and loads the board.
    ///
    /// - Returns: The session of the board.
    /// - Throws: A ``BoardKeyError`` when git cannot give the key, or an ``EventLogError`` when a log file cannot be
    ///   read. The next call then tries again.
    private func loadedSession() async throws -> CommitSession {
        if let session {
            return session
        }
        let key = try keyReader(root)
        let live = try await LiveGraph.load(using: BoardLoader(reading: EventLog(repositoryAt: root)))
        return CommitSession(of: live, inBoard: key, actingAs: sessionActor, mintingFrom: idSource, timedBy: clock)
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
