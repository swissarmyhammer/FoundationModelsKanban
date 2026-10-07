import Foundation

/// The target of one stored edge in the ``Graph`` (plan.md §3.3, §5.3).
///
/// A node from replay holds each edge as the stored ref of its target. When the node goes into the graph, the graph
/// changes each ref to the slot of its target. A ref that has no target in the graph stays unresolved: a ref to a
/// different board, or a ref to a node that is not loaded or that a broken merge removed.
enum EdgeTarget: Hashable, Sendable {
    /// The slot of the target node in the node table of the graph.
    case slot(Int)

    /// The stored ref of a target that the graph does not have.
    case unresolved(StoredRef)

    /// The slot of the target, or `nil` when the edge is unresolved.
    var resolvedSlot: Int? {
        guard case .slot(let slot) = self else {
            return nil
        }
        return slot
    }
}

/// The fields that all six node types have: the Markdown body and the time values (plan.md §4.1, §5.3).
///
/// Replay records each time value from the envelope `at` of a patch. No patch stores a time value.
struct NodeFields: Hashable, Sendable {
    /// The Markdown body of the node. It is empty when no patch set it.
    var body = ""

    /// The time of the first patch of the node.
    var created: DateTime

    /// The time of the last patch of the node.
    var updated: DateTime

    /// The time of the last `delete: true` patch, only while the node is a tombstone.
    var deleted: DateTime?

    /// `true` when the body has a full conflict block from an `edit` that could not apply (plan.md §5.5).
    var hasConflict = false

    /// The properties that the patches wrote and that the node type does not know. Replay keeps them, and no
    /// resolver reads them (plan.md §5.3, schema changes).
    var unknownProperties = PropertyBag()

    /// The tombstone flag: `true` when the node is deleted (plan.md §3.3, rule 2).
    var isDeleted: Bool {
        deleted != nil
    }
}

/// The properties of a node as the `set`, `unset`, `add`, and `remove` parts of its patches leave them (plan.md
/// §5.1).
struct PropertyBag: Hashable, Sendable {
    /// The single values: each `set` writes one, and each `unset` clears one.
    var values: [String: PatchValue] = [:]

    /// The members of the set-valued properties, in the order of their first `add`. A property with no members has
    /// no entry.
    var members: [String: [StoredRef]] = [:]
}

/// The state of one node type, as replay folds it and as the ``Graph`` stores it.
protocol NodeState: Hashable, Sendable {
    /// The local ref of the node. The graph gives one slot to each local ref.
    var ref: LocalRef { get }

    /// The body, the time values, and the unknown properties of the node. Replay writes the unknown properties
    /// through this requirement for each node type.
    var fields: NodeFields { get set }

    /// The node, as a case of the ``Node`` enum.
    var node: Node { get }

    /// Changes each stored edge of the node.
    ///
    /// - Parameter transform: Gives the new target of an edge from its current target.
    mutating func updateEdges(using transform: (EdgeTarget) -> EdgeTarget)
}

extension NodeState {
    /// Does nothing. This is the default for a node type that has no stored edges: the board, a column, and an
    /// actor.
    ///
    /// - Parameter transform: Not used, because the node has no edges to change.
    mutating func updateEdges(using transform: (EdgeTarget) -> EdgeTarget) {}
}

/// One node of the graph: the state of one of the six node types (plan.md §2.1, §3.1).
enum Node: Hashable, Sendable {
    /// The board of the repo.
    case board(BoardNode)

    /// A column of the board.
    case column(ColumnNode)

    /// An actor: a person or an agent.
    case actor(ActorNode)

    /// A tag.
    case tag(TagNode)

    /// A task.
    case task(TaskNode)

    /// A comment on a task.
    case comment(CommentNode)

    /// The state of the node.
    var state: any NodeState {
        switch self {
        case .board(let board): board
        case .column(let column): column
        case .actor(let actor): actor
        case .tag(let tag): tag
        case .task(let task): task
        case .comment(let comment): comment
        }
    }

    /// The local ref of the node.
    var ref: LocalRef {
        state.ref
    }

    /// The stored edges of the node, in the order of their properties.
    var edges: [EdgeTarget] {
        var copy = self
        var found: [EdgeTarget] = []
        copy.updateEdges { edge in
            found.append(edge)
            return edge
        }
        return found
    }

    /// Changes each stored edge of the node.
    ///
    /// - Parameter transform: Gives the new target of an edge from its current target.
    mutating func updateEdges(using transform: (EdgeTarget) -> EdgeTarget) {
        var state = state
        state.updateEdges(using: transform)
        self = state.node
    }
}
