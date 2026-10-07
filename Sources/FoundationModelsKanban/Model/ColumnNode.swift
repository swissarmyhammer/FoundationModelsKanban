import Foundation

/// The state of a column node (plan.md §3.1).
struct ColumnNode: NodeState {
    /// The slug of the column: its local id, for example `doing`.
    let slug: String

    /// The body and the time values of the column.
    var fields: NodeFields

    /// The local ref of the column.
    var ref: LocalRef {
        .column(slug: slug)
    }

    /// The column, as a case of the ``Node`` enum.
    var node: Node {
        .column(self)
    }

    /// Does nothing, because a column has no stored edges.
    ///
    /// - Parameter transform: Not used.
    func updateEdges(using transform: (EdgeTarget) -> EdgeTarget) {}
}
