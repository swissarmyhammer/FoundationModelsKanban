import Foundation

/// The state of a tag node (plan.md §3.1, §6.2).
struct TagNode: NodeState {
    /// The slug of the tag: its local id, for example `bug`.
    let slug: String

    /// The body and the time values of the tag.
    var fields: NodeFields

    /// The name of the tag. It is empty when no patch set it.
    var name = ""

    /// The color that a patch set, or `nil` when no patch set one. The projection then gives the auto color of the
    /// slug (``AutoColor``).
    var color: String?

    /// The `renamedTo` edge: the tag that a rename made this tag point to, or `nil` when the tag is not renamed.
    var renamedTo: EdgeTarget?

    /// The local ref of the tag.
    var ref: LocalRef {
        .tag(slug: slug)
    }

    /// The tag, as a case of the ``Node`` enum.
    var node: Node {
        .tag(self)
    }

    /// Changes the `renamedTo` edge.
    ///
    /// - Parameter transform: Gives the new target of an edge from its current target.
    mutating func updateEdges(using transform: (EdgeTarget) -> EdgeTarget) {
        renamedTo = renamedTo.map(transform)
    }
}
