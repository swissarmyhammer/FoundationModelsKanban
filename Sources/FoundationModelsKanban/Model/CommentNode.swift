import Foundation
import ULID

/// The state of a comment node. A comment is a full node with its own id (plan.md §3.1, §3.2).
struct CommentNode: NodeState {
    /// The ULID of the comment: its local id.
    let id: ULID

    /// The body and the time values of the comment. The body is the comment text.
    var fields: NodeFields

    /// The `task` edge: the task of the comment, or `nil` when no patch set it.
    var task: EdgeTarget?

    /// The `author` edge: the actor that wrote the comment, or `nil` when no patch set it.
    var author: EdgeTarget?

    /// The local ref of the comment.
    var ref: LocalRef {
        .comment(id)
    }

    /// The comment, as a case of the ``Node`` enum.
    var node: Node {
        .comment(self)
    }

    /// Changes the `task` and `author` edges.
    ///
    /// - Parameter transform: Gives the new target of an edge from its current target.
    mutating func updateEdges(using transform: (EdgeTarget) -> EdgeTarget) {
        task = task.map(transform)
        author = author.map(transform)
    }
}
