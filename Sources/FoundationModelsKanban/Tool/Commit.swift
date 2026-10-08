import Foundation
import OrderedCollections
import ULID

// MARK: - Event stamp

/// The envelope values of the events of one run of a call: the transaction, the actor, and the event ids (plan.md
/// §5.1, §5.4 step 4.2).
///
/// The event ids of one run increase. Replay sorts the events by id, and two patches of one body must apply in the
/// order that the call made them. A ULID source can give an id that is not larger than the last one (a system clock
/// that goes back, or two random ids in one millisecond). The stamp then gives the id after the last one.
struct EventStamp: Sendable {
    /// The transaction ULID of the run. All patches of the run have it (plan.md §6.5).
    let txn: ULID

    /// The local ref of the actor of the call, in the board of the log.
    let actor: LocalRef

    /// The source of the event ids. The caller takes it back after the run, so that the next run continues it.
    private(set) var ids: any ULIDSource

    /// The last id that the stamp gave: the transaction ULID, or the id of the last event.
    private var lastID: ULID

    /// Makes the stamp of one run, and mints its transaction ULID.
    ///
    /// - Parameters:
    ///   - actor: The local ref of the actor of the call.
    ///   - ids: The source of the transaction ULID and the event ids.
    init(actingAs actor: LocalRef, mintingFrom ids: any ULIDSource) {
        var source = ids
        txn = source.makeULID()
        self.actor = actor
        self.ids = source
        lastID = txn
    }

    /// Makes the event of one patch. The event has no `ops` yet: the commit writes the `ops` of the full call.
    ///
    /// - Parameters:
    ///   - patch: The patch.
    ///   - time: The time of the change.
    ///   - target: The transaction that the patch reverses, for a patch of `undo` and `redo`, else `nil`.
    /// - Returns: The event, with an id larger than each id that the stamp gave before.
    mutating func makeEvent(of patch: PatchInput, at time: DateTime, undoing target: ULID?) -> Event {
        Event(id: nextID(), txn: txn, ops: [], at: time, actor: actor, undoes: target, patch: patch)
    }

    /// Mints the ULID of a new node from the source of the event ids (the mint rule of plan.md §3.2).
    ///
    /// - Parameter existing: The short ids that are already in the board.
    /// - Returns: The first ULID of the source whose short id is not in `existing`.
    mutating func mintULID(avoiding existing: Set<ShortID>) -> ULID {
        ids.makeULID(avoiding: existing)
    }

    /// Gives the next event id: the next id of the source, or the id after the last one when the source gives an id
    /// that is not larger.
    ///
    /// - Returns: The id.
    private mutating func nextID() -> ULID {
        let minted = ids.makeULID()
        lastID = minted > lastID ? minted : lastID.successor
        return lastID
    }
}

extension ULID {
    /// The ULID after this one in sort order: the 128-bit value plus one.
    fileprivate var successor: ULID {
        var bytes = Array(ulidData)
        for index in bytes.indices.reversed() {
            let (sum, overflow) = bytes[index].addingReportingOverflow(1)
            bytes[index] = sum
            guard overflow else {
                break
            }
        }
        return ULID(ulidData: Data(bytes)) ?? self
    }
}

// MARK: - Working copy

/// The working copy of one run of a call (plan.md §5.4 steps 2 and 4, §12 item 25).
///
/// The working copy starts as a copy-on-write copy of the live graph. Each mutation field runs with
/// ``runField(as:reading:_:)``: it makes patches, applies them with ``apply(_:at:undoing:)``, checks the graph rules,
/// and keeps the patches. A field that throws discards only its own patches and its own changes to the graph. The
/// live graph does not change until the commit succeeds.
struct WorkingCopy: Sendable {
    /// The graph after the kept patches.
    private(set) var graph: Graph

    /// The events of the live graph, in the order of their ids: the global event list of the board. The working copy
    /// reads the events of a node from it the first time that a patch changes the node, and `Board.history` reads the
    /// transactions from it (plan.md §6.5).
    let liveEvents: [Event]

    /// The events of each node that a kept patch changed: the live events of the node plus the kept events, in the
    /// order of their ids.
    private var nodeEvents: [LocalRef: [Event]] = [:]

    /// The kept events of the run, in the order that the fields made them.
    private(set) var kept: [Event] = []

