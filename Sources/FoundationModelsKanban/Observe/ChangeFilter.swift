import Foundation

/// The filter arguments that `Board.history` and `Subscription.changes` share (plan.md §6.7, arguments). A client can
/// catch up with `history(since:)` and then subscribe with the same arguments.
protocol ChangeFilterArguments {
    /// The node types to keep, or `nil` for all types.
    var type: [NodeType]? { get }

    /// The node to keep: a full URI or a short form, or `nil` for all nodes.
    var node: NodeID? { get }

    /// The actor of the transactions to keep: a full URI or a short form, or `nil` for all actors.
    var actor: NodeID? { get }

    /// The filter of the tasks to keep, for example `#bug`, or `nil` for no filter.
    var filter: String? { get }

    /// `false` to leave out the `DERIVED` updates. An explicit `null` keeps them.
    var derived: Bool? { get }
}

extension HistoryArguments: ChangeFilterArguments {}

/// The filters of the change feed (plan.md §6.7, filters), with their refs resolved and their task filter parsed.
///
/// `type` keeps only the updates of the node types, `node` only the updates of the node, and `filter` only the
/// updates of the tasks that match it and of the comments on those tasks. `derived: false` leaves out the `DERIVED`
/// updates. `actor` keeps only the transactions of the actor. A change with no update after the filters is left out.
///
/// The refs resolve one time, against the graph of the call that makes the filter. The task filter reads the graph
/// that ``applied(to:readingTasksOf:)`` gets, so a subscription tests each task as the task is after the change.
struct ChangeFilter: Sendable {
    /// The node types to keep, or `nil` for all types.
    private let types: Set<NodeType>?

    /// The nodes to keep, or `nil` for all nodes. A `node` argument that names no node gives an empty set.
    private let nodes: Set<LocalRef>?

    /// The stored ref of the actor of the transactions to keep, or `nil` for all actors.
    private let actor: StoredRef?

    /// The task filter, or `nil` for no filter.
    private let expression: FilterExpr?

    /// `true` when the `DERIVED` updates stay in.
    private let includesDerived: Bool

    /// Resolves the filters of a call.
    ///
    /// - Parameters:
    ///   - arguments: The arguments of the call.
    ///   - view: The read view of the graph of the call. The `node` and `actor` refs resolve in it.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter is empty or does not
    ///   parse. ``KanbanError/notFound(type:reference:)`` when the `actor` names no actor.
    ///   ``KanbanError/ambiguousID(reference:matches:)`` when the `node` is a prefix of more than one ULID.
    init(for arguments: some ChangeFilterArguments, in view: BoardView) throws(KanbanError) {
        let resolver = view.resolver
        types = arguments.type.map(Set.init)
        nodes = try arguments.node.map { id throws(KanbanError) in
            Set(try resolver.anyLocalRef(for: id.text).map { ref in [ref] } ?? [])
        }
        actor = try arguments.actor.map { id throws(KanbanError) in
            try resolver.storedRef(for: id.text, ofType: .actor, includingTombstones: true)
        }
        expression = try arguments.filter.map { text throws(KanbanError) in try FilterExpr(parsing: text) }
        includesDerived = arguments.derived ?? HistoryArguments.includesDerivedByDefault
    }

    /// Applies the filters to some changes.
    ///
    /// - Parameters:
    ///   - changes: The changes, each of one transaction.
    ///   - view: The read view of the graph whose tasks the task filter tests.
    /// - Returns: Each change with the updates that the filters keep, in the order of `changes`. A change of a
    ///   different actor, and a change with no update after the filters, is not in the list.
    func applied(to changes: some Sequence<Change>, readingTasksOf view: BoardView) -> [Change] {
        let matcher = UpdateMatcher(filter: self, view: view)
        return changes.compactMap { change in applied(to: change, matching: matcher) }
    }

    /// Applies the filters to one change.
    ///
    /// - Parameters:
    ///   - change: The change of one transaction.
    ///   - matcher: The test of each update.
    /// - Returns: The change with the updates that the filters keep, or `nil` when the actor does not match or no
    ///   update stays.
    private func applied(to change: Change, matching matcher: UpdateMatcher) -> Change? {
        guard actor.map({ actor in actor == .local(change.actorRef) }) ?? true else {
            return nil
        }
        let updates = change.nodeUpdates.filter(matcher.keeps(update:))
        guard !updates.isEmpty else {
            return nil
        }
        return change.replacingNodeUpdates(updates)
    }

    /// The test of the updates of the changes against one graph: the filters, and the evaluator of the task filter
    /// over the graph.
    private struct UpdateMatcher {
        /// The filters.
        let filter: ChangeFilter

        /// The evaluator of the task filter, or `nil` for no filter.
        let evaluator: FilterEvaluator?

        /// The graph whose tasks the task filter tests.
        let graph: Graph

        /// Makes the test of the updates against the graph of a read view.
        ///
        /// - Parameters:
        ///   - filter: The filters.
        ///   - view: The read view of the graph whose tasks the task filter tests.
        init(filter: ChangeFilter, view: BoardView) {
            self.filter = filter
            evaluator = filter.expression.map { expression in
                FilterEvaluator(evaluating: expression, over: view.readiness, inBoard: view.boardKey)
            }
            graph = view.graph
        }

        /// Tells if the filters keep one update.
        ///
        /// - Parameter update: The update.
        /// - Returns: `true` when the update passes the type, the node, the source, and the task filter.
        func keeps(update: NodeUpdate) -> Bool {
            (filter.types?.contains(update.type) ?? true)
                && (filter.nodes?.contains(update.ref) ?? true)
                && (filter.includesDerived || update.source != .derived)
                && matchesTaskFilter(for: update)
        }

        /// Tells if an update passes the task filter: the update is of a task that matches the filter, or of a
        /// comment on such a task.
        ///
        /// - Parameter update: The update.
        /// - Returns: `true` when there is no task filter, or when the task of the update matches it.
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
        /// - Returns: The slot of the task, or `nil` for an update of a different node type or a node that the graph
        ///   does not have.
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
}
