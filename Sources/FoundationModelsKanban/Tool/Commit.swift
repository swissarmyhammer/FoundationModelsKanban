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
    /// - Returns: The event, with an id larger than each id that the stamp gave before.
    mutating func makeEvent(of patch: PatchInput, at time: DateTime) -> Event {
        Event(id: nextID(), txn: txn, ops: [], at: time, actor: actor, patch: patch)
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
/// ``runField(as:_:)``: it makes patches, applies them with ``apply(_:at:)``, checks the graph rules, and keeps the
/// patches. A field that throws discards only its own patches and its own changes to the graph. The live graph does
/// not change until the commit succeeds.
struct WorkingCopy: Sendable {
    /// The graph after the kept patches.
    private(set) var graph: Graph

    /// The events of the live graph, in the order of their ids. The working copy reads the events of a node from it
    /// the first time that a patch changes the node.
    private let liveEvents: [Event]

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

    /// Makes the working copy of a run.
    ///
    /// - Parameters:
    ///   - graph: The graph at the start of the run. Each node must be the fold of its events in `events`.
    ///   - events: The events of the graph, in the order of their ids.
    ///   - stamp: The envelope values of the events of the run.
    init(graph: Graph, events: [Event], stamp: EventStamp) {
        self.graph = graph
        liveEvents = events
        self.stamp = stamp
    }

    /// Runs one mutation field on the working copy (plan.md §5.4 step 4).
    ///
    /// The body works on a copy-on-write copy of the working copy. When the body returns, the copy becomes the
    /// working copy. When the body throws, the copy is discarded, so the field keeps none of its patches.
    ///
    /// - Parameters:
    ///   - operation: The name of the public mutation of the field, for the `ops` of the events, or `nil` for a
    ///     field that is not a public mutation (the internal `patch` mutation).
    ///   - body: Makes and applies the patches of the field, and checks the graph rules.
    /// - Returns: The value of the body.
    /// - Throws: The error of the body. Then the working copy does not change.
    mutating func runField<Value, Failure: Error>(
        as operation: String?,
        _ body: (inout WorkingCopy) throws(Failure) -> Value
    ) throws(Failure) -> Value {
        var field = self
        let value = try body(&field)
        if let operation, field.kept.count > kept.count {
            field.operations.append(operation)
        }
        self = field
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
    /// - Throws: An ``EventError`` from the change of the patch. A valid patch gives no error.
    mutating func apply(_ patch: PatchInput, at time: DateTime) throws(EventError) {
        let ref = patch.node
        let events = nodeEvents[ref] ?? liveEvents.filter { event in event.patch.node == ref }
        guard let change = try patch.changes(afterFolding: events) else {
            return
        }
        let event = stamp.makeEvent(of: change, at: time)
        let log = NodeLog(folding: events + [event], for: ref)
        nodeEvents[ref] = log.events
        kept.append(event)
        if let node = log.node {
            graph.update(with: node)
        }
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

    /// The key of the board. It orders the locks (plan.md §5.4 step 5.1).
    private let key: BoardKey

    /// The session actor: the actor of each event.
    private let actor: SessionActor

    /// The source of the transaction ULIDs and the event ids.
    private var ids: any ULIDSource

    /// The clock that gives the time of an empty board.
    private let clock: @Sendable () -> DateTime

    /// Makes the session of a loaded board.
    ///
    /// - Parameters:
    ///   - live: The live graph of the board.
    ///   - key: The key of the board.
    ///   - actor: The session actor.
    ///   - ids: The source of the transaction ULIDs and the event ids.
    ///   - clock: The clock that gives the time of an empty board.
    init(
        of live: LiveGraph,
        inBoard key: BoardKey,
        actingAs actor: SessionActor,
        mintingFrom ids: any ULIDSource,
        timedBy clock: @escaping @Sendable () -> DateTime
    ) {
        self.live = live
        self.key = key
        self.actor = actor
        self.ids = ids
        self.clock = clock
    }

    /// Runs one call on a working copy of the live graph, and commits the patches that the call kept (plan.md §5.4).
    ///
    /// A call that keeps no patch writes nothing and takes no lock (plan.md §5.4 step 6). A run that finds a changed
    /// log discards its response, and the call runs again on the new live graph.
    ///
    /// - Parameter call: Runs the call against the store of the working copy, and gives the response.
    /// - Returns: The response of the run that committed, or of the run that kept no patch.
    /// - Throws: ``KanbanError/boardBusy(attempts:)`` when a log changed before the commit of each of the
    ///   ``maximumRuns`` runs. Then the call wrote nothing. An ``EventLogError`` when a log file cannot be read,
    ///   locked, or written. The error of the call.
    mutating func run<Response: Sendable>(
        _ call: @Sendable (BoardStore) async throws -> Response
    ) async throws -> Response {
        for _ in 1...Self.maximumRuns {
            let store = BoardStore(working: makeWorkingCopy(), boardKey: key.description, actingAs: actor)
            let response = try await call(store)
            let work = await store.work
            ids = work.stamp.ids
            guard !work.kept.isEmpty else {
                return response
            }
            if try await commit(work) {
                return response
            }
        }
        throw KanbanError.boardBusy(attempts: Self.maximumRuns)
    }

    /// Makes the working copy of one run: the live graph, with an empty board in memory when the board has no
    /// board node.
    ///
    /// - Returns: The working copy.
    private func makeWorkingCopy() -> WorkingCopy {
        let repositoryName = live.log.directory.deletingLastPathComponent().lastPathComponent
        return WorkingCopy(
            graph: live.graph.withBoard(named: repositoryName, at: clock()),
            events: live.events,
            stamp: EventStamp(actingAs: actor.ref, mintingFrom: ids)
        )
    }

    /// Writes the kept patches of a run under the lock of the board (plan.md §5.4 step 5).
    ///
    /// - Parameter work: The working copy at the end of the run.
    /// - Returns: `true` when the patches are written and the working copy is the live graph. `false` when a log of
    ///   the board changed after the live graph read it. Then the changed files are applied to the live graph, and
    ///   the call must run again.
    /// - Throws: An ``EventLogError`` when a log file cannot be read, locked, or written.
    private mutating func commit(_ work: WorkingCopy) async throws(EventLogError) -> Bool {
        let log = live.log
        let lock = try EventLog.lock(sortedByKey: [key: log])
        let changed = try live.changedRefs()
        guard changed.isEmpty else {
            _ = try await live.apply(changedPaths: changed.map(log.fileURL(for:)))
            lock.unlock()
            return false
        }
        let written = work.kept.map { event in event.recording(operations: Array(work.operations)) }
        for (ref, events) in OrderedDictionary(grouping: written, by: \.patch.node) {
            try log.append(contentsOf: events, toLogOf: ref)
        }
        try live.adopt(work.graph, writing: written)
        lock.unlock()
        return true
    }
}

extension LiveGraph {
    /// Lists the node files of the board that changed after the live graph read them (plan.md §5.4 step 5.2): a file
    /// with a different signature, a new file, and a removed file. The check reads the files, so it does not wait for
    /// the watcher.
    ///
    /// - Returns: The local refs of the nodes of the changed files.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a directory or a file cannot be read.
    fileprivate func changedRefs() throws(EventLogError) -> Set<LocalRef> {
        let current = try log.nodeFileSignatures()
        return Set(current.keys).union(signatures.keys).filter { ref in current[ref] != signatures[ref] }
    }
}

extension Event {
    /// Gives this event with the `ops` of the full call.
    ///
    /// - Parameter operations: The names of the public mutations of the call.
    /// - Returns: The event with the operations, and the same other values.
    fileprivate func recording(operations: [String]) -> Event {
        Event(id: id, txn: txn, ops: operations, at: at, actor: actor, boards: boards, undoes: undoes, patch: patch)
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
