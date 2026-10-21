import Foundation
import FoundationModelsExtras
import GraphQL
import OrderedCollections

// MARK: - Source

/// One source board of `collectBoards` (divergence.md M9), as the call reads it from its `.kanban/` folder: its names,
/// the events of its node logs, and the signature of each node file.
///
/// The call adds the events of the node logs to the target board, the same as a git union merge. From the board log of
/// the source, the call adds only the lines of a transaction that also wrote a merged node log, so that each merged
/// transaction has a line in each file that its `files` list names (divergence.md Q23). The target keeps its own board
/// ID, git key, and name: the names of the source become old names of the target through one `collected` patch.
struct CollectedSource: Sendable {
    /// The name of the board property that each `collected` patch sets: the record of one source.
    static let collectedProperty = "collected"

    /// The root directory of the source board.
    let root: URL

    /// The board IDs of the source, as its board log has them.
    let boardIDs: [String]

    /// The git key that the last write of the source recorded, or `nil` when no write recorded one.
    let gitKey: String?

    /// The old names of the source, as its board log has them.
    let oldNames: [String]

    /// Each name of the source, each one time: the key that a board ref of the call gave, the board IDs, the git key,
    /// and the old names. Each name becomes an old name of the target.
    let names: [String]

    /// The key of the source in the lock order of the commit, or `nil` when the source has no board ID. The commit then
    /// uses the key of the target.
    let lockKey: BoardKey?

    /// The signature of each node file of the source when the call read it. The commit checks under the lock that no
    /// file changed after the read.
    let signatures: [LocalRef: FileSignature]

    /// The events of the node logs of the source other than the board log, by file in the sort order of the refs.
    let events: [Event]

    /// The events of the board log of the source whose transaction is the transaction of an event in ``events``, in
    /// the order of their ids (divergence.md M9).
    let boardEvents: [Event]

    /// The log files of the source board.
    var log: EventLog {
        EventLog(repositoryAt: root)
    }

    /// The key and the event log of the source, for the lock of many boards.
    ///
    /// - Parameter targetKey: The key of the target board. A source with no board ID uses it.
    /// - Returns: The lock entry.
    func lockEntry(besides targetKey: BoardKey) -> (key: BoardKey, value: EventLog) {
        (lockKey ?? targetKey, log)
    }

    /// The record of the `collected` patch of the source: the source path, and each board ID, git key, and old name of
    /// the source. The envelope of the event gives the time and the actor.
    var record: Map {
        [
            "path": .string(root.path),
            "boardIds": .array(boardIDs.map(Map.string)),
            "gitKey": gitKey.map(Map.string) ?? .null,
            "oldNames": .array(oldNames.map(Map.string)),
        ]
    }
}

extension CollectedSource {
    /// Reads a source board from its `.kanban/` folder now. The read takes no lock and makes no file.
    ///
    /// - Parameters:
    ///   - root: The root directory of the source board.
    ///   - key: The current key of the source when a board ref of the call names a loaded board, else `nil`.
    /// - Returns: The source.
    /// - Throws: ``EventLogError/incompatibleBoard(directory:)`` when the `.kanban/` folder is a board of the old Rust
    ///   kanban. ``EventLogError/fileSystem(path:detail:)`` when a directory or a file cannot be read.
    static func read(fromBoardAt root: URL, currentKey key: String?) throws(EventLogError) -> CollectedSource {
        let log = EventLog(repositoryAt: root)
        try log.checkCompatibility()
        let signatures = try log.nodeFileSignatures()
        let boardLog = try log.readLog(of: .board)
        let board = boardLog.node?.state as? BoardNode
        let refs = signatures.keys.filter { ref in ref != .board }.sorted()
        let events = Array(try refs.map { ref throws(EventLogError) in try log.readLog(of: ref).events }.joined())
        let transactions = Set(events.map(\.txn))
        let boardIDs = board?.ids.map(\.ulidString) ?? []
        let recorded = [key].compactMap(\.self) + boardIDs + [board?.gitKey].compactMap(\.self)
            + (board?.oldNames ?? [])
        return CollectedSource(
            root: root,
            boardIDs: boardIDs,
            gitKey: board?.gitKey,
            oldNames: board?.oldNames ?? [],
            names: OrderedSet(recorded.map(BoardKey.normalizedText(of:))).elements,
            lockKey: board?.ids.first.map(BoardKey.init(boardID:)),
            signatures: signatures,
            events: events,
            boardEvents: boardLog.events.filter { event in transactions.contains(event.txn) }
        )
    }