    /// The names of the mutation fields that kept a patch, in call order, each one time. The commit writes them as
    /// the `ops` of each event.
    private(set) var operations: OrderedSet<String> = []

    /// The envelope values of the events of the run.
    private(set) var stamp: EventStamp

    /// The local ref of the session actor when it is a live actor of the graph at the start of the run, else `nil`.
    /// An `addTask` with no assignee assigns this actor (plan.md §6, "Assignees"). An actor that the call itself makes
    /// is not known before the call, so it is not assigned.
    let knownSessionActor: LocalRef?

    /// The other boards as the graph rules of a field read them: the related boards of the run, with the working
    /// graph of each board that the run changed (plan.md §3.3 rule 6, §6.6). ``runField(as:reading:_:)`` gives them
    /// to each field. A working copy that runs no field reads no other board.
    private(set) var otherBoards = RelatedBoards.unavailable

    /// The canonical paths of the repo directories of the other boards that a graph rule of a kept field read. The
    /// commit locks and checks these boards too (plan.md §5.4 steps 4.4 and 5.1).
    private(set) var readBoards: Set<String> = []

    /// Makes the working copy of a run.
    ///
    /// - Parameters:
    ///   - graph: The graph at the start of the run. Each node must be the fold of its events in `events`.
    ///   - events: The events of the graph, in the order of their ids.
    ///   - stamp: The envelope values of the events of the run. Its actor is the session actor.
    init(graph: Graph, events: [Event], stamp: EventStamp) {
        self.graph = graph
        liveEvents = events
        self.stamp = stamp
        let isKnown = graph.node(for: stamp.actor)?.state.fields.isDeleted == false
        knownSessionActor = isKnown ? stamp.actor : nil
    }

    /// Runs one mutation field on the working copy (plan.md §5.4 step 4).
    ///
    /// The body works on a copy-on-write copy of the working copy. When the body returns, the copy becomes the
    /// working copy. When the body throws, the copy is discarded, so the field keeps none of its patches.
    ///
    /// - Parameters:
    ///   - operation: The name of the public mutation of the field, for the `ops` of the events, or `nil` for a
    ///     field that is not a public mutation (the internal `patch` mutation).
    ///   - boards: The other boards as the graph rules of the field read them.
    ///   - body: Makes and applies the patches of the field, and checks the graph rules.
    /// - Returns: The value of the body.
    /// - Throws: The error of the body. Then the working copy does not change.
    mutating func runField<Value, Failure: Error>(
        as operation: String?,
        reading boards: RelatedBoards,
        _ body: (inout WorkingCopy) throws(Failure) -> Value
    ) throws(Failure) -> Value {
        var field = self
        field.otherBoards = boards
        let value = try body(&field)
        if let operation, field.kept.count > kept.count {
            field.operations.append(operation)
        }
        self = field
        return value
    }

    /// Runs one mutation field on the working copy of a different board of the call: a related board (plan.md
    /// §6.6, one transaction, many boards).
    ///
    /// The field continues the stamp of this working copy, so all patches of the call have one `txn` and their
    /// event ids increase over all boards. This working copy records the operation of the field, because it holds
    /// the `ops` of the full call. When the body throws, neither working copy changes.
    ///
    /// - Parameters:
    ///   - operation: The name of the public mutation of the field, for the `ops` of the events.
    ///   - other: The working copy of the board that the field changes.
    ///   - boards: The other boards as the graph rules of the field read them.
    ///   - body: Makes and applies the patches of the field, and checks the graph rules.
    /// - Returns: The value of the body.
    /// - Throws: The error of the body. Then the two working copies do not change.
    mutating func runField<Value, Failure: Error>(
        as operation: String,
        on other: inout WorkingCopy,
        reading boards: RelatedBoards,
        _ body: (inout WorkingCopy) throws(Failure) -> Value
    ) throws(Failure) -> Value {
        var field = other
        field.stamp = stamp
        field.otherBoards = boards
        let value = try body(&field)
        if field.kept.count > other.kept.count {
            operations.append(operation)
        }
        stamp = field.stamp
        other = field
        return value
    }

