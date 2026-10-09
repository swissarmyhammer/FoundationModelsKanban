import Foundation

/// The filter of the change feed: the `filter` argument of `Board.history`, `Subscription.changes`, and
/// `Change.updates` (plan.md §6.7, filters).
///
/// The filter keeps the updates whose node matches it. The test of a node is the test of a task list (``TaskFilter``),
/// with the same parser, the same evaluator, and the same "hidden unless named" rule. A task atom (`#`, `@`, `%`, or a
/// virtual tag) matches only a task. `^id` matches the node with the id, and `~type` matches each node of the type. A
/// change with no update after the filter is left out, so a change is in the result when one update or more matches.
///
/// The filter reads the graph that ``applied(to:readingNodesOf:)`` gets, so a subscription tests each node as the node
/// is after the change.
struct ChangeFilter: Sendable {
    /// The parsed filter, or `nil` for no filter.
    private let expression: FilterExpr?

    /// Parses the filter of a call.
    ///
    /// - Parameter filter: The filter text, for example `#bug || ~column`, or `nil` for no filter.
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter is empty or does not
    ///   parse.
    init(parsing filter: String?) throws(KanbanError) {
        expression = try filter.map { text throws(KanbanError) in try FilterExpr(parsing: text) }
    }

    /// Applies the filter to some changes.
    ///
    /// - Parameters:
    ///   - changes: The changes, each of one transaction.
    ///   - view: The read view of the graph whose nodes the filter tests.
    /// - Returns: Each change with the updates that the filter keeps, in the order of `changes`. A change with no
    ///   update after the filter is not in the list.
    /// - Throws: An error of ``check(against:)``.
    func applied(
        to changes: some Sequence<Change>,
        readingNodesOf view: BoardView
    ) throws(KanbanError) -> [Change] {
        let keeps = try test(over: view)
        return changes.compactMap { change in
            let updates = change.nodeUpdates.filter(keeps)
            return updates.isEmpty ? nil : change.replacingNodeUpdates(updates)
        }
    }

    /// Applies the filter to the updates of one change.
    ///
    /// - Parameters:
    ///   - updates: The updates.
    ///   - view: The read view of the graph whose nodes the filter tests.
    /// - Returns: The updates that the filter keeps, in the order of `updates`.
    /// - Throws: An error of ``check(against:)``.
    func updates(of updates: [NodeUpdate], readingNodesOf view: BoardView) throws(KanbanError) -> [NodeUpdate] {
        updates.filter(try test(over: view))
    }

    /// Checks that the filter can test the nodes of the graph of a read view, as a subscription does when it starts.
    ///
    /// - Parameter view: The read view of the graph whose nodes the filter tests.
    /// - Throws: An error of ``TaskFilter/init(filtering:over:inBoard:)``, for example `AMBIGUOUS_ID` for a `^id` value
    ///   that is a short id of two or more tasks.
    func check(against view: BoardView) throws(KanbanError) {
        _ = try test(over: view)
    }

    /// Makes the test of the updates against the graph of a read view.
    ///
    /// - Parameter view: The read view of the graph whose nodes the filter tests.
    /// - Returns: The test. With no filter, it keeps each update. Else it keeps an update when the graph has the node
    ///   of the update and the node passes the filter.
    /// - Throws: An error of ``check(against:)``.
    private func test(over view: BoardView) throws(KanbanError) -> (NodeUpdate) -> Bool {
        guard let expression else {
            return { _ in true }
        }
        let nodeFilter = try TaskFilter(filtering: expression, over: view.readiness, inBoard: view.boardKey)
        let graph = view.graph
        return { update in graph.slot(for: update.ref).map(nodeFilter.matches(nodeAt:)) ?? false }
    }
}
