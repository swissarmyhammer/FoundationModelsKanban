import Foundation

/// The tasks that one task list of a query selects (plan.md §6.3): the filter, and the default rule of
/// ``TaskFilter``.
///
/// The filter applies to `Board.tasks`, to `Board.nextTask`, to `Board.searchTasks`, and to the `tasks` fields of
/// `Column`, `Actor`, and `Tag`. A filter that is empty or does not parse gives `INVALID_FILTER`. A value that names
/// nothing gives no task.
///
/// A list leaves out the tasks in a hidden state (``VirtualTag/hiddenUnlessNamed``): the done tasks and the
/// tombstones. A filter that names the tag of a state also selects from the tasks in that state, and the filter
/// decides (``TaskFilter``, plan.md §3.3 rule 3).
struct TaskSelection {
    /// The full filter: the scope ANDed with the `filter` argument, or `nil` when the list has neither.
    private let filter: FilterExpr?

    /// Makes the selection of a list.
    ///
    /// - Parameters:
    ///   - text: The `filter` argument, or `nil` when the call gives no filter.
    ///   - scope: The atom of the node that holds the list, for example `%doing` for the `tasks` field of a column,
    ///     or `nil` for a list of the board. It is ANDed with the filter, so it also names a hidden state: a column
    ///     scope names `DONE` (``FilterExpr/names(_:)``).
    /// - Throws: ``KanbanError/invalidFilter(filter:position:detail:example:)`` when the filter is empty or does not
    ///   parse.
    init(filtering text: String?, within scope: FilterExpr? = nil) throws(KanbanError) {
        let expression = try text.map { text throws(KanbanError) in try FilterExpr(parsing: text) }
        switch (scope, expression) {
        case (let scope?, let expression?):
            filter = .and(scope, expression)
        case (let scope?, nil):
            filter = scope
        case (nil, let expression):
            filter = expression
        }
    }

    /// Gives the selected tasks of a board, in board order.
    ///
    /// - Parameters:
    ///   - view: The read view of the board.
    ///   - isIncluded: One more test that each task must pass, for example "the task has the virtual tag `READY`".
    /// - Returns: The tasks that pass `isIncluded` and the ``TaskFilter`` of the filter: a task in a hidden state
    ///   only when the filter names that state.
    func tasks(in view: BoardView, where isIncluded: (TaskObject) -> Bool = { _ in true }) -> [TaskObject] {
        let taskFilter = TaskFilter(filtering: filter, over: view.readiness, inBoard: view.boardKey)
        return view.allTasks.filter { task in
            isIncluded(task) && taskFilter.matches(taskAt: task.slot)
        }
    }
}
