import Graphiti
import GraphQL

/// The type of the node that a patch changes (plan.md §5.1).
enum PatchNodeType: String, Codable, Sendable, CaseIterable {
    /// The board.
    case board = "Board"

    /// A column of the board.
    case column = "Column"

    /// A task.
    case task = "Task"

    /// An actor: a person or an agent.
    case actor = "Actor"

    /// A tag.
    case tag = "Tag"

    /// A comment on a task.
    case comment = "Comment"
}

/// The `input` of the internal `patch` mutation: one property patch on one
/// node (plan.md §5.1).
///
/// Each part is optional, except `node` and `type`. The parts that hold
/// property values are `JSON` values.
struct PatchInput: Codable, Sendable {
    /// The local ref of the node that the patch changes.
    let node: String

    /// The type of the node.
    let type: PatchNodeType

    /// The properties to write. A value replaces the old value.
    let set: Map?

    /// The names of the properties to clear.
    let unset: [String]?

    /// The values to add to set-valued properties.
    let add: Map?

    /// The values to remove from set-valued properties.
    let remove: Map?

    /// `true` makes a tombstone. `false` removes the tombstone.
    let delete: Bool?

    /// A unified diff for the Markdown body: `{"body": "<unified diff>"}`.
    let edit: Map?
}

/// The arguments of the internal `patch` mutation.
struct PatchArguments: Codable, Sendable {
    /// The patch.
    let input: PatchInput
}

extension PatchInput {
    /// The patch as a `JSON` value. A part that is not set is not in the value.
    ///
    /// The value is made directly, not with `MapEncoder`, because
    /// `MapEncoder` changes each `Bool` to a number.
    var map: Map {
        [
            "node": .string(node),
            "type": .string(type.rawValue),
            "set": set ?? .undefined,
            "unset": unset.map { .array($0.map(Map.string)) } ?? .undefined,
            "add": add ?? .undefined,
            "remove": remove ?? .undefined,
            "delete": delete.map(Map.bool) ?? .undefined,
            "edit": edit ?? .undefined,
        ]
    }
}

extension KanbanResolver {
    /// Resolves the internal `Mutation.patch`.
    ///
    /// This step has no event log, so the stub applies nothing. It returns
    /// the patch that the engine decoded, as a `JSON` value. Thus a caller
    /// sees the patch in the form that a later step applies.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The patch.
    /// - Returns: The decoded patch.
    func patch(context _: KanbanContext, arguments: PatchArguments) async -> Map {
        arguments.input.map
    }
}

/// The internal GraphQL schema of the event log.
///
/// Each log line is a request to the `patch` mutation of this schema
/// (plan.md §5.1). The schema is separate from ``PublicSchema``, so that the
/// model cannot write a patch directly (plan.md §12, item 9).
struct PatchSchema: API {
    /// The root resolver.
    let resolver = KanbanResolver()

    /// The schema that Graphiti makes from the Swift types.
    let schema: Schema<KanbanResolver, KanbanContext>

    /// Makes the schema.
    ///
    /// - Throws: An error from Graphiti when a type of the schema is not valid.
    init() throws {
        schema = try SchemaBuilder.makeKanbanBuilder()
            .add {
                Enum(PatchNodeType.self) {
                    Value(.board)
                    Value(.column)
                    Value(.task)
                    Value(.actor)
                    Value(.tag)
                    Value(.comment)
                }
                Input(PatchInput.self) {
                    InputField("node", at: \.node)
                    InputField("type", at: \.type)
                    InputField("set", at: \.set)
                    InputField("unset", at: \.unset)
                    InputField("add", at: \.add)
                    InputField("remove", at: \.remove)
                    InputField("delete", at: \.delete)
                    InputField("edit", at: \.edit)
                }
            }
            .addMutation {
                Field("patch", at: KanbanResolver.patch) {
                    Argument("input", at: \.input)
                }
            }
            .build()
    }
}