    /// Mints the ULID of a new task or comment: its short id is unique among the tasks and the comments of the graph,
    /// live or tombstoned (plan.md §3.2, mint rule). A call that runs again after a changed log mints from the new
    /// live graph, so a node that a different process wrote keeps its short id (plan.md §5.4 step 5.2).
    ///
    /// - Returns: The ULID.
    mutating func mintULID() -> ULID {
        stamp.mintULID(avoiding: graph.shortIDs)
    }

    /// Tells if the log has the node of a ref: a live event or a kept event changed it.
    ///
    /// The graph alone does not tell this. The graph of a repo with no board log holds an empty board in memory.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: `true` when an event changed the node.
    func hasEvents(of ref: LocalRef) -> Bool {
        nodeEvents[ref] != nil || liveEvents.contains { event in event.patch.node == ref }
    }

    /// Records the other boards that a graph rule of the field read, so that the commit locks and checks them
    /// (plan.md §5.4 steps 4.4 and 5.1).
    ///
    /// - Parameter paths: The canonical paths of the repo directories of the boards.
    mutating func record(readBoards paths: Set<String>) {
        readBoards.formUnion(paths)
    }

    /// Applies one patch to the working copy (plan.md §5.4 steps 4.2 and 4.3).
    ///
    /// The patch keeps only the parts that change the node (``PatchInput/changes(afterFolding:)``). A patch that
    /// changes nothing is not kept. Else the working copy makes its event, folds the node again from all its events,
    /// and puts the new state in the slot of the node. Thus, the graph is the state that a replay after the commit
    /// gives.
    ///
    /// - Parameters:
    ///   - patch: The patch.
    ///   - time: The time of the change. It becomes the `at` of the event.
    ///   - target: The transaction that the patch reverses, for a patch of `undo` and `redo`. It becomes the
    ///     `undoes` of the event. The default is `nil`.
    /// - Throws: An ``EventError`` from the change of the patch. A valid patch gives no error.
    mutating func apply(_ patch: PatchInput, at time: DateTime, undoing target: ULID? = nil) throws(EventError) {
        let ref = patch.node
        let events = nodeEvents[ref] ?? liveEvents.filter { event in event.patch.node == ref }
        guard let change = try patch.changes(afterFolding: events) else {
            return
        }
        let event = stamp.makeEvent(of: change, at: time, undoing: target)
        nodeEvents[ref] = graph.update(folding: events + [event], for: ref)
        kept.append(event)
    }
}

// MARK: - Commit session

/// The live graph of one board, and the commit path of the calls of the board (plan.md §5.4 steps 2 to 6).
///
/// Each run of a call gets a new working copy of the live graph. At the end of the run, a call that kept patches
/// commits them: under the lock of the board, the session compares the signature of each log file and the list of
/// node files with the live graph. When a log changed, the session applies the changed files to the live graph,
/// discards the working copy, and runs the call again. After ``maximumRuns`` changed runs, the call fails with
/// ``KanbanError/boardBusy(attempts:)``. Else the session appends the kept patches, records the new signatures, and
/// the working copy becomes the live graph.
struct CommitSession: Sendable {
    /// The largest number of runs of one call. Each run after the first comes from a log that changed before the
    /// commit (plan.md §5.4 step 5.2).
    static let maximumRuns = 5

    /// The live graph of the board.
    private(set) var live: LiveGraph

    /// The key of the board. It orders the locks (plan.md §5.4 step 5.1), and the engine resolves the board refs of
    /// the related boards with it (plan.md §6.6).
    let key: BoardKey

    /// The session actor: the actor of each event.
    private let actor: SessionActor

    /// The source of the transaction ULIDs and the event ids.
    private var ids: any ULIDSource

    /// The clock that gives the time of an empty board.
    private let clock: @Sendable () -> DateTime

    /// The ranked search over the tasks of the board. The session updates it after each change of the live graph.
    private let search: TaskSearch

    /// Makes the session of a loaded board.
    ///
    /// - Parameters:
    ///   - live: The live graph of the board.
    ///   - key: The key of the board.
    ///   - actor: The session actor.
    ///   - ids: The source of the transaction ULIDs and the event ids.
    ///   - clock: The clock that gives the time of an empty board.
    ///   - search: The ranked search over the tasks of the board.
    init(
        of live: LiveGraph,
        inBoard key: BoardKey,
        actingAs actor: SessionActor,
        mintingFrom ids: any ULIDSource,
        timedBy clock: @escaping @Sendable () -> DateTime,
        searchingWith search: TaskSearch
    ) {
        self.live = live
        self.key = key
        self.actor = actor
        self.ids = ids
        self.clock = clock
        self.search = search
    }

