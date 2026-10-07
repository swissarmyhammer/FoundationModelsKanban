import Foundation

extension Readiness {
    /// Gives the time when a task started: the `started` field (plan.md §5.3 step 4).
    ///
    /// The value is the time of the first column move to a column that is not the first column, in the current column
    /// order. A move to a column that is tombstoned or that the graph does not have counts as a move to the first
    /// column, because a task in such a column shows in the first column (``ColumnOrder/displaySlot(of:)``).
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: The time of the move, or `nil` when the task never left the first column. A slot that holds no task
    ///   gives `nil`.
    func started(ofTaskAt slot: Int) -> DateTime? {
        let start = columnMoves(ofTaskAt: slot).first { move in
            columnOrder.displaySlot(of: move.column) != columnOrder.first
        }
        return start?.at
    }

    /// Gives the time when a task was completed: the `completed` field (plan.md §5.3 step 4).
    ///
    /// The value is the time of the last column move, only when the task is now done. Thus, a new column with a
    /// larger `order` clears the value of each task in the old terminal column.
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: The time of the last move, or `nil` when the task is not done or has no move.
    func completed(ofTaskAt slot: Int) -> DateTime? {
        guard isDone(taskAt: slot) else {
            return nil
        }
        return columnMoves(ofTaskAt: slot).last?.at
    }

    /// Gives the column moves of a task, in the order that replay recorded them.
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: The moves. A slot that holds no task gives no moves.
    private func columnMoves(ofTaskAt slot: Int) -> [ColumnMove] {
        graph.node(at: slot, as: TaskNode.self)?.columnMoves ?? []
    }
}
