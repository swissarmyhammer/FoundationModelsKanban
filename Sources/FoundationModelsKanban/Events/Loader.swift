import Foundation
import HeapModule
import Synchronization
import ULID

/// One board, as the loader reads it from its log files: the joined graph and the global event list (plan.md §5.3).
struct LoadedBoard: Sendable {
    /// The graph of the board. Each edge to a node of the board holds the slot of its target.
    let graph: Graph

    /// The events of all log files of the board whose transaction is complete, in the order of their event ids. Undo,
    /// `history`, and the change feed read this list (plan.md §5.3, global order).
    let events: [Event]

    /// The events of the transactions that are not complete in all their log files, in the order of their event ids
    /// (divergence.md Q23). The graph does not hold their state.
    let heldEvents: [Event]
}

/// One board after the join of its nodes, before the merge of its event lists (plan.md §5.3). The engine indexes the
/// tasks of the graph for the search while the event lists merge (divergence.md §16, L4).
struct JoinedBoard: Sendable {
    /// The graph of the board. Each edge to a node of the board holds the slot of its target.
    let graph: Graph

    /// The event list of each log file whose transaction is complete, each in the order of its event ids. The lists
    /// are in the join order.
    let eventLists: [[Event]]

    /// The event list of each log file whose transaction is not complete, each in the order of its event ids. The
    /// lists are in the join order.
    let heldLists: [[Event]]

    /// Merges the event lists into the global event list with a k-way merge by event id.
    ///
    /// - Returns: The graph, the global event list, and the held events.
    func merged() -> LoadedBoard {
        LoadedBoard(graph: graph, events: EventMerge.merged(eventLists), heldEvents: EventMerge.merged(heldLists))
    }
}

/// Gets a call when a worker of the ``BoardLoader`` starts, when it starts to read each file, and when it ends.
///
/// A test uses it to count the workers that run at the same time, and to see which files they read. The loader calls
/// it from the thread of each worker, so a conforming type must be safe to call from different threads.
protocol LoaderWorkerObserver: Sendable {
    /// Tells that a worker started.
    func workerDidStart()

    /// Tells that a worker ended.
    func workerDidFinish()

    /// Tells that a worker starts to read the log file of one node.
    ///
    /// - Parameter ref: The local ref of the node of the file.
    func workerWillRead(fileOf ref: LocalRef)
}

extension LoaderWorkerObserver {
    /// Does nothing. An observer that counts only the workers does not need the files.
    ///
    /// - Parameter ref: The local ref of the node of the file.
    func workerWillRead(fileOf ref: LocalRef) {}
}

/// The parallel loader: it reads one board from its log files into a ``Graph`` (plan.md §5.3, §12 item 23).
///
/// The loader lists the folders of all node types at the same time, and puts the files of all node types into one
/// work queue. A fixed set of workers takes files from the queue until it is empty, and each worker folds one node
/// from its file with ``NodeLog``. Each file folds alone, so no worker waits for the files of a different node type.
///
/// When all workers are done, the loader **joins** the nodes in memory, in **stages** in entity order: board, actors,
/// columns, tags, tasks, comments. In each stage, it inserts the nodes into the graph in the sort order of their
/// local refs, and the graph changes each stored ref to the slot of its target. A tag `renamedTo` edge and a task
/// `dependsOn` edge can point to a node of the same stage, so they resolve when the stage ends. A ref to a different
/// board, or to a node with no file, stays unresolved. The fixed insert order gives the same graph for each worker
/// count.
///
/// After the join, a k-way merge by event id makes one global event list from the sorted events of all files.
struct BoardLoader: Sendable {
    /// The node types of the stages of the join, in order. Each stage needs only the nodes of the stages before it
    /// (plan.md §5.3, why this order).
    static let stageOrder: [PatchNodeType] = [.board, .actor, .column, .tag, .task, .comment]

    /// The smallest number of workers of a load that has files.
    static let minimumWorkerCount = 1

    /// The log files of the board.
    let log: EventLog

    /// The largest number of workers that read files at the same time.
    let workerCount: Int

    /// Gets a call when each worker starts, reads a file, and ends, or `nil` for no calls.
    let observer: (any LoaderWorkerObserver)?

    /// Makes a loader for one board.
    ///
    /// - Parameters:
    ///   - log: The log files of the board.
    ///   - workerCount: The largest number of workers that read files at the same time. The default is the number of
    ///     active processors. A value less than one gives one worker.
    ///   - observer: Gets a call when each worker starts, reads a file, and ends, or `nil` for no calls.
    init(
        reading log: EventLog,
        withWorkers workerCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        reportingTo observer: (any LoaderWorkerObserver)? = nil
    ) {
        self.log = log
        self.workerCount = max(workerCount, Self.minimumWorkerCount)
        self.observer = observer
    }

