import Graphiti

/// The caller of one call, as the GraphQL `Viewer` type (divergence.md §26).
struct ViewerObject: Sendable {
    /// The write actor of the call: the actor node that the changes of the call reference.
    let actor: ActorObject
}

extension KanbanResolver {
    /// Resolves `Query.viewer`: the write actor of the call, as the actor node of the current board (divergence.md
    /// §26).
    ///
    /// A call of a client with a person gives the actor node of that person. Each other call gives the session actor
    /// of the view. The `id` of the actor is the same `id` as the `Change.actor` of a change that the caller wrote,
    /// so a client compares the two to find its own changes. Before the first write of the actor, the board has no
    /// node of the actor: the field then gives the actor as the next write makes it. The field writes no event.
    ///
    /// - Parameters:
    ///   - context: The context of the call. Its store holds the write actor.
    ///   - arguments: No arguments.
    /// - Returns: The caller.
    func viewer(context: KanbanContext, arguments _: NoArguments) async -> ViewerObject {
        let (view, actor) = (await context.store.view, context.store.sessionActor)
        let graph = view.graph
        if let slot = graph.slot(for: actor.ref), let state = graph.node(at: slot, as: ActorNode.self) {
            return ViewerObject(actor: ActorObject(view: view, slot: slot, state: state))
        }
        let time = context.clock()
        guard case .actor(let slug) = actor.ref else {
            preconditionFailure("The write actor \(actor.ref) is not the ref of an actor")
        }
        let state = ActorNode(
            slug: slug,
            fields: NodeFields(created: time, updated: time),
            name: actor.name,
            aliases: actor.aliases(merging: nil)
        )
        return ViewerObject(actor: ActorObject(view: view, slot: graph.allSlots.upperBound, state: state))
    }
}

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the `Viewer` type of `Query.viewer` (divergence.md §26).
    ///
    /// - Returns: This builder, for method chaining.
    func addViewerTypes() -> Self {
        add {
            Type(ViewerObject.self, as: GraphQLTypeName.viewer) {
                Field("actor", at: \.actor).description(SchemaDescription.viewerActor)
            }
            .description(SchemaDescription.viewer)
        }
    }
}
