import Graphiti

/// A public mutation whose `input` object has the same fields as the `input` object of a different mutation, for
/// example `deleteTask` and `undeleteTask`.
///
/// EXTRAS-9 rule 7 gives each mutation the form `verbNoun(input: VerbNounInput!)`, so each mutation has an `input` type
/// of its own name. Graphiti gives each Swift type one GraphQL type, so the Swift type of a shared `input` shape is
/// generic over a type of this protocol, and each mutation adds the specialization of its own type to the schema with
/// the name ``inputTypeName``. The type is a ``SendableMetatype``, so that a resolver can use it in a concurrent
/// closure.
protocol SharedInputMutation: SendableMetatype {
    /// The name of the mutation, from ``MutationName``.
    static var name: String { get }
}

extension SharedInputMutation {
    /// The GraphQL name of the `input` type of the mutation: the name of the mutation with its first letter in
    /// uppercase, and then `Input`, for example `DeleteTaskInput` for `deleteTask` (EXTRAS-9 rule 7).
    static var inputTypeName: String {
        "\(name.prefix(1).uppercased())\(name.dropFirst())Input"
    }
}

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Gives the `input` type of a mutation that names one node and has no other field (``NodeReferenceInput``), with
    /// the name of the mutation (EXTRAS-9 rule 7).
    ///
    /// - Parameter mutation: The mutation of the `input` type.
    /// - Returns: The `input` type `<Mutation>Input`, with its one field `id`.
    static func makeNodeReferenceInput<Mutation: SharedInputMutation>(
        of mutation: Mutation.Type
    ) -> Input<KanbanResolver, KanbanContext, NodeReferenceInput<Mutation>> {
        Input(NodeReferenceInput<Mutation>.self, as: NodeReferenceInput<Mutation>.inputTypeName) {
            InputField("id", at: \.id).description(SchemaDescription.nodeReference)
        }
        .description(SchemaDescription.nodeReferenceInput(of: mutation.name))
    }
}