    /// Reads all log files of the board with one worker pool, and joins the nodes into one graph.
    ///
    /// A missing node directory (for example no `comments/`) is an empty stage. A board with no `.kanban/`
    /// directory gives an empty graph.
    ///
    /// - Returns: The graph and the global event list.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a directory or a file is there and cannot be read.
    func load() async throws(EventLogError) -> LoadedBoard {
        try await join().merged()
    }

    /// Reads all log files of the board with one worker pool, and joins the nodes into one graph. The event lists of
    /// the files are not merged yet, so that a caller can do other work with the graph during the merge.
    ///
    /// A missing node directory (for example no `comments/`) is an empty stage. A board with no `.kanban/`
    /// directory gives an empty graph.
    ///
    /// - Returns: The graph and the event list of each file.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a directory or a file is there and cannot be read.
    func join() async throws(EventLogError) -> JoinedBoard {
        var graph = Graph()
        let logs = try await readStages(
            listingFilesWith: { type throws(EventLogError) in try stageRefs(of: type) },
            joiningInto: &graph
        )
        return JoinedBoard(graph: graph, eventLists: logs.map(\.log.events), heldLists: logs.map(\.held))
    }

    /// Reads some node files with one worker pool, checks the transactions, and joins each node into a graph, stage
    /// by stage in ``stageOrder`` (plan.md §5.3, §5.6, divergence.md Q23).
    ///
    /// The full load and the apply of changed files both use this call. The listings of all node types run at the
    /// same time, and then the workers read the files of all node types from one queue. When all files are read, the
    /// check finds each transaction that is not complete in all its files (``IncompleteTransactions``), over the read
    /// files and the events of the other files. A node with an event of such a transaction folds again without it,
    /// and the event waits in the held list. A node of the other files whose state the check changes folds again from
    /// its events in memory: a transaction that is complete now applies, and a transaction that is not complete now
    /// waits. Then the join runs in memory. A log that gives a node inserts the node, or replaces the state in the
    /// slot of the node. A log that gives no node (a removed file, or a file with no valid line) removes the node
    /// from its slot, and each edge to it becomes unresolved. A ref that the graph does not have changes nothing.
    ///
    /// - Parameters:
    ///   - fileList: Gives the refs of the files of one node type. The loader calls it for each node type at the
    ///     same time, from different threads.
    ///   - others: The applied and the held events of the files that the call does not read. The default has no
    ///     event: the call reads all files of the board.
    ///   - graph: The graph that gets the nodes.
    /// - Returns: The log of each node that the call joined: each read file, and each node of the other files whose
    ///   state the check changed. The logs are in the join order.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a directory or a file cannot be read.
    func readStages(
        listingFilesWith fileList: @escaping @Sendable (PatchNodeType) throws(EventLogError) -> [LocalRef],
        besides others: CheckedEvents = .none,
        joiningInto graph: inout Graph
    ) async throws(EventLogError) -> [StagedLog] {
        let logs = try await readFiles(of: Self.listFiles(with: fileList))
        let otherFiles = others.excluding(nodes: Set(logs.map(\.ref)))
        let incomplete = IncompleteTransactions(
            among: logs.flatMap(\.log.events) + otherFiles.applied + otherFiles.held
        )
        incomplete.recordHold()
        let checked = logs.map { staged in staged.checked(by: incomplete) } + otherFiles.refolded(by: incomplete)
        let ordered = Self.joinOrder(of: checked)
        for staged in ordered {
            if let node = staged.log.node {
                graph.update(with: node)
            } else {
                graph.remove(nodeAt: staged.ref)
            }
        }
        return ordered
    }
}

// MARK: - Worker pool

extension BoardLoader {
    /// Lists the files of all node types at the same time.
    ///
    /// - Parameter fileList: Gives the refs of the files of one node type.
    /// - Returns: The refs of the files of all node types, in ``stageOrder``.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a directory cannot be read. When more than one
    ///   listing fails, the error of the first node type in ``stageOrder``.
    private static func listFiles(
        with fileList: @escaping @Sendable (PatchNodeType) throws(EventLogError) -> [LocalRef]
    ) async throws(EventLogError) -> [LocalRef] {
        let listings = await withTaskGroup(of: StageListing.self) { group in
            for (stage, type) in stageOrder.enumerated() {
                group.addTask {
                    StageListing(stage: stage, refs: Result { () throws(EventLogError) in try fileList(type) })
                }
            }
            return await group.reduce(into: []) { listings, listing in listings.append(listing) }
        }
        let ordered = listings.sorted { lhs, rhs in lhs.stage < rhs.stage }
        return Array(try ordered.map { listing throws(EventLogError) in try listing.refs.get() }.joined())
    }

