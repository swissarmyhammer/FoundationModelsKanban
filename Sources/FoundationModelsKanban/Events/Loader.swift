import Foundation
import HeapModule
import Synchronization
import ULID

/// One board, as the loader reads it from its log files: the joined graph and the global event list (plan.md §5.3).
struct LoadedBoard: Sendable {
    /// The graph of the board. Each edge to a node of the board holds the slot of its target.
    let graph: Graph

    /// The events of all log files of the board, in the order of their event ids. Undo, `history`, and the change
    /// feed read this list (plan.md §5.3, global order).
    let events: [Event]
}

/// Gets a call when a worker of the ``BoardLoader`` starts and when it ends.
///
/// A test uses it to count the workers that run at the same time. The loader calls it from the thread of each
/// worker, so a conforming type must be safe to call from different threads.
protocol LoaderWorkerObserver: Sendable {
    /// Tells that a worker started.
    func workerDidStart()

    /// Tells that a worker ended.
    func workerDidFinish()
}

/// The parallel loader: it reads one board from its log files into a ``Graph`` (plan.md §5.3, §12 item 23).
///
/// The loader reads the board in **stages**, in entity order: board, actors, columns, tags, tasks, comments. A stage
/// puts all its files into a work queue. A fixed set of workers takes files from the queue until it is empty, and
/// each worker folds one node from its file with ``NodeLog``. The stage ends when all workers are done (a barrier).
///
/// At the end of each stage, the loader **joins** the nodes of the stage: it inserts them into the graph in the sort
/// order of their local refs, and the graph changes each stored ref to the slot of its target. A tag `renamedTo` edge
/// and a task `dependsOn` edge can point to a node of the same stage, so they resolve when the stage ends. A ref to a
/// different board, or to a node with no file, stays unresolved. The fixed insert order gives the same graph for
/// each worker count.
///
/// After the last stage, a k-way merge by event id makes one global event list from the sorted events of all files.
struct BoardLoader: Sendable {
    /// The node types of the stages, in the order that the loader reads them. Each stage needs only the nodes of
    /// the stages before it (plan.md §5.3, why this order).
    static let stageOrder: [PatchNodeType] = [.board, .actor, .column, .tag, .task, .comment]

    /// The smallest number of workers of a stage that has files.
    static let minimumWorkerCount = 1

    /// The log files of the board.
    let log: EventLog

    /// The largest number of workers that read files at the same time.
    let workerCount: Int

    /// Gets a call when each worker starts and ends, or `nil` for no calls.
    let observer: (any LoaderWorkerObserver)?

    /// Makes a loader for one board.
    ///
    /// - Parameters:
    ///   - log: The log files of the board.
    ///   - workerCount: The largest number of workers that read files at the same time. The default is the number of
    ///     active processors. A value less than one gives one worker.
    ///   - observer: Gets a call when each worker starts and ends, or `nil` for no calls.
    init(
        reading log: EventLog,
        withWorkers workerCount: Int = ProcessInfo.processInfo.activeProcessorCount,
        reportingTo observer: (any LoaderWorkerObserver)? = nil
    ) {
        self.log = log
        self.workerCount = max(workerCount, Self.minimumWorkerCount)
        self.observer = observer
    }

    /// Reads all log files of the board, stage by stage, and joins the nodes into one graph.
    ///
    /// A missing node directory (for example no `comments/`) is an empty stage. A board with no `.kanban/`
    /// directory gives an empty graph.
    ///
    /// - Returns: The graph and the global event list.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a directory or a file is there and cannot be read.
    func load() async throws(EventLogError) -> LoadedBoard {
        var graph = Graph()
        var eventLists: [[Event]] = []
        for type in Self.stageOrder {
            let stage = try await readStage(of: type)
            for node in stage.compactMap(\.log.node) {
                graph.update(with: node)
            }
            eventLists.append(contentsOf: stage.map(\.log.events))
        }
        return LoadedBoard(graph: graph, events: EventMerge.merged(eventLists))
    }
}

// MARK: - Stage

extension BoardLoader {
    /// Reads the files of one stage with the workers. The call returns when all workers are done.
    ///
    /// - Parameter type: The node type of the stage.
    /// - Returns: The folded log of each file, in the sort order of the local refs.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when the directory or a file cannot be read.
    private func readStage(of type: PatchNodeType) async throws(EventLogError) -> [StagedLog] {
        let refs = try stageRefs(of: type)
        let queue = WorkQueue(holding: refs)
        let results = await withTaskGroup(of: Result<[StagedLog], EventLogError>.self) { group in
            for _ in 0..<min(workerCount, refs.count) {
                group.addTask {
                    Result { () throws(EventLogError) in try runWorker(takingFrom: queue) }
                }
            }
            return await group.reduce(into: []) { results, result in results.append(result) }
        }
        let logs = try results.map { result throws(EventLogError) in try result.get() }.joined()
        return logs.sorted(by: StagedLog.precedes)
    }

    /// Lists the refs of the files of one stage.
    ///
    /// - Parameter type: The node type of the stage.
    /// - Returns: The board ref for the board stage, or the ref of each file in the directory of the node type.
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
    /// - Parameter queue: The work queue of the stage.
    /// - Returns: The folded log of each file that the worker read.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a file cannot be read.
    private func runWorker(takingFrom queue: WorkQueue) throws(EventLogError) -> [StagedLog] {
        observer?.workerDidStart()
        defer { observer?.workerDidFinish() }
        do {
            return try AnyIterator(queue.next).map { ref throws(EventLogError) in
                StagedLog(ref: ref, log: try log.readLog(of: ref))
            }
        } catch {
            queue.removeAll()
            throw error
        }
    }
}

/// The folded log of one file of a stage, with the local ref of its node.
private struct StagedLog: Sendable {
    /// The local ref of the node of the file.
    let ref: LocalRef

    /// The folded log of the file.
    let log: NodeLog

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

/// The files of one stage that no worker has taken yet. The workers take files from different threads, so a lock
/// keeps the list.
private final class WorkQueue: Sendable {
    /// The refs of the files that no worker has taken, in the order that the workers take them.
    private let pending: Mutex<ArraySlice<LocalRef>>

    /// Makes a queue of the files of one stage.
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

/// The k-way merge of the sorted event lists of all files into one list (plan.md §5.3, global order).
private enum EventMerge {
    /// The position of the next event of one list in the merge.
    struct Cursor: Comparable {
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
    static func nextEvent(takingFrom heap: inout Heap<Cursor>, in lists: [[Event]]) -> Event? {
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
    static func cursor(at position: Int, inList list: Int, of lists: [[Event]]) -> Cursor? {
        guard lists[list].indices.contains(position) else {
            return nil
        }
        return Cursor(id: lists[list][position].id, list: list, position: position)
    }
}
