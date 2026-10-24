import Foundation

/// What the value of an atom names, after the resolve of a URL.
enum FilterAtomTarget {
    /// A short form in this board: a name, a slug, or a ULID form. A URL with the current key gives its local id.
    case local(String)

    /// A node of a different board.
    case remote(NodeURI)
}

/// The state of a node that a filter atom can name by its slug or by the slug of its name: a tag, an actor, or a
/// column.
protocol SlugNamedState: NodeState {
    /// The slug of the node: its local id.
    var slug: String { get }

    /// The name of the node.
    var name: String { get }
}

extension TagNode: SlugNamedState {}

extension ActorNode: SlugNamedState {}

extension ColumnNode: SlugNamedState {}

/// The one name resolution of the filter language for one board (plan.md §6.3, divergence.md §17).
///
/// The evaluator (``FilterEvaluator``) uses it to make the test of each atom, and the name check of the filter agent
/// (``FilterNameCheck``) uses it to find a name that names nothing. Thus the two read a name with the same rules. Each
/// match ignores case.
struct FilterNames {
    /// The readiness of the tasks of the board.
    let readiness: Readiness

    /// The current key of the board.
    let boardKey: String

    /// The graph of the board.
    var graph: Graph {
        readiness.graph
    }

    /// Finds what the value of an atom names for the test of a task.
    ///
    /// - Parameters:
    ///   - value: The value of the atom.
    ///   - kind: The kind of the atom.
    /// - Returns: The local form or the URI of a different board, or `nil` when the value is a URL of a node type
    ///   that the task test of the atom does not read, for example a column URL after `^`.
    func target(of value: FilterValue, for kind: FilterAtomKind) -> FilterAtomTarget? {
        switch value {
        case .name(let name):
            return .local(name)
        case .uri(let uri):
            guard uri.ref.nodeType == kind.bareURLType else {
                return nil
            }
            guard let localID = uri.localRef(inBoard: boardKey)?.localID else {
                return .remote(uri)
            }
            return .local(localID)
        }
    }

    /// Finds the live tag that a tag name names, after the rename redirect (``RefResolver``).
    ///
    /// - Parameter name: The tag name or the slug.
    /// - Returns: The slot of the tag at the end of the rename chain, or `nil` when the name names no live tag.
    func liveTagSlot(named name: String) -> Int? {
        let resolver = RefResolver(graph: graph, boardKey: boardKey)
        guard case .local(let ref)? = try? resolver.storedRef(for: name, ofType: .tag) else {
            return nil
        }
        return graph.slot(for: ref)
    }

    /// Finds the live nodes of one type whose slug, or the slug of whose name, is the slug of a name.
    ///
    /// - Parameters:
    ///   - type: The state type of the nodes, for example `ActorNode.self`.
    ///   - name: The name as the filter writes it.
    /// - Returns: The slots of the nodes. A name that gives an empty slug gives no slots.
    func liveSlots<State: SlugNamedState>(of type: State.Type, named name: String) -> Set<Int> {
        let key = Slug.normalizedText(of: name)
        guard !key.isEmpty else {
            return []
        }
        return Set(
            graph.allSlots.filter { slot in
                graph.node(at: slot, as: type).map { node in matches(liveNode: node, withSlug: key) } ?? false
            }
        )
    }

    /// Gives the live nodes of one type, in slot order.
    ///
    /// - Parameter type: The state type of the nodes, for example `TagNode.self`.
    /// - Returns: The states of the nodes that are not tombstones.
    func liveNodes<State: SlugNamedState>(of type: State.Type) -> [State] {
        graph.allSlots.compactMap { slot in graph.node(at: slot, as: type) }.filter { node in !node.fields.isDeleted }
    }

    /// Tells if a task of the board has as its assignee an actor of a different board with a slug
    /// (``isRemoteActor(_:withSlug:)``).
    ///
    /// - Parameter name: The slug or the name of the actor, in any case.
    /// - Returns: `true` when the `assignees` edge of a task names such an actor.
    func hasRemoteAssignee(named name: String) -> Bool {
        let key = Slug.normalizedText(of: name)
        return graph.allSlots.contains { slot in
            graph.node(at: slot, as: TaskNode.self)?.assignees.contains { edge in
                guard case .unresolved(let ref) = edge else {
                    return false
                }
                return isRemoteActor(ref, withSlug: key)
            } ?? false
        }
    }

    /// Tells if an assignee that is not a slot of this board is an actor of a different board with a slug.
    ///
    /// When a loaded board has the actor, the actor matches when it is live and its slug, or the slug of its name, is
    /// the key. When no loaded board has the actor, for example when its board cannot be read, the slug in the URI
    /// decides, so that the filter keeps working (divergence.md Q7).
    ///
    /// - Parameters:
    ///   - ref: The stored ref of the assignee.
    ///   - key: The slug to find. An empty key matches nothing.
    /// - Returns: `true` when the ref is the URI of an actor of a different board with the slug.
    func isRemoteActor(_ ref: StoredRef, withSlug key: String) -> Bool {
        guard !key.isEmpty, case .remote(let uri) = ref, uri.ref.nodeType == .actor else {
            return false
        }
        guard let found = readiness.related.node(for: ref, as: ActorNode.self) else {
            return uri.ref.localID == key
        }
        return matches(liveNode: found.state, withSlug: key)
    }

    /// Tells if a node is live, and has a slug, or the slug of a name, that is a key.
    ///
    /// - Parameters:
    ///   - node: The state of the node.
    ///   - key: The slug to find.
    /// - Returns: `true` when the node is live and the slug of the node or of its name is the key.
    private func matches(liveNode node: some SlugNamedState, withSlug key: String) -> Bool {
        !node.fields.isDeleted && (node.slug == key || Slug.normalizedText(of: node.name) == key)
    }
}