    /// Reads some files with one worker pool. The call returns when all workers are done.
    ///
    /// - Parameter refs: The local refs of the files, in the order that the workers take them.
    /// - Returns: The folded log of each file, in no fixed order.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a file cannot be read.
    private func readFiles(of refs: [LocalRef]) async throws(EventLogError) -> [StagedLog] {
        let queue = WorkQueue(holding: refs)
        let results = await withTaskGroup(of: Result<[StagedLog], EventLogError>.self) { group in
            for _ in 0..<min(workerCount, refs.count) {
                group.addTask {
                    Result { () throws(EventLogError) in try runWorker(takingFrom: queue) }
                }
            }
            return await group.reduce(into: []) { results, result in results.append(result) }
        }
        return Array(try results.map { result throws(EventLogError) in try result.get() }.joined())
    }

    /// Puts the folded logs into the order of the join: by node type in ``stageOrder``, and in each node type, in
    /// the sort order of the local refs. The fixed order gives the same graph and the same event list for each
    /// worker count.
    ///
    /// - Parameter logs: The folded logs, in no fixed order.
    /// - Returns: The folded logs in the order of the join.
    private static func joinOrder(of logs: [StagedLog]) -> [StagedLog] {
        let logsByType = Dictionary(grouping: logs) { staged in staged.ref.nodeType }
        return stageOrder.flatMap { type in logsByType[type, default: []].sorted(by: StagedLog.precedes) }
    }

    /// Lists the refs of the files of one node type.
    ///
    /// - Parameter type: The node type.
    /// - Returns: The board ref for the board type, or the ref of each file in the directory of the node type.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the directory is there and cannot be read.
    private func stageRefs(of type: PatchNodeType) throws(EventLogError) -> [LocalRef] {
        guard type != .board else {
            return [.board]
        }
        return try log.nodeRefs(ofType: type)
    }

    /// Runs one worker: it takes files from the queue until the queue is empty, and folds the node of each file.
    ///
    /// When a file cannot be read, the worker empties the queue, so that the other workers stop after their current
    /// file.
    ///
    /// - Parameter queue: The work queue of the files of all node types.
    /// - Returns: The folded log of each file that the worker read.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a file cannot be read.
    private func runWorker(takingFrom queue: WorkQueue) throws(EventLogError) -> [StagedLog] {
        observer?.workerDidStart()
        defer { observer?.workerDidFinish() }
        do {
            return try AnyIterator(queue.next).map { ref throws(EventLogError) in
                observer?.workerWillRead(fileOf: ref)
                return StagedLog(ref: ref, log: try log.readLog(of: ref))
            }
        } catch {
            queue.removeAll()
            throw error
        }
    }
}

/// The result of the listing of the files of one node type.
private struct StageListing: Sendable {
    /// The index of the node type in ``BoardLoader/stageOrder``.
    let stage: Int

    /// The refs of the files of the node type, or the error of the listing.
    let refs: Result<[LocalRef], EventLogError>
}

/// The folded log of one node, with the local ref of the node, and the events of the node that wait for their
/// transaction (divergence.md Q23).
struct StagedLog: Sendable {
    /// The local ref of the node.
    let ref: LocalRef

    /// The folded log of the node. It holds only the events whose transaction is complete.
    let log: NodeLog

    /// The events of the node whose transaction is not complete, in the order of their ids. The fold does not apply
    /// them.
    let held: [Event]

    /// Makes the log of one node that a worker read: no transaction check ran yet, so no event waits.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the node.
    ///   - log: The folded log of the file of the node.
    init(ref: LocalRef, log: NodeLog) {
        self.init(ref: ref, log: log, held: [])
    }

    /// Folds the events of one node, and holds the events whose transaction is not complete.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the node.
    ///   - events: The events of the node, in any order.
    ///   - incomplete: The transactions that are not complete.
    init(ref: LocalRef, folding events: [Event], by incomplete: IncompleteTransactions) {
        self.init(
            ref: ref,
            log: NodeLog(folding: events.filter { event in !incomplete.holds(event) }, for: ref),
            held: events.filter(incomplete.holds).sorted { lhs, rhs in lhs.id < rhs.id }
        )
    }

