import Foundation

/// The state of a column node (plan.md §3.1).
struct ColumnNode: NodeState {
    /// The slug of the column: its local id, for example `doing`.
    let slug: String

    /// The body and the time values of the column.
    ///
    /// The synthesized `Hashable` `==` and `hash(into:)` read it; periphery sees no caller. The projection and the
    /// queries read it later (plan.md §5.3).
    // periphery:ignore
    var fields: NodeFields

    /// The local ref of the column.
    var ref: LocalRef {
        .column(slug: slug)
    }

    /// The column, as a case of the ``Node`` enum.
    var node: Node {
        .column(self)
    }
}
