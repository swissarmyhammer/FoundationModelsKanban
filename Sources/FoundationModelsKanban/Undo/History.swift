import Foundation
import OrderedCollections
import ULID

// MARK: - History

/// The transactions of one board, each as a ``Change`` (plan.md §6.5, `history`).
///
/// The history groups the global event list by `txn`, and orders the transactions by their transaction ULID: the
/// time order of the calls. It replays the transactions in that order into an empty graph, and compares the
/// projection just before and just after each transaction with ``ChangeBuilder``. The fold of each node sorts the
/// events of the node by event id, so after the last transaction the graph is the graph that the loader gives. The
/// undone state of each transaction comes from ``UndoneState``.
private struct History {
    /// The events of each transaction, in the order of the transaction ULIDs. The events of one transaction are in
    /// the order of their ids.
    private let transactions: [(txn: ULID, events: [Event])]

    /// The current key of the board.
    private let boardKey: String

    /// The undone state of the transactions.
    private let undoneState: UndoneState

    /// Makes the history of a board.
    ///
    /// - Parameters:
    ///   - events: The global event list of the board, in the order of the event ids.
    ///   - boardKey: The current key of the board.
    init(of events: [Event], inBoard boardKey: String) {
        transactions = events.groupedByTransaction()
        self.boardKey = boardKey
        undoneState = UndoneState(of: events)
    }

    /// Makes the change of each transaction after a start.
    ///
    /// The ULID text sorts in time order, so the start does not have to be a transaction of the log: a client that
    /// knows a transaction of a different branch, or an old one, gets the transactions that came later.
    ///
    /// - Parameter start: The text of a transaction ULID, in any case. Only the transactions whose ULID text sorts
    ///   after it are in the result. `nil` gives all transactions.
    /// - Returns: The changes, oldest first.
    func changes(after start: String?) -> [Change] {
        // Each ULID text of the log is Crockford base 32 in uppercase, so a start in lowercase compares in uppercase.
        let startText = start?.uppercased()
        var projection = Projection(inBoard: boardKey)
        return transactions.compactMap { txn, events in
            guard startText.map({ text in txn.ulidString > text }) ?? true else {
                projection.apply(contentsOf: events)
                return nil
            }
            let before = projection.view()
            projection.apply(contentsOf: events)
            let builder = ChangeBuilder(from: before, to: projection.view())
            return builder.change(of: events, markingUndone: undoneState.isUndone(txn: txn))
        }
    }
}

/// The graph of a board while the history replays its transactions.
private struct Projection {
    /// The current key of the board.
    private let boardKey: String

    /// The graph after the transactions so far.
    private var graph = Graph()

    /// The events of each node so far, in the order of their ids.
    private var nodeEvents: [LocalRef: [Event]] = [:]

    /// The read view of the graph, or `nil` when no transaction applied after the view was made.
    private var cachedView: BoardView?

    /// Makes the empty projection of a board.
    ///
    /// - Parameter boardKey: The current key of the board.
    init(inBoard boardKey: String) {
        self.boardKey = boardKey
    }

    /// Gives the read view of the graph after the transactions so far. The view is made one time for each state.
    ///
    /// - Returns: The read view.
    mutating func view() -> BoardView {
        let view = cachedView ?? BoardView(of: graph, inBoard: boardKey)
        cachedView = view
        return view
    }

    /// Applies the events of one transaction: each changed node is folded again from all its events so far.
    ///
    /// - Parameter events: The events of the transaction, in the order of their ids.
    mutating func apply(contentsOf events: [Event]) {
        for (ref, transactionEvents) in OrderedDictionary(grouping: events, by: \.patch.node) {
            nodeEvents[ref] = graph.update(folding: nodeEvents[ref, default: []] + transactionEvents, for: ref)
        }
        cachedView = nil
    }
}

// MARK: - Filters

/// The filters of `Board.history` (plan.md §6.7, Filters), resolved against the graph of the call: the graph now.
///
/// `type` keeps only the updates of the node types, `node` only the updates of the node, and `filter` only the
/// updates of the tasks that match it now and of the comments on those tasks. `derived: false` leaves out the
/// `DERIVED` updates. `actor` keeps only the transactions of the actor. A change with no update after the filters is
/// left out.
private struct ChangeFilter {
    /// The node types to keep, or `nil` for all types.
    private let types: Set<NodeType>?

    /// The nodes to keep, or `nil` for all nodes. A `node` argument that names no node gives an empty set.
    private let nodes: Set<LocalRef>?

    /// The stored ref of the actor of the transactions to keep, or `nil` for all actors.
    private let actor: StoredRef?

    /// The evaluator of the task filter, or `nil` for no filter.
    private let evaluator: FilterEvaluator?

    /// `true` when the `DERIVED` updates stay in.
    private let includesDerived: Bool

    /// The graph of the call. The task filter reads it.
    private let graph: Graph

