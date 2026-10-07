import Foundation
import ULID

/// The graph of one loaded board that stays current with its log files (plan.md §5.6, §12 item 25).
///
/// A log can change outside the tool: a manual edit, a `git pull`, a merge, a branch switch, or a write from a
/// different process. The file watcher and the commit check give the changed files to ``apply(changedPaths:)``,
/// which reads each changed file again and joins its node into the graph. The graph keeps the slot of each node, so
/// the edges of the other nodes stay correct.
///
/// The value also keeps the global event list and the signature of each node file that it read. The commit check
/// compares the signatures with the files on disk (plan.md §5.4 step 5).
struct LiveGraph: Sendable {
    /// The divisor of the file count of the board for a full reload: a batch that changes more than the file count
    /// divided by this value (more than half of the files, for example after a branch switch) loads the board again
    /// with the full parallel loader (plan.md §5.6, large changes).
    static let fullReloadDivisor = 2

    /// The loader of the board. It reads the changed files of a batch, and the full board for a full reload.
    private let loader: BoardLoader

    /// The graph of the board.
    private(set) var graph: Graph

    /// The events of all log files of the board, in the order of their event ids (plan.md §5.3, global order).
    private(set) var events: [Event]

    /// The signature of each node file that the graph read, by the local ref of its node. A node with no file has no
    /// entry.
    private(set) var signatures: [LocalRef: FileSignature]

    /// The event log of the board.
    var log: EventLog {
        loader.log
    }

    /// Loads a board with the full parallel loader, and records the signature of each node file.
    ///
    /// The signatures are read before the files. Thus, a write between the two reads gives a different signature at
    /// the next check, and the change is not lost.
    ///
    /// - Parameter loader: The loader of the board.
    /// - Returns: The live graph of the board.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a directory or a file cannot be read.
    static func load(using loader: BoardLoader) async throws(EventLogError) -> LiveGraph {
        let signatures = try loader.log.nodeFileSignatures()
        let board = try await loader.load()
        return LiveGraph(loader: loader, graph: board.graph, events: board.events, signatures: signatures)
    }

    /// Applies a batch of changed files to the graph (plan.md §5.6, apply a batch).
    ///
    /// The apply uses the work queue and the stage order of the loader: board, actors, columns, tags, tasks,
    /// comments. For each changed node file:
    ///
    /// - A changed file is read again from the start, and its node is folded again. The new state replaces the state
    ///   in the slot of the node.
    /// - A new file gets a new slot. Each edge that waited for its node resolves to the new slot.
    /// - A removed file removes its node from its slot. Each edge to the node becomes unresolved.
    ///
    /// A line that does not parse is skipped, and the other lines of its file still apply. Then the apply updates
    /// the global event list and the signature of each changed file. When the batch changes more than half of the
    /// files of the board, the apply loads the full board again instead (plan.md §5.6, large changes). A path that
    /// is not a node log of the board (for example the lock file) changes nothing.
    ///
    /// The graph, the event list, and the signatures change only when the apply succeeds.
    ///
    /// - Parameter changedPaths: The changed files.
    /// - Returns: The ids of the events that the graph did not have before the apply, in the order of their ids. A
    ///   caller makes `Change` values from them (plan.md §6.7).
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a directory or a file cannot be read.
    mutating func apply(changedPaths: some Sequence<URL>) async throws(EventLogError) -> [ULID] {
        let refs = Set(changedPaths.compactMap(loader.log.ref(ofFileAt:)))
        guard !refs.isEmpty else {
            return []
        }
        let knownIDs = Set(events.map(\.id))
        if refs.count * Self.fullReloadDivisor > signatures.count {
            self = try await Self.load(using: loader)
        } else {
            try await reload(filesOf: refs)
        }
        return events.map(\.id).filter { id in !knownIDs.contains(id) }
    }

    /// Makes the graph of a commit the live graph, after the commit appended its events (plan.md §5.4 step 5.4).
    ///
    /// The call records the new signature of each log file that the commit appended to. Thus, the watcher event for
    /// this write finds no change, and the tool does not read its own write again.
    ///
    /// - Parameters:
    ///   - committed: The working graph of the call. It holds the state that the appended events give.
    ///   - written: The events that the commit appended, in the order of their ids.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a log file cannot be read. Then nothing changes.
    mutating func adopt(_ committed: Graph, writing written: [Event]) throws(EventLogError) {
        let newSignatures = try fileSignatures(of: Set(written.map(\.patch.node)))
        install(committed, events: EventMerge.merged([events, written]), signatures: newSignatures)
    }

    /// Reads the files of some nodes again, stage by stage, and joins their nodes into the graph.
    ///
    /// - Parameter refs: The local refs of the changed nodes.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a file cannot be read. Then nothing changes.
    private mutating func reload(filesOf refs: Set<LocalRef>) async throws(EventLogError) {
        let newSignatures = try fileSignatures(of: refs)
        var updated = graph
        let eventLists = try await loader.readStages(
            listingFilesWith: { type in Array(refs.filter { ref in ref.nodeType == type }) },
            joiningInto: &updated
        )
        let keptEvents = events.filter { event in !refs.contains(event.patch.node) }
        install(updated, events: EventMerge.merged([keptEvents] + eventLists), signatures: newSignatures)
    }

    /// Reads the signature of the log file of each of some nodes.
    ///
    /// - Parameter refs: The local refs of the nodes.
    /// - Returns: The signature of each file, by the local ref of its node. A node with no file gives `nil`.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a file cannot be read.
    private func fileSignatures(of refs: Set<LocalRef>) throws(EventLogError) -> [LocalRef: FileSignature?] {
        let pairs = try refs.map { ref throws(EventLogError) in (ref, try loader.log.signature(of: ref)) }
        return Dictionary(uniqueKeysWithValues: pairs)
    }

    /// Replaces the graph and the event list, and records the signatures of the changed files.
    ///
    /// - Parameters:
    ///   - newGraph: The new graph.
    ///   - newEvents: The new global event list, in the order of the event ids.
    ///   - newSignatures: The signature of each changed file, by the local ref of its node. A `nil` signature removes
    ///     the entry of a file that is gone.
    private mutating func install(
        _ newGraph: Graph,
        events newEvents: [Event],
        signatures newSignatures: [LocalRef: FileSignature?]
    ) {
        graph = newGraph
        events = newEvents
        for (ref, signature) in newSignatures {
            signatures[ref] = signature
        }
    }
}
