import Foundation

/// The state of a column node (plan.md §3.1).
struct ColumnNode: NodeState {
    /// The slug of the column: its local id, for example `doing`.
    let slug: String

    /// The body and the time values of the column.
    var fields: NodeFields

    /// The name of the column. It is empty when no patch set it.
    var name = ""

    /// The sort key of the column on the board. Two columns with the same order sort by slug (plan.md §5.3). It is 0
    /// when no patch set it.
    var order = 0

    /// The local ref of the column.
    var ref: LocalRef {
        .column(slug: slug)
    }

    /// The column, as a case of the ``Node`` enum.
    var node: Node {
        .column(self)
    }
}