    /// Gives the live tasks of the board to the search (plan.md §6.4, life of the searcher). The searcher embeds again
    /// only the tasks that changed.
    func updateSearch() async {
        await search.update(from: BoardView(of: live.graph, inBoard: key.description))
    }

    /// Applies one batch of the file watcher to the live graph, and then updates the search (plan.md §5.6, batch).
    ///
    /// A file whose signature equals the recorded signature is not read again: a write of this process, or a
    /// repeated event. A batch with no other file changes nothing, and the search does not change. A batch that holds
    /// the `.kanban/` directory itself (FSEvents dropped events, or the directory appeared) compares each node file
    /// of the board, and not only the paths of the batch.
    ///
    /// - Parameter paths: The changed paths of the batch.
    /// - Returns: The node files that the apply read again, in the sort order of their refs. The list is empty when
    ///   no file changed.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a directory or a file cannot be read. Then the live
    ///   graph does not change.
    mutating func apply(watchedPaths paths: [URL]) async throws(EventLogError) -> [URL] {
        let isFullCheck = paths.contains(where: live.log.isBoardDirectory(at:))
        let refs = isFullCheck ? try live.changedRefs() : try live.changedRefs(among: paths)
        guard !refs.isEmpty else {
            return []
        }
        let files = refs.sorted { lhs, rhs in lhs.description < rhs.description }.map(live.log.fileURL(for:))
        _ = try await live.apply(changedPaths: files)
        await updateSearch()
        return files
    }

    /// The root directory of the repo of the board.
    private var directory: URL {
        live.log.directory.deletingLastPathComponent()
    }

    /// The directory, the search, and the events of the board, for its read views.
    var source: BoardSource {
        BoardSource(directory: directory, search: search, events: live.events)
    }

    /// The board as a read of a related board sees it: the live graph, with an empty board in memory when the board
    /// has no board node (plan.md §6.6, board name).
    var snapshot: BoardSnapshot {
        BoardSnapshot(key: key.description, graph: displayGraph, source: source)
    }

    /// The live graph, with an empty board in memory with the name of the repo directory when the board has no board
    /// node.
    private var displayGraph: Graph {
        live.graph.withBoard(named: directory.lastPathComponent, at: clock())
    }

    /// Runs one call on a working copy of the live graph, and commits the patches that the call kept (plan.md §5.4).
    ///
    /// A call that keeps no patch writes nothing and takes no lock (plan.md §5.4 step 6). A run that finds a changed
    /// log discards its response, and the call runs again on the new live graph.
    ///
    /// Before the first run, the loader loads the related boards that the cross-board dependencies of the live graph
    /// name (plan.md §6.6). A run that asks for a related board that the loader did not load, for example a board
    /// ref of `Query.board` or a dependency that the run adds, discards its response: the loader loads the board,
    /// and the call runs again before it commits.
    ///
    /// A call that changes related boards (plan.md §6.6) commits all boards together: one lock of each changed
    /// board and of each board that a graph rule of the call read, in the sort order of the board key, one check of
    /// each of these boards under the locks, and then the append to each changed board. The engine gets the related
    /// sessions after each commit attempt.
    ///
    /// - Parameters:
    ///   - load: Loads the related boards of some requests, and gives the new related boards of the run. The value
    ///     must answer each request. The default loads no board, so the run reads no related board.
    ///   - store: Stores the sessions of the related boards that a commit attempt changed, and gives the new related
    ///     boards of the next run. The default stores nothing.
    ///   - call: Runs the call against the store of the working copy, and gives the response.
    /// - Returns: The response of the run that committed, or of the run that kept no patch.
    /// - Throws: ``KanbanError/boardBusy(attempts:)`` when a log changed before the commit of each of the
    ///   ``maximumRuns`` runs. Then the call wrote nothing. An ``EventLogError`` when a log file cannot be read,
    ///   locked, or written. An error of the loader. The error of the call.
    mutating func run<Response: Sendable>(
        readingRelatedBoardsWith load: RelatedBoardLoad = { _, _ in .unavailable },
        storingRelatedBoardsWith store: RelatedBoardStore = { _, related in related },
        _ call: @Sendable (BoardStore) async throws -> Response
    ) async throws -> Response {
        let initialRequests = RelatedBoards.loadable.dependencyRequests(of: live.graph, inBoard: key.description)
        var related = try await load(.loadable, initialRequests)
        for _ in 1...Self.maximumRuns {
            let (response, work, relatedWork) = try await runReading(&related, loadingWith: load, call)
            guard !work.kept.isEmpty || relatedWork.contains(where: \.hasPatches) else {
                return response
            }
            let readOnlyWork = readOnlyWork(of: work, along: relatedWork, in: related)
            let attempt = try await commit(work, along: relatedWork + readOnlyWork)
            await updateSearch()
            related = await store(attempt.relatedSessions, related)
            if case .committed = attempt {
                return response
            }
        }
        throw KanbanError.boardBusy(attempts: Self.maximumRuns)
    }

