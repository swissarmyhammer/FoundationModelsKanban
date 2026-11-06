import Foundation

/// The state of an actor node: a person or an agent (plan.md §3.1).
struct ActorNode: NodeState {
    /// The slug of the actor: its local id, for example `claude-code`.
    let slug: String

    /// The body and the time values of the actor.
    var fields: NodeFields

    /// The name of the actor. It is empty when no patch set it.
    var name = ""

    /// The color of the actor, or `nil` when the actor has no color.
    var color: String?

    /// The avatar of the actor, for example a URL or an emoji, or `nil` when the actor has no avatar (divergence.md
    /// Q19).
    var avatar: String?

    /// The ids of the person that this actor records, for example `local/wballard` and the iCloud user record id, in
    /// sort order. A call of a client writes them (``SessionActor``). The list is empty for an actor that no client
    /// wrote, for example the agent of the session.
    var aliases: [String] = []

    /// The local ref of the actor.
    var ref: LocalRef {
        .actor(slug: slug)
    }

    /// The actor, as a case of the ``Node`` enum.
    var node: Node {
        .actor(self)
    }
}