    /// Tells if the node files of the source are the same as when the call read them. The commit calls it under the
    /// lock of the source.
    ///
    /// - Returns: `true` when no node file changed, came, or went.
    /// - Throws: ``EventLogError/fileSystem(path:detail:)`` when a directory or a file cannot be read.
    func isUnchanged() throws(EventLogError) -> Bool {
        try log.nodeFileSignatures() == signatures
    }

    /// Removes the `.kanban/` folder of the source after the commit wrote its events to the target. A folder that
    /// cannot be removed does not stop the call, because the target holds each event now: the removal records the
    /// fault with swift-log, and a later collect of the same source adds no event again.
    func removeBoardDirectory() {
        do {
            try FileManager.default.removeItem(at: log.directory)
        } catch {
            Log.kanban.error(
                "collectBoards wrote the events of a source board and cannot remove its .kanban folder",
                metadata: ["path": "\(log.directory.path)", "error": "\(error)"]
            )
        }
    }
}

// MARK: - Merge report

/// The nodes that more than one board of a `collectBoards` call has, and the fields that those boards give different
/// values (divergence.md M9). Replay decides each such field by the event order, and the report gives the value that
/// won.
struct CollectMerge {
    /// One board of the merge: its path, and the events of each of its nodes.
    struct Board {
        /// The root directory of the board, for the report.
        let path: String

        /// The events of each node of the board that the merge reads.
        let events: [LocalRef: [Event]]
    }

    /// One field that two or more boards give different values.
    struct Conflict {
        /// The local ref of the node.
        let node: LocalRef

        /// The name of the field: a property name, or `body`.
        let field: String

        /// The value that each board gives, each one time, in the order of the boards.
        let values: [String]

        /// The value after the merge, or `nil` when the merge has no value.
        let winner: String?
    }

    /// The name of the body in a conflict.
    static let bodyField = "body"

    /// The node types whose nodes have a slug: two boards with the same slug have one node after the merge.
    static let slugTypes: Set<PatchNodeType> = [.column, .tag, .actor]

    /// The boards of the merge: the target first, then each source.
    let boards: [Board]

    /// Each node that more than one board has, in the sort order of the refs, with the path of each board that has
    /// it.
    var sharedNodes: [(node: LocalRef, paths: [String])] {
        let pairs = boards.flatMap { board in board.events.keys.map { node in (node: node, path: board.path) } }
        return OrderedDictionary(grouping: pairs, by: \.node)
            .map { node, entries in (node: node, paths: entries.map(\.path)) }
            .filter { shared in shared.paths.count > 1 }
            .sorted { lhs, rhs in lhs.node < rhs.node }
    }

    /// Each column, tag, and actor that more than one board has: the slug merges of the call.
    var slugMerges: [(node: LocalRef, paths: [String])] {
        sharedNodes.filter { shared in Self.slugTypes.contains(shared.node.nodeType) }
    }

    /// Each field that two or more boards give different values, by node in the order of ``sharedNodes``.
    var conflicts: [Conflict] {
        sharedNodes.flatMap { shared in conflicts(of: shared.node) }
    }