    /// Resolves the filters of a `history` call.
    ///
    /// - Parameters:
    ///   - arguments: The arguments of the call.
    ///   - view: The read view of the graph of the call.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter is empty or does not
    ///   parse. ``KanbanError/notFound(type:reference:)`` when the `actor` names no actor.
    ///   ``KanbanError/ambiguousID(reference:matches:)`` when the `node` is a prefix of more than one ULID.
    init(for arguments: HistoryArguments, in view: BoardView) throws(KanbanError) {
        let resolver = view.resolver
        types = arguments.type.map(Set.init)
        nodes = try arguments.node.map { id throws(KanbanError) in
            Set(try resolver.anyLocalRef(for: id.text).map { ref in [ref] } ?? [])
        }
        actor = try arguments.actor.map { id throws(KanbanError) in
            try resolver.storedRef(for: id.text, ofType: .actor, includingTombstones: true)
        }
        evaluator = try arguments.filter.map { text throws(KanbanError) in
            FilterEvaluator(evaluating: try FilterExpr(parsing: text), over: view.readiness, inBoard: view.boardKey)
        }
        includesDerived = arguments.derived ?? HistoryArguments.includesDerivedByDefault
        graph = view.graph
    }

    /// Applies the filters to one change.
    ///
    /// - Parameter change: The change of one transaction.
    /// - Returns: The change with the updates that the filters keep, or `nil` when the actor does not match or no
    ///   update stays.
    func applied(to change: Change) -> Change? {
        guard actor.map({ actor in actor == .local(change.actorRef) }) ?? true else {
            return nil
        }
        let updates = change.nodeUpdates.filter { update in keeps(update: update) }
        guard !updates.isEmpty else {
            return nil
        }
        return change.keeping(only: updates)
    }

    /// Tells if the filters keep one update.
    ///
    /// - Parameter update: The update.
    /// - Returns: `true` when the update passes the type, the node, the source, and the task filter.
    private func keeps(update: NodeUpdate) -> Bool {
        (types?.contains(update.type) ?? true)
            && (nodes?.contains(update.ref) ?? true)
            && (includesDerived || update.source != .derived)
            && matchesTaskFilter(for: update)
    }

    /// Tells if an update passes the task filter: the update is of a task that matches the filter, or of a comment
    /// on such a task.
    ///
    /// - Parameter update: The update.
    /// - Returns: `true` when the call has no task filter, or when the task of the update matches it.
    private func matchesTaskFilter(for update: NodeUpdate) -> Bool {
        guard let evaluator else {
            return true
        }
        return taskSlot(of: update).map(evaluator.matches(taskAt:)) ?? false
    }

    /// Gives the slot of the task that the task filter tests for an update: the task itself, or the task of a
    /// comment.
    ///
    /// - Parameter update: The update.
    /// - Returns: The slot of the task, or `nil` for an update of a different node type or a node that the graph does
    ///   not have.
    private func taskSlot(of update: NodeUpdate) -> Int? {
        let slot = graph.slot(for: update.ref)
        switch update.type {
        case .task:
            return slot
        case .comment:
            return slot.flatMap { slot in graph.node(at: slot, as: CommentNode.self) }?.task?.resolvedSlot
        case .board, .column, .tag, .actor:
            return nil
        }
    }
}

extension Change {
    /// Gives this change with only some of its updates.
    ///
    /// - Parameter updates: The updates to keep.
    /// - Returns: The change with the same envelope and only these updates.
    fileprivate func keeping(only updates: [NodeUpdate]) -> Change {
        replacingNodeUpdates(updates)
    }
}

// MARK: - Resolver

extension BoardObject {
    /// Resolves `Board.history` (plan.md §6.5, §6.7): the transactions that changed the board, newest first, with the
    /// filters of the change feed.
    ///
    /// The list reads the committed log of the board: the global event list of the board of the view. For the current
    /// board, it is the global event list of the working copy, and for a related board, it is the event list of
    /// that loaded board (plan.md §6.6). A patch of the same call is not in the log yet, so it is not in the list.
    /// The GraphQL field is nullable: an error gives `null` for the field and one item in `errors`, and the other
    /// fields of the board keep their data.
    ///
    /// - Parameters:
    ///   - context: The context of the call. Its store holds the global event list of a board in memory only.
    ///   - arguments: The filters, the start, and the page size.
    /// - Returns: The newest `first` changes after `since` that the filters keep. The value is never `nil`. The
    ///   optional type makes the GraphQL field nullable.
    /// - Throws: An error of ``ChangeFilter/init(for:in:)``.
    func history(context: KanbanContext, arguments: HistoryArguments) async throws(KanbanError) -> [Change]? {
        let filter = try ChangeFilter(for: arguments, in: view)
        let currentEvents = await context.store.work.liveEvents
        let events = view.source?.events ?? currentEvents
        let changes = History(of: events, inBoard: view.boardKey).changes(after: arguments.since?.text)
        let pageSize = max(arguments.first ?? HistoryArguments.defaultPageSize, .zero)
        return Array(changes.reversed().lazy.compactMap { change in filter.applied(to: change) }.prefix(pageSize))
    }
}
