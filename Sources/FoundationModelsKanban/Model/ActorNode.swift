import Foundation

/// The state of an actor node: a person or an agent (plan.md §3.1).
struct ActorNode: NodeState {
    /// The slug of the actor: its local id, for example `claude-code`.
    let slug: String

    /// The body and the time values of the actor.
    var fields: NodeFields

    /// The local ref of the actor.
    var ref: LocalRef {
        .actor(slug: slug)
    }

    /// The actor, as a case of the ``Node`` enum.
    var node: Node {
        .actor(self)
    }

    /// Does nothing, because an actor has no stored edges.
    ///
    /// - Parameter transform: Not used.
    func updateEdges(using transform: (EdgeTarget) -> EdgeTarget) {}
}
