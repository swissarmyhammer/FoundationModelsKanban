import Foundation

/// The in-memory graph of one board: a node table with stable slots (plan.md §3.3, §5.3 Join, §5.6).
///
/// Each node has a **slot**: an integer index into the node table. A local ref gets its slot one time, and keeps it
/// for the life of the graph, also after a remove. Each stored edge holds an ``EdgeTarget``: the slot of its target,
/// or the stored ref of a target that the graph does not have. Thus, a replace of one node changes only its slot, and
/// the edges of the other nodes stay correct.
///
/// The graph is a value type. Its storage is Swift arrays and dictionaries, so a copy is cheap (copy-on-write), and a
/// change to a copy does not change the original. A mutation works on such a copy (plan.md §5.4).
struct Graph: Sendable {
    /// The node table. The index of a node is its slot. A slot whose node was removed holds `nil`.
    private var nodes: [Node?] = []

    /// The slot of each local ref that the graph has had.
    private var slots: [LocalRef: Int] = [:]

    /// For each local ref that the graph does not have now: the slots of the nodes that have an unresolved edge to
    /// it. An insert of the ref resolves the edges of these nodes, with no scan of the full table.
    private var waiting: [LocalRef: Set<Int>] = [:]

    /// Gives the slot of a local ref.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The slot, or `nil` when the graph never had the ref. A ref keeps its slot after a remove.
    func slot(for ref: LocalRef) -> Int? {
        slots[ref]
    }

    /// Gives the node in a slot.
    ///
    /// - Parameter slot: A slot that this graph gave.
    /// - Returns: The node, or `nil` when the node was removed.
    func node(at slot: Int) -> Node? {
        nodes[slot]
    }

    /// Inserts a node, or replaces the state of the node with the same local ref.
    ///
    /// The graph resolves each unresolved local edge of the node to the slot of its target, when the graph has the
    /// target. Then it resolves the edges of the other nodes that wait for this node. A replace keeps the slot, so
    /// the edges to the node stay correct.
    ///
    /// - Parameter node: The new state of the node.
    /// - Returns: The slot of the node.
    @discardableResult
    mutating func update(with node: Node) -> Int {
        let ref = node.ref
        let slot = slots[ref] ?? makeSlot(for: ref)
        var resolvedNode = node
        resolvedNode.updateEdges { edge in
            resolve(edge, heldBy: slot)
        }
        nodes[slot] = resolvedNode
        resolveWaitingEdges(to: ref, at: slot)
        return slot
    }

    /// Removes the node of a local ref from its slot. The ref keeps its slot for a later insert.
    ///
    /// Each edge to the node becomes an unresolved edge with the local ref of the node (plan.md §3.3, rule 4). A later
    /// insert of the same ref resolves these edges again. A ref that the graph does not have changes nothing.
    ///
    /// - Parameter ref: The local ref of the node.
    mutating func remove(nodeAt ref: LocalRef) {
        guard let slot = slots[ref], nodes[slot] != nil else {
            return
        }
        nodes[slot] = nil
        let removedEdge = EdgeTarget.slot(slot)
        let unresolvedEdge = EdgeTarget.unresolved(.local(ref))
        let holders = nodes.indices.filter { holder in
            nodes[holder]?.edges.contains(removedEdge) == true
        }
        replaceEdges(removedEdge, with: unresolvedEdge, inNodesAt: holders)
        waiting[ref, default: []].formUnion(holders)
    }
}

// MARK: - Join

extension Graph {
    /// Adds an empty slot at the end of the node table for a local ref.
    ///
    /// - Parameter ref: The local ref that gets the slot.
    /// - Returns: The new slot.
    private mutating func makeSlot(for ref: LocalRef) -> Int {
        let slot = nodes.endIndex
        nodes.append(nil)
        slots[ref] = slot
        return slot
    }

    /// Resolves one edge of a node that goes into the graph.
    ///
    /// An unresolved local edge becomes the slot of its target when the graph has the target. When the graph does not
    /// have the target, the edge stays unresolved, and the node waits for the target. A remote edge stays unresolved,
    /// because its target is in a different board.
    ///
    /// - Parameters:
    ///   - edge: The edge.
    ///   - holder: The slot of the node that has the edge.
    /// - Returns: The resolved edge, or the same edge when it cannot resolve.
    private mutating func resolve(_ edge: EdgeTarget, heldBy holder: Int) -> EdgeTarget {
        guard case .unresolved(.local(let ref)) = edge else {
            return edge
        }
        if let target = slots[ref], nodes[target] != nil {
            return .slot(target)
        }
        waiting[ref, default: []].insert(holder)
        return edge
    }

    /// Resolves the edges of the nodes that wait for a local ref that now has a node.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the new node.
    ///   - slot: The slot of the new node.
    private mutating func resolveWaitingEdges(to ref: LocalRef, at slot: Int) {
        guard let holders = waiting.removeValue(forKey: ref) else {
            return
        }
        replaceEdges(.unresolved(.local(ref)), with: .slot(slot), inNodesAt: holders)
    }

    /// Changes each edge with one target to a new target, in the nodes of some slots.
    ///
    /// - Parameters:
    ///   - oldEdge: The edge to change.
    ///   - newEdge: The edge that replaces it.
    ///   - holders: The slots of the nodes to change. A slot whose node was removed is skipped.
    private mutating func replaceEdges(
        _ oldEdge: EdgeTarget,
        with newEdge: EdgeTarget,
        inNodesAt holders: some Sequence<Int>
    ) {
        for holder in holders {
            nodes[holder]?.updateEdges { edge in
                edge == oldEdge ? newEdge : edge
            }
        }
    }
}
