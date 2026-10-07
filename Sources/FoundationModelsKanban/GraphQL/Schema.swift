import Foundation
import Graphiti
import GraphQL

/// The board, as the GraphQL `Board` type.
///
/// This is the small board of the GraphQL engine step (plan.md §10, step 2).
/// The full `Node` types of plan.md §4.1 replace it in a later step.
struct Board: Codable, Sendable {
    /// The name of the board.
    var name: String

    /// The Markdown body of the board. The value is `""` when it is not set.
    var body: String

    /// The time of the first change to the board.
    let created: DateTime

    /// The time of the last change to the board.
    var updated: DateTime
}

/// The `input` object of the `updateBoard` mutation. A field that is not set
/// does not change.
struct UpdateBoardInput: Codable, Sendable {
    /// The new name of the board.
    let name: String?

    /// The new Markdown body of the board.
    let body: String?
}

/// The arguments of the `updateBoard` mutation. The `input` argument is
/// optional, because `UpdateBoardInput` has no required field (plan.md §4.2).
struct UpdateBoardArguments: Codable, Sendable {
    /// The changes to the board.
    let input: UpdateBoardInput?
}

/// The in-memory board that the resolvers read and change.
///
/// The actor makes each change to the board one at a time, so that resolvers
/// that run concurrently do not race.
actor BoardStore {
    /// The board now.
    private(set) var board: Board

    /// Makes a store that holds a board.
    ///
    /// - Parameter board: The first state of the board.
    init(board: Board) {
        self.board = board
    }

    /// Changes the board.
    ///
    /// - Parameters:
    ///   - input: The changes. A field that is not set does not change.
    ///   - time: The time of the change. It becomes the `updated` value.
    /// - Returns: The board after the change.
    func update(with input: UpdateBoardInput?, at time: DateTime) -> Board {
        board.name = input?.name ?? board.name
        board.body = input?.body ?? board.body
        board.updated = time
        return board
    }
}

/// The context of each resolver of the kanban schemas.
struct KanbanContext: Sendable {
    /// The board that the resolvers read and change.
    let store: BoardStore

    /// The clock that gives the time of a change. A test gives a fixed clock,
    /// so that the output is deterministic (plan.md §11).
    let clock: @Sendable () -> DateTime
}

/// The root resolver of the kanban schemas.
///
/// Each resolver is `async`. Graphiti calls it with the context of the call.
struct KanbanResolver: Sendable {
    /// Resolves `Query.board`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The field has no arguments.
    /// - Returns: The board now.
    func board(context: KanbanContext, arguments _: NoArguments) async -> Board {
        await context.store.board
    }

    /// Resolves `Mutation.updateBoard`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The changes to the board.
    /// - Returns: The board after the change.
    func updateBoard(context: KanbanContext, arguments: UpdateBoardArguments) async -> Board {
        await context.store.update(with: arguments.input, at: context.clock())
    }
}

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Makes a builder with the parts that the public schema and the internal
    /// `patch` schema share: the scalars, the types, and the query fields.
    ///
    /// GraphQL needs a `Query` type in each schema. Thus the internal schema
    /// gets the same query fields as the public schema.
    ///
    /// - Returns: A builder that has no mutation field.
    static func makeKanbanBuilder() -> SchemaBuilder {
        SchemaBuilder(KanbanResolver.self, KanbanContext.self)
            .addKanbanScalars()
            .add {
                Type(Board.self) {
                    Field("name", at: \.name)
                    Field("body", at: \.body)
                    Field("created", at: \.created)
                    Field("updated", at: \.updated)
                }
            }
            .addQuery {
                Field("board", at: KanbanResolver.board)
            }
    }
}

/// The public GraphQL schema: the schema that the agent sees.
///
/// The schema does not have the internal `patch` mutation (plan.md §12,
/// item 9). ``PatchSchema`` has it.
struct PublicSchema: API {
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
                Input(UpdateBoardInput.self) {
                    InputField("name", at: \.name)
                    InputField("body", at: \.body)
                }
            }
            .addMutation {
                Field("updateBoard", at: KanbanResolver.updateBoard) {
                    Argument("input", at: \.input)
                }
            }
            .build()
    }
}

extension API {
    /// The schema in the GraphQL schema definition language (SDL).
    var sdl: String {
        printSchema(schema: schema.schema)
    }

    /// Runs one GraphQL document, and returns the response as JSON text.
    ///
    /// The response follows the GraphQL specification: `{"data": …}`, and
    /// `"errors"` when the document has an error. A GraphQL error does not
    /// throw (plan.md §4.4). The keys of `data` are in the order of the
    /// selection. A `/` is not escaped, so a ref such as `tag/bug` stays
    /// easy to read.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - variables: The values of the variables of the document.
    ///   - context: The context of each resolver.
    /// - Returns: The response as JSON text.
    /// - Throws: An error that is not a GraphQL error, for example an error
    ///   from the JSON encoder.
    func respond(
        to document: String,
        variables: [String: Map] = [:],
        context: ContextType
    ) async throws -> String {
        let result = try await execute(request: document, context: context, variables: variables)
        let encoder = GraphQLJSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return try String(decoding: encoder.encode(result), as: UTF8.self)
    }
}
