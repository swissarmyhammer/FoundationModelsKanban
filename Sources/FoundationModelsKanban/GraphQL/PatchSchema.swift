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

/// The arguments of the internal `patch` mutation.
struct PatchArguments: Codable, Sendable {
    /// The patch.
    let input: PatchInput
}

extension KanbanResolver {
    /// Resolves the internal `Mutation.patch`: applies one patch to the working graph of the call (plan.md §5.1,
    /// §5.4 step 4).
    ///
    /// The field keeps the patch, and the commit at the end of the call writes it. A patch that changes nothing is
    /// not kept.
    ///
    /// - Parameters:
    ///   - context: The context of the call. Its store holds the working copy, and its clock gives the time.
    ///   - arguments: The patch.
    /// - Returns: The patch that the engine decoded, as a `JSON` value.
    /// - Throws: An ``EventError`` when the patch breaks a rule of the log. Then the field keeps nothing.
    func patch(context: KanbanContext, arguments: PatchArguments) async throws(EventError) -> Map {
        let input = arguments.input
        let time = context.clock()
        try await context.store.runField(as: nil) { work throws(EventError) in
            try work.apply(input, at: time)
        }
        return input.map
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
                // Graphiti reads only the type of each key path, for the
                // SDL. The `Decodable` form of `PatchInput` reads the
                // argument, so each ref is checked when the engine decodes it.
                Input(PatchInput.self) {
                    InputField("node", at: \.nodeText)
                    InputField("type", at: \.type)
                    InputField("set", at: \.setMap)
                    InputField("unset", at: \.unsetList)
                    InputField("add", at: \.addMap)
                    InputField("remove", at: \.removeMap)
                    InputField("delete", at: \.delete)
                    InputField("edit", at: \.editMap)
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
