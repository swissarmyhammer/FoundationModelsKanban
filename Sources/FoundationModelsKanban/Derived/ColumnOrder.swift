import Foundation

/// The live columns of a board in board order, and the column where each task shows (plan.md §5.3 step 5, §6).
///
/// - The board order sorts the columns by `order`. Two columns with the same `order` sort by slug (plan.md §5.3
///   step 5). A tombstoned column is not in the order.
/// - The **first column** has the minimum `order`. The **terminal column** has the maximum `order`. A task in the
///   terminal column is done.
/// - A task shows in its column when that column is live. A task with no column, or with a column that is tombstoned
///   or that the graph does not have, shows in the first column (plan.md §5.3 step 5). Thus, on a board with one
///   column, such a task is in the terminal column, and it is done.
struct ColumnOrder {
    /// The slots of the live columns, in board order.
    let slots: [Int]

    /// The slots of the live columns, for a fast membership test.
    private let liveSlots: Set<Int>

    /// Sorts the live columns of a graph.
    ///
    /// - Parameter graph: The graph of the board.
    init(of graph: Graph) {
        let columns = graph.allSlots.compactMap { slot -> (slot: Int, column: ColumnNode)? in
            guard let column = graph.node(at: slot, as: ColumnNode.self), !column.fields.isDeleted else {
                return nil
            }
            return (slot, column)
        }
        slots = columns.sorted { lhs, rhs in
            (lhs.column.order, lhs.column.slug) < (rhs.column.order, rhs.column.slug)
        }
        .map(\.slot)
        liveSlots = Set(slots)
    }

    /// The slot of the first column, or `nil` when the board has no live column.
    var first: Int? {
        slots.first
    }

    /// The slot of the terminal column, or `nil` when the board has no live column.
    var terminal: Int? {
        slots.last
    }

    /// Gives the column where a task shows.
    ///
    /// - Parameter column: The `column` edge of the task, or the column of one of its moves.
    /// - Returns: The slot of the column when it is live, else the slot of the first column. The value is `nil` only
    ///   when the board has no live column.
    func displaySlot(of column: EdgeTarget?) -> Int? {
        guard let slot = column?.resolvedSlot, liveSlots.contains(slot) else {
            return first
        }
        return slot
    }

    /// Tells if a task shows in the terminal column: the task is done.
    ///
    /// - Parameter column: The `column` edge of the task.
    /// - Returns: `true` when the board has a live column and the task shows in the terminal column.
    func isTerminal(_ column: EdgeTarget?) -> Bool {
        terminal != nil && displaySlot(of: column) == terminal
    }
}
