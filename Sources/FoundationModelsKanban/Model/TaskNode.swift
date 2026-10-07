import Foundation
import ULID

/// One move of a task to a column: the time of a `set column` patch and the column that it set (plan.md §5.3).
///
/// The `started` and `completed` times of a task come from these moves at read time, because they depend on the
/// column order, and the column order can change later.
struct ColumnMove: Hashable, Sendable {
    /// The envelope time of the patch that moved the task.
    let at: DateTime

    /// The column that the patch set.
    var column: EdgeTarget
}

/// The state of a task node (plan.md §3.1).
struct TaskNode: NodeState {
    /// The ULID of the task: its local id.
    let id: ULID

    /// The body and the time values of the task.
    var fields: NodeFields

    /// The title of the task. It is empty when no patch set it.
    var title = ""

    /// The `column` edge, or `nil` when no patch set a column.
    var column: EdgeTarget?

    /// The position of the task in its column (plan.md §3.2). It is ``Ordinal/first`` when no patch set it.
    var ordinal = Ordinal.first

    /// The `assignees` edges: the actors of the task.
    var assignees: [EdgeTarget] = []

    /// The `tags` edges.
    var tags: [EdgeTarget] = []

    /// The `dependsOn` edges: the tasks that this task waits for, in this board or in a different board.
    var dependsOn: [EdgeTarget] = []

    /// Each move of the task to a column, in event order.
    var columnMoves: [ColumnMove] = []

    /// The local ref of the task.
    var ref: LocalRef {
        .task(id)
    }

    /// The task, as a case of the ``Node`` enum.
    var node: Node {
        .task(self)
    }

    /// Changes the `column`, `assignees`, `tags`, and `dependsOn` edges, and the column of each move.
    ///
    /// - Parameter transform: Gives the new target of an edge from its current target.
    mutating func updateEdges(using transform: (EdgeTarget) -> EdgeTarget) {
        column = column.map(transform)
        assignees = assignees.map(transform)
        tags = tags.map(transform)
        dependsOn = dependsOn.map(transform)
        columnMoves = columnMoves.map { move in
            ColumnMove(at: move.at, column: transform(move.column))
        }
    }
}
