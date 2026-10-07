import Foundation
import Graphiti
import GraphQL

/// The in-memory graph of the current board that the resolvers read and change.
///
/// The actor makes each change to the graph one at a time, so that resolvers that run concurrently do not race. A
/// query reads one ``BoardView`` of the graph, so that all the fields of the query see the same state.
actor BoardStore {
    /// The graph of the board now.
    private(set) var graph: Graph

    /// The current key of the board, for example `github.com/swissarmyhammer/FoundationModelsKanban`. Each `id` in
    /// the output starts with `kanban://` and this key (plan.md §3.2).
    let boardKey: String

    /// Makes a store that holds the graph of a board.
    ///
    /// - Parameters:
    ///   - graph: The first state of the graph.
    ///   - boardKey: The current key of the board.
    init(graph: Graph, boardKey: String) {
        self.graph = graph
        self.boardKey = boardKey
    }

    /// The read view of the graph now.
    var view: BoardView {
        BoardView(of: graph, inBoard: boardKey)
    }

    /// Changes the board node.
    ///
    /// This step has no event log, so the change goes into the graph only. The commit path writes the patches in a
    /// later step (plan.md §5.4).
    ///
    /// - Parameters:
    ///   - input: The changes. A field that is not set does not change.
    ///   - time: The time of the change. It becomes the `updated` value.
    /// - Returns: The read view of the graph after the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the graph has no board node.
    func update(with input: UpdateBoardInput?, at time: DateTime) throws(KanbanError) -> BoardView {
        guard var board = graph.boardNode else {
            throw .notFound(type: .board, reference: boardKey)
        }
        board.name = input?.name ?? board.name
        board.fields.body = input?.body ?? board.fields.body
        board.fields.updated = time
        graph.update(with: .board(board))
        return view
    }
}

/// The context of each resolver of the kanban schemas.
struct KanbanContext: Sendable {
    /// The graph of the board that the resolvers read and change.
    let store: BoardStore

    /// The clock that gives the time of a change. A test gives a fixed clock,
    /// so that the output is deterministic (plan.md §11).
    let clock: @Sendable () -> DateTime
}

// MARK: - Arguments

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

/// The arguments of `Query.board`.
struct BoardArguments: Codable, Sendable {
    /// The board to read: the key of the board, or its full URI. No value reads the current board.
    let id: String?
}

/// The arguments of `Board.task`.
struct TaskArguments: Codable, Sendable {
    /// The task: a full URI or a short form (plan.md §3.2).
    let id: NodeID
}

/// The arguments of `Board.tasks`: the cursor paging of plan.md §4.1.
struct TasksArguments: Codable, Sendable {
    /// The number of tasks of a page when the call does not give `first`.
    static let defaultPageSize = 10

    /// The maximum number of tasks of the page. A negative value gives no task. An explicit `null` gives
    /// ``defaultPageSize``.
    let first: Int?

    /// The cursor of the task before the page, or `nil` for the first page. A cursor is the `id` of a task, and a
    /// short form of the task also works.
    let after: String?
}

// MARK: - Root resolver

/// The root resolver of the kanban schemas.
///
/// Each resolver is `async`. Graphiti calls it with the context of the call.
struct KanbanResolver: Sendable {
    /// Resolves `Query.board`. This step reads the current board only. The related boards come with the cross-repo
    /// task.
    ///
    /// The GraphQL field is nullable (plan.md §4.1): an error gives `null` for the field and one item in `errors`,
    /// and the other fields of the call keep their data.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The board to read. No `id` reads the current board.
    /// - Returns: The board. The value is never `nil`. The optional type makes the GraphQL field nullable.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the `id` does not name the current board, or when
    ///   the graph has no board node.
    func board(context: KanbanContext, arguments: BoardArguments) async throws(KanbanError) -> BoardObject? {
        let view = await context.store.view
        if let reference = arguments.id {
            _ = try view.resolver.storedRef(for: reference, ofType: .board)
        }
        return try BoardObject(in: view)
    }

    /// Resolves `Mutation.updateBoard`.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The changes to the board.
    /// - Returns: The board after the change.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the graph has no board node.
    func updateBoard(
        context: KanbanContext,
        arguments: UpdateBoardArguments
    ) async throws(KanbanError) -> BoardObject {
        try await BoardObject(in: context.store.update(with: arguments.input, at: context.clock()))
    }
}

// MARK: - Node types

/// A node of the graph as a GraphQL object: the `Node` interface (plan.md §4.1). Each node is a document: properties
/// plus one Markdown body.
protocol NodeObject: Sendable {
    /// The full URI of the node.
    var id: NodeID { get }

    /// The Markdown body of the node. It is `""` when no patch set it.
    var body: String { get }

    /// The time of the first patch of the node.
    var created: DateTime { get }

    /// The time of the last patch of the node.
    var updated: DateTime { get }