    /// Gives the fields of one node that two or more boards give different values.
    ///
    /// - Parameter node: The local ref of the node.
    /// - Returns: The conflicts, by field in name order, and the body last.
    private func conflicts(of node: LocalRef) -> [Conflict] {
        let logs = boards.compactMap { board in board.events[node] }
        let snapshots = logs.compactMap { events in NodeSnapshot(folding: events, for: node) }
        guard let merged = NodeSnapshot(folding: OrderedSet(logs.joined()).elements, for: node) else {
            return []
        }
        let names = Set(snapshots.flatMap(\.properties.values.keys)).sorted()
        let fields = names.compactMap { name in
            conflict(of: node, field: name, values: snapshots.compactMap { snapshot in
                snapshot.properties.values[name]?.map.plainText
            }, winner: merged.properties.values[name]?.map.plainText)
        }
        let bodies = snapshots.map(\.body).filter { body in !body.isEmpty }
        let body = conflict(of: node, field: Self.bodyField, values: bodies, winner: merged.body)
        return fields + [body].compactMap(\.self)
    }

    /// Makes the conflict of one field, when the boards give more than one value.
    ///
    /// - Parameters:
    ///   - node: The local ref of the node.
    ///   - field: The name of the field.
    ///   - values: The value that each board gives.
    ///   - winner: The value after the merge.
    /// - Returns: The conflict, or `nil` when the boards give one value or none.
    private func conflict(of node: LocalRef, field: String, values: [String], winner: String?) -> Conflict? {
        let distinct = OrderedSet(values).elements
        return distinct.count > 1 ? Conflict(node: node, field: field, values: distinct, winner: winner) : nil
    }
}

// MARK: - Patches

extension WorkingCopy {
    /// Adds the board lines of the sources, and writes one `collected` patch on the board for each source
    /// (divergence.md M9). The board lines are the lines of each source board log whose transaction also wrote a
    /// merged node log (``CollectedSource/boardEvents``). The names of the source become old names of this board, and
    /// the record of the source holds its path and its names. The commit locks each source with this board, and
    /// removes its `.kanban/` after the write.
    ///
    /// - Parameters:
    ///   - sources: The source boards.
    ///   - time: The time of the change.
    /// - Throws: An ``EventError`` when a patch breaks a rule of the log.
    mutating func addCollected(_ sources: [CollectedSource], at time: DateTime) throws(EventError) {
        let own = graph.boardNode
        merge(sources.flatMap(\.boardEvents))
        try keepBoardNames(of: own, at: time)
        for source in sources {
            let patch = try PatchInput(
                node: .board,
                set: [CollectedSource.collectedProperty: .json(source.record)],
                add: [PropertyName.oldNames: source.names.map(StoredRef.board(named:))]
            )
            try apply(patch, at: time)
            record(collected: source)
        }
    }

    /// Gives this board back its own board IDs, git key, and name after the merge of the board lines of the sources
    /// (divergence.md M9). One board patch sets the name and the git key that the board had before the merge, clears
    /// each of them that the board did not have, and removes each board ID that the board did not have. The merge
    /// makes the id of the patch larger than each merged id, so the patch wins in the event order. A patch that
    /// changes nothing is not kept.
    ///
    /// - Parameters:
    ///   - own: The board node before the merge, or `nil` when the graph had no board node.
    ///   - time: The time of the change.
    /// - Throws: An ``EventError`` when the patch breaks a rule of the log.
    private mutating func keepBoardNames(of own: BoardNode?, at time: DateTime) throws(EventError) {
        guard let merged = graph.boardNode else {
            return
        }
        let ownIDs = own?.ids ?? []
        let ownName = own.flatMap { board in board.name.isEmpty ? nil : board.name }
        let values = [PropertyName.name: ownName, PropertyName.gitKey: own?.gitKey]
        let foreignIDs = merged.ids.filter { id in !ownIDs.contains(id) }
        let patch = try PatchInput(
            node: .board,
            set: values.compactMapValues { value in value.map { text in .json(.string(text)) } },
            unset: values.filter { _, value in value == nil }.keys.sorted(),
            remove: [PropertyName.boardIDs: foreignIDs.map { id in StoredRef.board(named: id.ulidString) }]
                .filter { _, refs in !refs.isEmpty }
        )
        try apply(patch, at: time)
    }
}