    /// Runs one call on a new working copy, and runs it again while the run asks for related boards that the
    /// related boards of the run do not answer.
    ///
    /// Each load answers each request of the run, so each run after a load reads more boards than the run before.
    /// A run that is the same as the run before asks for nothing new, so the loop ends.
    ///
    /// - Parameters:
    ///   - related: The related boards of the run. The loop gives the related boards of the last run back.
    ///   - load: Loads the related boards of some requests.
    ///   - call: Runs the call against the store of the working copy, and gives the response.
    /// - Returns: The response, the working copy, and the working copy of each related board that the last run
    ///   changed, in the sort order of the path of the repo directory.
    /// - Throws: An error of the loader, or the error of the call.
    private mutating func runReading<Response: Sendable>(
        _ related: inout RelatedBoards,
        loadingWith load: RelatedBoardLoad,
        _ call: @Sendable (BoardStore) async throws -> Response
    ) async throws -> (response: Response, work: WorkingCopy, relatedWork: [RelatedWork]) {
        while true {
            let store = BoardStore(
                working: makeWorkingCopy(stampedBy: EventStamp(actingAs: actor.ref, mintingFrom: ids)),
                boardKey: key.description,
                actingAs: actor,
                from: source,
                reading: related
            )
            let response = try await call(store)
            let work = await store.work
            let relatedWork = await store.relatedWork.values.sorted { lhs, rhs in lhs.path < rhs.path }
            ids = work.stamp.ids
            let changed = related.with(working: relatedWork)
            let dependencies = changed.dependencyRequests(of: work.graph, inBoard: key.description)
            let requests = await store.requests.union(dependencies)
            guard !related.satisfies(requests) else {
                return (response, work, relatedWork)
            }
            related = try await load(related, requests)
            guard related.satisfies(requests) else {
                assertionFailure("The loader of the related boards did not answer the requests \(requests)")
                Log.kanban.error("The loader of the related boards did not answer each request; the run stays")
                return (response, work, relatedWork)
            }
        }
    }

    /// Gives a working copy with no patch of each related board that a graph rule of a run read and that the run
    /// did not change, so that the commit locks and checks the board too (plan.md §5.4 steps 4.4 and 5.1).
    ///
    /// - Parameters:
    ///   - work: The working copy of the current board at the end of the run.
    ///   - changed: The working copy of each related board that the run changed.
    ///   - related: The related boards of the run.
    /// - Returns: The working copies, in the sort order of the path of the repo directory.
    private func readOnlyWork(
        of work: WorkingCopy,
        along changed: [RelatedWork],
        in related: RelatedBoards
    ) -> [RelatedWork] {
        let known = Set(changed.map(\.path)).union([directory.canonicalPath])
        return work.boardsRead(along: changed).subtracting(known).sorted().compactMap { path in
            guard let session = related.session(atPath: path) else {
                assertionFailure("A graph rule read the board at \(path), and the engine did not load it")
                Log.kanban.error(
                    "A graph rule read a board that the engine did not load",
                    metadata: ["path": "\(path)"]
                )
                return nil
            }
            return RelatedWork(path: path, session: session, work: session.makeWorkingCopy(stampedBy: work.stamp))
        }
    }

    /// Makes a working copy of the live graph, with an empty board in memory when the board has no board node.
    ///
    /// - Parameter stamp: The envelope values of the events of the run. A working copy of a related board gets the
    ///   stamp of the run, so that its patches continue the transaction of the call.
    /// - Returns: The working copy.
    func makeWorkingCopy(stampedBy stamp: EventStamp) -> WorkingCopy {
        WorkingCopy(graph: displayGraph, events: live.events, stamp: stamp)
    }