    /// Makes the log of one node.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the node.
    ///   - log: The folded log of the node.
    ///   - held: The events of the node whose transaction is not complete, in the order of their ids.
    private init(ref: LocalRef, log: NodeLog, held: [Event]) {
        self.ref = ref
        self.log = log
        self.held = held
    }

    /// Gives this log after a transaction check. A log with no event of a transaction that is not complete does not
    /// change. Else the node folds again without these events, and they wait.
    ///
    /// - Parameter incomplete: The transactions that are not complete.
    /// - Returns: The checked log.
    func checked(by incomplete: IncompleteTransactions) -> StagedLog {
        guard log.events.contains(where: incomplete.holds) else {
            return self
        }
        return StagedLog(ref: ref, folding: log.events + held, by: incomplete)
    }

    /// Tells if one log comes before a different log in the insert order of the join: the sort order of the text of
    /// the local ref.
    ///
    /// - Parameters:
    ///   - lhs: A log.
    ///   - rhs: A different log.
    /// - Returns: `true` when `lhs` comes first.
    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.ref.description < rhs.ref.description
    }
}

// MARK: - Work queue

/// The files of a load that no worker has taken yet. The workers take files from different threads, so a lock keeps
/// the list.
private final class WorkQueue: Sendable {
    /// The refs of the files that no worker has taken, in the order that the workers take them.
    private let pending: Mutex<ArraySlice<LocalRef>>

    /// Makes a queue of the files of a load.
    ///
    /// - Parameter refs: The local refs of the files.
    init(holding refs: [LocalRef]) {
        pending = Mutex(refs[...])
    }

    /// Takes the next file.
    ///
    /// - Returns: The local ref of the file, or `nil` when the queue is empty.
    func next() -> LocalRef? {
        pending.withLock { pending in pending.popFirst() }
    }

    /// Removes all files that no worker has taken.
    func removeAll() {
        pending.withLock { pending in pending.removeAll() }
    }
}

// MARK: - Global order

/// The k-way merge of the sorted event lists of all files into one list (plan.md §5.3, global order). The loader and
/// the live graph (plan.md §5.6) use it.
enum EventMerge {
    /// The position of the next event of one list in the merge.
    private struct Cursor: Comparable {
        /// The id of the next event of the list.
        let id: ULID

        /// The index of the list.
        let list: Int

        /// The index of the next event in the list.
        let position: Int

        /// Tells if one cursor comes before a different cursor: by event id, then by the index of the list, so that
        /// two equal ids keep a fixed order.
        ///
        /// - Parameters:
        ///   - lhs: A cursor.
        ///   - rhs: A different cursor.
        /// - Returns: `true` when `lhs` comes first.
        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.id, lhs.list) < (rhs.id, rhs.list)
        }
    }

    /// Merges event lists that are each in the order of their event ids.
    ///
    /// - Parameter lists: The event lists. Each list is in the order of its event ids.
    /// - Returns: All events, in the order of their event ids.
    static func merged(_ lists: [[Event]]) -> [Event] {
        let cursors = lists.indices.compactMap { list in cursor(at: 0, inList: list, of: lists) }
        return Array(sequence(state: Heap(cursors)) { heap in nextEvent(takingFrom: &heap, in: lists) })
    }

    /// Takes the event with the smallest id from the heap, and puts the cursor of the next event of its list into
    /// the heap.
    ///
    /// - Parameters:
    ///   - heap: The cursor of the next event of each list that has events left.
    ///   - lists: The event lists.
    /// - Returns: The event, or `nil` when no list has events left.
    private static func nextEvent(takingFrom heap: inout Heap<Cursor>, in lists: [[Event]]) -> Event? {
        guard let cursor = heap.popMin() else {
            return nil
        }
        if let next = Self.cursor(at: cursor.position + 1, inList: cursor.list, of: lists) {
            heap.insert(next)
        }
        return lists[cursor.list][cursor.position]
    }

    /// Makes the cursor of one position in one list.
    ///
    /// - Parameters:
    ///   - position: The index of the event in the list.
    ///   - list: The index of the list.
    ///   - lists: The event lists.
    /// - Returns: The cursor, or `nil` when the list has no event at the position.
    private static func cursor(at position: Int, inList list: Int, of lists: [[Event]]) -> Cursor? {
        guard lists[list].indices.contains(position) else {
            return nil
        }
        return Cursor(id: lists[list][position].id, list: list, position: position)
    }
}