    /// The time of the delete, only on a tombstone (plan.md §3.3).
    var deleted: DateTime? { get }
}

extension NodeObject {
    /// The object as a value of the `Node` interface type.
    ///
    /// A key path to this property lets one list of field declarations serve the `Node` interface and each object
    /// type that implements it.
    var nodeInterface: any NodeObject {
        self
    }
}

/// A node that marks tasks, with a name and a color: an actor or a tag.
protocol LabelObject: NodeObject {
    /// The Swift type of the color. Its optionality sets the nullability of the GraphQL `color` field.
    associatedtype Color: Sendable

    /// The name of the node.
    var name: String { get }

    /// The color of the node.
    var color: Color { get }

    /// The live tasks that the node marks, in board order.
    var tasks: [TaskObject] { get }
}

/// The board, as the GraphQL `Board` type: the root of the tree (plan.md §3.1).
struct BoardObject: GraphNodeObject {
    /// The read view of the graph.
    let view: BoardView

    /// The state of the board node.
    let state: BoardNode
}

/// A column, as the GraphQL `Column` type.
struct ColumnObject: SlotNodeObject {
    /// The read view of the graph.
    let view: BoardView

    /// The slot of the column in the graph.
    let slot: Int

    /// The state of the column node.
    let state: ColumnNode
}

/// An actor, as the GraphQL `Actor` type.
struct ActorObject: SlotNodeObject, LabelObject {
    /// The read view of the graph.
    let view: BoardView

    /// The slot of the actor in the graph.
    let slot: Int

    /// The state of the actor node.
    let state: ActorNode
}

/// A tag, as the GraphQL `Tag` type.
struct TagObject: SlotNodeObject, LabelObject {
    /// The read view of the graph.
    let view: BoardView

    /// The slot of the tag in the graph.
    let slot: Int

    /// The state of the tag node.
    let state: TagNode
}

/// A task, as the GraphQL `Task` type.
struct TaskObject: SlotNodeObject {
    /// The read view of the graph.
    let view: BoardView

    /// The slot of the task in the graph.
    let slot: Int

    /// The state of the task node.
    let state: TaskNode
}

/// A comment, as the GraphQL `Comment` type.
struct CommentObject: SlotNodeObject {
    /// The read view of the graph.
    let view: BoardView

    /// The slot of the comment in the graph.
    let slot: Int

    /// The state of the comment node.
    let state: CommentNode
}

/// One page of tasks, as the GraphQL `TaskConnection` type: the cursor paging of plan.md §4.1.
struct TaskConnection: Sendable {
    /// The tasks of the page, each with its cursor.
    let edges: [TaskEdge]

    /// The position of the page in the full list.
    let pageInfo: PageInfo

    /// The number of tasks in the full list.
    let totalCount: Int
}

/// One task of a page, as the GraphQL `TaskEdge` type.
struct TaskEdge: Sendable {
    /// The task.
    let node: TaskObject

    /// The cursor of the task: its `id`.
    let cursor: String
}