    /// Writes the kept patches of a run under the locks of the boards that the run changed or read for a graph rule
    /// (plan.md §5.4 step 5).
    ///
    /// The commit locks each of these boards in the sort order of the board key. Under the locks, it compares the
    /// signatures of the log files of each locked board with its live graph. When a log of one board changed, the
    /// commit applies the changed files to the live graph of each locked board and writes nothing. Else it appends
    /// the kept patches of each changed board with the `ops` of the full call and the keys of the other changed
    /// boards, and each working copy becomes the live graph of its board.
    ///
    /// - Parameters:
    ///   - work: The working copy of the current board at the end of the run.
    ///   - related: The working copy of each related board that the run changed or read for a graph rule.
    /// - Returns: The result: the patches are written, or a log changed and the call must run again. The result
    ///   holds the session of each related board after the attempt.
    /// - Throws: An ``EventLogError`` when a log file cannot be read, locked, or written.
    private mutating func commit(
        _ work: WorkingCopy,
        along related: [RelatedWork]
    ) async throws(EventLogError) -> CommitAttempt {
        let reads = work.boardsRead(along: related)
        var writes = [BoardWrite(key: key, path: directory.canonicalPath, live: live, work: work)]
            + related.map(\.boardWrite)
        let lockedBoards = writes.indices.filter { index in
            writes[index].hasPatches || reads.contains(writes[index].path)
        }
        let lock = try EventLog.lock(sortedByKey: lockedBoards.map { index in writes[index].lockEntry })
        var isLogChanged = false
        for index in lockedBoards {
            let isChanged = try await writes[index].applyChangedFiles()
            isLogChanged = isLogChanged || isChanged
        }
        if !isLogChanged {
            let changedBoards = writes.indices.filter { index in writes[index].hasPatches }
            let keys = changedBoards.map { index in writes[index].key.description }
            for index in changedBoards {
                try writes[index].append(recording: Array(work.operations), changing: keys)
            }
        }
        lock.unlock()
        live = writes[0].live
        let sessions = Dictionary(
            uniqueKeysWithValues: zip(related, writes.dropFirst()).map { board, write in
                (board.path, board.session.replacing(live: write.live))
            }
        )
        return isLogChanged ? .logChanged(sessions) : .committed(sessions)
    }

    /// Gives this session with a different live graph.
    ///
    /// - Parameter newLive: The live graph after a commit attempt.
    /// - Returns: The session with the live graph.
    private func replacing(live newLive: LiveGraph) -> CommitSession {
        var session = self
        session.live = newLive
        return session
    }
}

/// The result of one commit attempt of a call (plan.md §5.4 step 5). Each case holds the session of each related
/// board that the run changed, after the attempt, by the canonical path of its repo directory.
private enum CommitAttempt {
    /// The patches are written, and each working copy is the live graph of its board.
    case committed([String: CommitSession])

    /// A log changed after the live graph read it. The changed files are applied, and the call must run again.
    case logChanged([String: CommitSession])

    /// The session of each related board that the run changed, after the attempt.
    var relatedSessions: [String: CommitSession] {
        switch self {
        case .committed(let sessions), .logChanged(let sessions): sessions
        }
    }
}

/// One board of a commit: its key, its repo directory, its live graph, and the working copy of the run (plan.md §5.4
/// step 5).
private struct BoardWrite {
    /// The key of the board.
    let key: BoardKey

    /// The canonical path of the repo directory of the board.
    let path: String

    /// The live graph of the board.
    var live: LiveGraph

    /// The working copy of the board at the end of the run.
    let work: WorkingCopy

    /// `true` when the run kept a patch of the board, so the commit locks, checks, and writes the board.
    var hasPatches: Bool {
        !work.kept.isEmpty
    }

    /// The key and the event log of the board, for the lock of many boards.
    var lockEntry: (key: BoardKey, value: EventLog) {
        (key, live.log)
    }

