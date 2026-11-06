import FoundationModelsExtras

/// The write actor of one call: the actor of each event that the call writes (plan.md §6, divergence.md §26).
///
/// A call of a client whose ``GraphQLViewer`` has a person writes as that person (``init(person:)``). Each other call
/// writes as the session actor of the view, for example a model tool call. A call that writes to a board makes sure
/// that the actor exists in that board: it writes an actor `set` patch with ``name`` when the actor is new, and for a
/// person also when the name or the ids changed.
struct SessionActor: Equatable, Sendable {
    /// The local ref of the actor, for example `actor/claude-code` or `actor/local-wballard`.
    let ref: LocalRef

    /// The name of the actor, for example `Claude Code`.
    let name: String

    /// The ids of the person, the id first and then the earlier ids, or the empty list for the session actor of a
    /// view. The actor node records them as ``ActorNode/aliases``.
    let personIDs: [String]

    /// Makes the actor of a ref and a name, with no person ids: the session actor of a view.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the actor.
    ///   - name: The name of the actor.
    init(ref: LocalRef, name: String) {
        self.init(ref: ref, name: name, personIDs: [])
    }

    /// Makes the actor of a ref, a name, and the ids of a person.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the actor.
    ///   - name: The name of the actor.
    ///   - personIDs: The ids of the person, the id first.
    private init(ref: LocalRef, name: String, personIDs: [String]) {
        self.ref = ref
        self.name = name
        self.personIDs = personIDs
    }

    /// Makes the write actor of a person that a client gives in its ``GraphQLViewer``.
    ///
    /// The ref is the actor ref of the slug of the id: `local/wballard` gives `actor/local-wballard`. The ref of a
    /// board can be different: ``resolved(in:)`` finds the actor node of the person in that board.
    ///
    /// - Parameter person: The person of the viewer.
    /// - Throws: ``KanbanError/invalidSlug(name:)`` when the id gives an empty slug.
    ///   ``KanbanError/reservedSlug(type:)`` when the id gives the slug ``Slug/reservedForBoard``.
    init(person: GraphQLActor) throws(KanbanError) {
        let ref = try Self.ref(ofPersonID: person.id)
        try ref.checkSlugIsNotReserved()
        var ids = [person.id]
        for alias in person.aliases where !ids.contains(alias) {
            ids.append(alias)
        }
        self.init(ref: ref, name: person.name, personIDs: ids)
    }

    /// `true` when the actor is a person that a client gave, `false` for the session actor of a view.
    var isPerson: Bool {
        !personIDs.isEmpty
    }

    /// Gives the actor ref of the slug of one id of a person.
    ///
    /// - Parameter id: The id, for example `local/wballard`.
    /// - Returns: The actor ref, for example `actor/local-wballard`.
    /// - Throws: ``KanbanError/invalidSlug(name:)`` when the id gives an empty slug.
    private static func ref(ofPersonID id: String) throws(KanbanError) -> LocalRef {
        .actor(slug: try Slug(columnOrActorName: id).value)
    }

    /// The actor refs of the slugs of the ids of the person. An id that gives no slug gives no ref.
    private var slugRefs: [LocalRef] {
        personIDs.compactMap { id in try? Self.ref(ofPersonID: id) }
    }

    /// Tells if an actor node of a graph is a node of this person: its ref is the ref of an id of the person, or it
    /// records one of the ids of the person (``ActorNode/aliases``).
    ///
    /// - Parameter node: The actor node.
    /// - Returns: `true` for a node of this person. For the session actor, `true` only for the node of ``ref``.
    private func owns(_ node: ActorNode) -> Bool {
        node.ref == ref || slugRefs.contains(node.ref) || node.aliases.contains { id in personIDs.contains(id) }
    }

    /// Gives the actor as it writes to a board: the same actor, with the ref of the actor node of the person in the
    /// graph of that board.
    ///
    /// The order is: the node of the slug of the id when the graph has it; else a live actor node of the person
    /// (``owns(_:)``), the lowest slot first; else the ref of the slug of the id, for a new node. The session actor
    /// of a view does not change.
    ///
    /// - Parameter graph: The graph of the board.
    /// - Returns: The actor with the ref that the call writes.
    func resolved(in graph: Graph) -> SessionActor {
        guard isPerson, graph.slot(for: ref) == nil else {
            return self
        }
        let owner = graph.allSlots.lazy.compactMap { slot in graph.node(at: slot, as: ActorNode.self) }
            .first { node in !node.fields.isDeleted && owns(node) }
        guard let owner else {
            return self
        }
        return SessionActor(ref: owner.ref, name: name, personIDs: personIDs)
    }

    /// Gives the refs of the actor nodes of this actor in a graph: ``ref``, and for a person each node of the person
    /// (``owns(_:)``). `undoChange` and `redoChange` with no `txn` take only a transaction of one of these refs.
    ///
    /// - Parameter graph: The graph of the board.
    /// - Returns: The refs.
    func ownRefs(in graph: Graph) -> Set<LocalRef> {
        guard isPerson else {
            return [ref]
        }
        var refs = Set(slugRefs).union([ref])
        for slot in graph.allSlots {
            if let node = graph.node(at: slot, as: ActorNode.self), owns(node) {
                refs.insert(node.ref)
            }
        }
        return refs
    }

    /// Gives the ids that the actor node of this person records after a write: the ids that the node records and
    /// the ids of the person, in sort order with no copy.
    ///
    /// - Parameter node: The actor node in the graph, or `nil` for a new node.
    /// - Returns: The ids.
    func aliases(merging node: ActorNode?) -> [String] {
        Set((node?.aliases ?? []) + personIDs).sorted()
    }
}