// MARK: - Schema

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
            .addNodeInterface()
            .addBoardTypes()
            .addTaskTypes()
            .addQuery {
                Field("board", at: KanbanResolver.board) {
                    Argument("id", at: \.id)
                }
            }
    }

    /// Adds the `Node` interface.
    ///
    /// - Returns: This builder, for method chaining.
    private func addNodeInterface() -> Self {
        add {
            Interface(NodeObject.self, as: GraphQLTypeName.node) {
                // The explicit `return` turns off the result builder, so the closure gives the array as it is.
                return Self.nodeFields(of: \.nodeInterface)
            }
        }
    }

    /// Adds the `Board`, `Column`, `Actor`, `Tag`, and `BoardSummary` types.
    ///
    /// - Returns: This builder, for method chaining.
    private func addBoardTypes() -> Self {
        add {
            Self.nodeType(BoardObject.self, as: GraphQLTypeName.board) {
                Field("key", at: \.key)
                Field("name", at: \.name)
                Field("columns", at: \.columns)
                Field("actors", at: \.actors)
                Field("tags", at: \.tags)
                Field("task", at: BoardObject.task) {
                    Argument("id", at: \.id)
                }
                Field("tasks", at: BoardObject.tasks) {
                    Argument("first", at: \.first).defaultValue(TasksArguments.defaultPageSize)
                    Argument("after", at: \.after)
                }
                Field("summary", at: \.summary)
            }
            Self.nodeType(ColumnObject.self, as: GraphQLTypeName.column) {
                Field("name", at: \.name)
                Field("order", at: \.order)
                Field("tasks", at: \.tasks)
            }
            Self.nodeType(ActorObject.self, as: GraphQLTypeName.actor, fields: Self.labelFields)
            Self.nodeType(TagObject.self, as: GraphQLTypeName.tag, fields: Self.labelFields)
            Type(BoardSummary.self) {
                Field("total", at: \.total)
                Field("ready", at: \.ready)
                Field("blocked", at: \.blocked)
                Field("done", at: \.done)
                Field("percent", at: \.percent)
            }
        }
    }

    /// Adds the `Task`, `Comment`, `Progress`, `TaskConnection`, `TaskEdge`, and `PageInfo` types.
    ///
    /// - Returns: This builder, for method chaining.
    private func addTaskTypes() -> Self {
        add {
            Self.nodeType(TaskObject.self, as: GraphQLTypeName.task) {
                Field("shortId", at: \.shortID)
                Field("title", at: \.title)
                Field("column", at: TaskObject.column)
                Field("ordinal", at: \.ordinal)
                Field("assignees", at: \.assignees)
                Field("tags", at: \.tags)
                Field("dependsOn", at: \.dependsOn)
                Field("blockedBy", at: \.blockedBy)
                Field("blocks", at: \.blocks)
                Field("ready", at: \.ready)
                Field("virtualTags", at: \.virtualTags)
                Field("progress", at: \.progress)
                Field("comments", at: \.comments)
                Field("started", at: \.started)
                Field("completed", at: \.completed)
            }
            Self.nodeType(CommentObject.self, as: GraphQLTypeName.comment) {
                Field("shortId", at: \.shortID)
                Field("task", at: CommentObject.task)
                Field("author", at: CommentObject.author)
            }
            Type(TaskProgress.self, as: GraphQLTypeName.progress) {
                Field("total", at: \.total)
                Field("completed", at: \.completed)
                Field("fraction", at: \.fraction)
            }
            Type(TaskConnection.self) {
                Field("edges", at: \.edges)
                Field("pageInfo", at: \.pageInfo)
                Field("totalCount", at: \.totalCount)
            }
            Type(TaskEdge.self) {
                Field("node", at: \.node)
                Field("cursor", at: \.cursor)
            }
            Type(PageInfo.self) {
                Field("hasPreviousPage", at: \.hasPreviousPage)
                Field("hasNextPage", at: \.hasNextPage)
                Field("startCursor", at: \.startCursor)
                Field("endCursor", at: \.endCursor)
            }
        }
    }

    /// Makes an object type that implements the `Node` interface.
    ///
    /// - Parameters:
    ///   - type: The Swift type of the object.
    ///   - name: The GraphQL name of the type.
    ///   - fields: The fields of the type, without the fields of the `Node` interface.
    /// - Returns: The type, with the fields of the `Node` interface first.
    private static func nodeType<Object: NodeObject>(
        _ type: Object.Type,
        as name: String,
        @FieldComponentBuilder<Object, KanbanContext> fields: () -> [FieldComponent<Object, KanbanContext>]
    ) -> Graphiti.`Type`<KanbanResolver, KanbanContext, Object> {
        Graphiti.`Type`(
            resolver: KanbanResolver.self,
            context: KanbanContext.self,
            type,
            as: name,
            interfaces: [NodeObject.self],
            fields: nodeFields(of: \.nodeInterface) + fields()
        )
    }

    /// Gives the fields of the `Node` interface, for the interface and for each object type that implements it.
    ///
    /// - Parameter node: The key path from the object to its value as the `Node` interface type. The interface
    ///   and the object types have different Swift types, so each field reads through this key path.
    /// - Returns: The fields `id`, `body`, `created`, `updated`, and `deleted`.
    @FieldComponentBuilder<Object, KanbanContext>
    private static func nodeFields<Object: Sendable>(
        of node: KeyPath<Object, any NodeObject>
    ) -> [FieldComponent<Object, KanbanContext>] {
        Field("id", at: node.appending(path: \.id))
        Field("body", at: node.appending(path: \.body))
        Field("created", at: node.appending(path: \.created))
        Field("updated", at: node.appending(path: \.updated))
        Field("deleted", at: node.appending(path: \.deleted))
    }

    /// Gives the fields of an actor or a tag, after the fields of the `Node` interface.
    ///
    /// - Returns: The fields `name`, `color`, and `tasks`.
    @FieldComponentBuilder<Object, KanbanContext>
    private static func labelFields<Object: LabelObject>() -> [FieldComponent<Object, KanbanContext>] {
        Field("name", at: \.name)
        Field("color", at: \.color)
        Field("tasks", at: \.tasks)
    }
}

/// The GraphQL names of the types whose Swift names are different (plan.md §4.1).
enum GraphQLTypeName {
    /// The name of the interface of all node types.
    static let node = "Node"

    /// The name of the board type.
    static let board = "Board"

    /// The name of the column type.
    static let column = "Column"

    /// The name of the actor type.
    static let actor = "Actor"

    /// The name of the tag type.
    static let tag = "Tag"

    /// The name of the task type.
    static let task = "Task"

    /// The name of the comment type.
    static let comment = "Comment"

    /// The name of the checklist progress type of a task.
    static let progress = "Progress"
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