    /// Applies the log files of the board that changed after the live graph read them (plan.md §5.4 step 5.2).
    ///
    /// - Returns: `true` when a file changed. The changed files are then applied to the live graph.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a directory or a file cannot be read.
    mutating func applyChangedFiles() async throws(EventLogError) -> Bool {
        let changed = try live.changedRefs()
        guard !changed.isEmpty else {
            return false
        }
        _ = try await live.apply(changedPaths: changed.map(live.log.fileURL(for:)))
        return true
    }

    /// Appends the kept patches of the board to their node logs, and makes the working copy the live graph (plan.md
    /// §5.4 steps 5.3 and 5.4).
    ///
    /// - Parameters:
    ///   - operations: The names of the public mutations of the full call.
    ///   - keys: The keys of all boards that the call changed. Each event records the keys of the other boards.
    /// - Throws: An ``EventLogError`` when a log file cannot be written or read.
    mutating func append(recording operations: [String], changing keys: [String]) throws(EventLogError) {
        let written = work.kept.map { event in
            event.recording(operations: operations, changing: keys, inBoard: key.description)
        }
        for (ref, events) in OrderedDictionary(grouping: written, by: \.patch.node) {
            try live.log.append(contentsOf: events, toLogOf: ref)
        }
        try live.adopt(work.graph, writing: written)
    }
}

// MARK: - Related work

/// The working copy of one related board that a run changes, or that a graph rule of the run reads (plan.md §5.4,
/// §6.6).
struct RelatedWork: Sendable {
    /// The canonical path of the repo directory of the board.
    let path: String

    /// The session of the board at the start of the run: its live graph and its key.
    let session: CommitSession

    /// The working copy of the board.
    var work: WorkingCopy

    /// `true` when the run kept a patch of the board.
    var hasPatches: Bool {
        !work.kept.isEmpty
    }

    /// The board as the reads of the run see it now: the working graph.
    var snapshot: BoardSnapshot {
        BoardSnapshot(key: session.key.description, graph: work.graph, source: session.source)
    }

    /// The board as the commit writes it.
    fileprivate var boardWrite: BoardWrite {
        BoardWrite(key: session.key, path: path, live: session.live, work: work)
    }
}

extension WorkingCopy {
    /// Gives the other boards that a graph rule of the run read: in this working copy, or in the working copy of a
    /// related board of the run.
    ///
    /// - Parameter related: The working copy of each related board of the run.
    /// - Returns: The canonical paths of the repo directories of the boards.
    fileprivate func boardsRead(along related: [RelatedWork]) -> Set<String> {
        related.reduce(readBoards) { reads, board in reads.union(board.work.readBoards) }
    }
}

extension Event {
    /// Gives this event with the `ops` and the `boards` of the full call (plan.md §5.1). The `boards` value holds the
    /// sorted keys of the other boards that the call changes, or `nil` when the call changes one board.
    ///
    /// - Parameters:
    ///   - operations: The names of the public mutations of the call.
    ///   - keys: The keys of all boards that the call changes.
    ///   - key: The key of the board of the log of the event. The `boards` value does not hold it.
    /// - Returns: The event with the operations and the boards, and the same other values.
    func recording(operations: [String], changing keys: [String], inBoard key: String) -> Event {
        let others = Set(keys).subtracting([key]).sorted()
        return Event(
            id: id,
            txn: txn,
            ops: operations,
            at: at,
            actor: actor,
            boards: others.isEmpty ? nil : others,
            undoes: undoes,
            patch: patch
        )
    }
}

extension Graph {
    /// The short ids of the tasks and the comments of the graph, live or tombstoned.
    fileprivate var shortIDs: Set<ShortID> {
        Set(
            allSlots.compactMap { slot in
                (node(at: slot)?.state as? any ULIDNodeState).map { state in ShortID(of: state.id) }
            }
        )
    }

    /// Gives the graph with a board node. A graph that has no board node (a repo with no `.kanban/`, or no
    /// `board.jsonl`) gets an empty board in memory only. No file is written.
    ///
    /// - Parameters:
    ///   - name: The name of the empty board: the name of the repo directory.
    ///   - time: The `created` and `updated` time of the empty board.
    /// - Returns: This graph when it has a board node, else this graph with the empty board.
    fileprivate func withBoard(named name: String, at time: DateTime) -> Graph {
        guard boardNode == nil else {
            return self
        }
        var graph = self
        graph.update(with: .board(BoardNode(fields: NodeFields(created: time, updated: time), name: name)))
        return graph
    }
}
