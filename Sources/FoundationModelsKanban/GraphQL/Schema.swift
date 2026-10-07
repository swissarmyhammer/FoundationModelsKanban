import Foundation
import Graphiti
import GraphQL

/// The working copy of the current board for one run of a call, which the resolvers read and change (plan.md §5.4).
///
/// The actor makes each change to the working copy one at a time, so that resolvers that run concurrently do not race.
/// A query reads one ``BoardView`` of the graph, so that all the fields of the query see the same state. A mutation
/// field changes the working copy only through ``runField(as:_:)``.
actor BoardStore {
    /// The working copy of the run.
    private(set) var work: WorkingCopy

    /// The current key of the board, for example `github.com/swissarmyhammer/FoundationModelsKanban`. Each `id` in
    /// the output starts with `kanban://` and this key (plan.md §3.2).
    let boardKey: String

    /// The session actor of the call. A mutation field that writes to the board makes sure that this actor exists
    /// there (plan.md §6).
    let sessionActor: SessionActor

    /// The local ref of the session actor when it is a live actor of the board at the start of the run, else `nil`.
    /// An `addTask` with no assignee assigns this actor (plan.md §6, "Assignees"). An actor that the call itself makes
    /// is not known before the call, so it is not assigned.
    let knownSessionActor: LocalRef?

    /// Makes a store that holds the working copy of a board.
    ///
    /// - Parameters:
    ///   - work: The working copy at the start of the run.
    ///   - boardKey: The current key of the board.
    ///   - sessionActor: The session actor of the call.
    init(working work: WorkingCopy, boardKey: String, actingAs sessionActor: SessionActor) {
        self.work = work
        self.boardKey = boardKey
        self.sessionActor = sessionActor
        let isKnown = work.graph.node(for: sessionActor.ref)?.state.fields.isDeleted == false
        knownSessionActor = isKnown ? sessionActor.ref : nil
    }

    /// The read view of the working graph now.
    var view: BoardView {
        BoardView(of: work.graph, inBoard: boardKey)
    }

    /// Runs one mutation field on the working copy. A field that throws keeps none of its patches.
    ///
    /// - Parameters:
    ///   - operation: The name of the public mutation of the field, or `nil` for the internal `patch` mutation.
    ///   - body: Makes and applies the patches of the field, and checks the graph rules.
    /// - Returns: The value of the body.
    /// - Throws: The error of the body. Then the working copy does not change.
    func runField<Value: Sendable, Failure: Error>(
        as operation: String?,
        _ body: (inout WorkingCopy) throws(Failure) -> Value
    ) throws(Failure) -> Value {
        try work.runField(as: operation, body)
    }
}

/// The context of each resolver of the kanban schemas.
struct KanbanContext: Sendable {
    /// The graph of the board that the resolvers read and change.
    let store: BoardStore

    /// The clock that gives the time of a change. A test gives a fixed clock,
    /// so that the output is deterministic (plan.md §11).
    let clock: @Sendable () -> DateTime

    /// The ranked search over the tasks of the board, for `Board.searchTasks` (plan.md §6.4).
    let search: TaskSearch
}

// MARK: - Arguments

/// The arguments of `Query.board`.
struct BoardArguments: Codable, Sendable {
    /// The board to read: the key of the board, or its full URI. No value reads the current board.
    let id: String?
}

/// The arguments of a field that finds one node by its id: `Board.task` and `Query.node`.
struct NodeArguments: Codable, Sendable {
    /// The node: a full URI or a short form (plan.md §3.2).
    let id: NodeID
}

/// The arguments of `Query.nodes`.
struct NodesArguments: Codable, Sendable {
    /// The nodes, each by a full URI or a short form (plan.md §3.2).
    let ids: [NodeID]
}

/// The arguments of `Board.tasks`: the list, the filter and the scoping arguments of plan.md §6.3, and the cursor
/// paging of plan.md §4.1.
struct TasksArguments: Codable, Sendable {
    /// The number of tasks of a page when the call does not give `first`.
    static let defaultPageSize = 10

    /// The list when the call does not give `deleted`: the live tasks.
    static let listsDeletedByDefault = false

    /// `true` to list only the tombstoned tasks (plan.md §3.3, rule 3). `false` or an explicit `null` lists the live
    /// tasks.
    let deleted: Bool?

    /// The filter, for example `#bug && @alice`, or `nil` for no filter.
    let filter: String?

    /// The column that the tasks show in: the same as the atom `%x` in the filter.
    let column: NodeID?

    /// The tag that the tasks have: the same as the atom `#x` in the filter.
    let tag: NodeID?

    /// The actor that the tasks are assigned to: the same as the atom `@x` in the filter.
    let assignee: NodeID?

    /// `true` to leave out the done tasks. No value is `true`, or `false` when the call names a column or lists the
    /// tombstoned tasks.
    let excludeDone: Bool?

    /// The maximum number of tasks of the page. A negative value gives no task. An explicit `null` gives
    /// ``defaultPageSize``.
    let first: Int?

    /// The cursor of the task before the page, or `nil` for the first page. A cursor is the `id` of a task, and a
    /// short form of the task also works.
    let after: String?

    /// `true` when the call lists the tombstoned tasks.
    var listsDeleted: Bool {
        deleted == true
    }
}

/// The arguments of `Board.searchTasks` (plan.md §6.4).
struct SearchTasksArguments: Codable, Sendable {
    /// The search text.
    let query: String

    /// The filter, for example `#bug && @alice`, or `nil` for no filter.
    let filter: String?

    /// The largest number of hits. A negative value gives no hit. An explicit `null` gives
    /// ``TasksArguments/defaultPageSize``.
    let first: Int?
}

/// The arguments of `Board.history`: the filters of the change feed, the start, and the page size (plan.md §4.1,
/// §6.7).
struct HistoryArguments: Codable, Sendable {
    /// The number of changes when the call does not give `first`.
    static let defaultPageSize = 20

    /// The value of `derived` when the call does not give it: the list keeps the `DERIVED` updates.
    static let includesDerivedByDefault = true

    /// The node types to keep, or `nil` for all types.
    let type: [NodeType]?

    /// The node to keep: a full URI or a short form, or `nil` for all nodes.
    let node: NodeID?

    /// The actor of the transactions to keep: a full URI or a short form, or `nil` for all actors.
    let actor: NodeID?

    /// The filter of the tasks to keep, for example `#bug`, or `nil` for no filter.
    let filter: String?

    /// `false` to leave out the `DERIVED` updates. An explicit `null` keeps them.
    let derived: Bool?

    /// The transaction after which the list starts, or `nil` for all transactions.
    let since: NodeID?

    /// The maximum number of changes. A negative value gives no change. An explicit `null` gives
    /// ``defaultPageSize``.
    let first: Int?
}

/// The arguments of a task list that has only a filter: `Board.nextTask`, and the `tasks` fields of `Column`,
/// `Actor`, and `Tag` (plan.md §6.3).
struct FilterArguments: Codable, Sendable {
    /// The filter, for example `#bug && @alice`, or `nil` for no filter.
    let filter: String?
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

    /// Resolves `Query.node`: one node of any type by its full URI or a short form, live or tombstoned (plan.md
    /// §3.3, rule 3).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The id of the node.
    /// - Returns: The node, or `nil` when no node of the current board has the id.
    /// - Throws: ``KanbanError/ambiguousID(reference:matches:)`` when the id is a prefix of more than one ULID. The
    ///   field is then `null`, and `errors` has the matches.
    func node(context: KanbanContext, arguments: NodeArguments) async throws(KanbanError) -> (any NodeObject)? {
        try await context.store.view.node(for: arguments.id.text)
    }

    /// Resolves `Query.nodes`: the nodes of some ids, in the order of the ids, live or tombstoned (plan.md §4.1).
    ///
    /// The list has no `null` item: an id that names no node is not in the list. Thus a call where no id names a node
    /// gives an empty list. The GraphQL field is nullable: an error gives `null` for the field and one item in
    /// `errors`, and the other fields of the call keep their data.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The ids of the nodes.
    /// - Returns: The nodes of the ids that name a node, in the order of the ids. The value is never `nil`. The
    ///   optional type makes the GraphQL field nullable.
    /// - Throws: ``KanbanError/ambiguousID(reference:matches:)`` when an id is a prefix of more than one ULID, the same
    ///   as `Query.node`.
    func nodes(context: KanbanContext, arguments: NodesArguments) async throws(KanbanError) -> [any NodeObject]? {
        let view = await context.store.view
        return try arguments.ids.map { id throws(KanbanError) in try view.node(for: id.text) }.compactMap(\.self)
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

    /// The values of the public fields that a `Change` compares before and after a transaction (plan.md §6.7).
    var trackedFields: TrackedFields { get }
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
protocol LabelObject: TaskHolderObject {
    /// The Swift type of the color. Its optionality sets the nullability of the GraphQL `color` field.
    associatedtype Color: Sendable

    /// The name of the node.
    var name: String { get }

    /// The color of the node.
    var color: Color { get }
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
            .addChangeTypes()
            .addQuery {
                Field("board", at: KanbanResolver.board) {
                    Argument("id", at: \.id)
                }
                Field("node", at: KanbanResolver.node) {
                    Argument("id", at: \.id)
                }
                Field("nodes", at: KanbanResolver.nodes) {
                    Argument("ids", at: \.ids)
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
                    Argument("filter", at: \.filter)
                    Argument("column", at: \.column)
                    Argument("tag", at: \.tag)
                    Argument("assignee", at: \.assignee)
                    Argument("excludeDone", at: \.excludeDone)
                    Argument("deleted", at: \.deleted).defaultValue(TasksArguments.listsDeletedByDefault)
                    Argument("first", at: \.first).defaultValue(TasksArguments.defaultPageSize)
                    Argument("after", at: \.after)
                }
                Field("nextTask", at: BoardObject.nextTask) {
                    Argument("filter", at: \.filter)
                }
                Field("searchTasks", at: BoardObject.searchTasks) {
                    Argument("query", at: \.query)
                    Argument("filter", at: \.filter)
                    Argument("first", at: \.first).defaultValue(TasksArguments.defaultPageSize)
                }
                Field("summary", at: \.summary)
                Field("history", at: BoardObject.history) {
                    Argument("type", at: \.type)
                    Argument("node", at: \.node)
                    Argument("actor", at: \.actor)
                    Argument("filter", at: \.filter)
                    Argument("derived", at: \.derived).defaultValue(HistoryArguments.includesDerivedByDefault)
                    Argument("since", at: \.since)
                    Argument("first", at: \.first).defaultValue(HistoryArguments.defaultPageSize)
                }
            }
            Self.nodeType(ColumnObject.self, as: GraphQLTypeName.column) {
                Field("name", at: \.name)
                Field("order", at: \.order)
                Self.taskListField()
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

    /// Adds the `Task`, `Comment`, `Progress`, `TaskConnection`, `TaskEdge`, `PageInfo`, `TaskHit`, and
    /// `SearchSignals` types.
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
            Type(TaskHit.self) {
                Field("task", at: \.task)
                Field("score", at: \.score)
                Field("signals", at: \.signals)
            }
            Type(SearchSignals.self) {
                Field("bm25", at: \.bm25)
                Field("trigram", at: \.trigram)
                Field("cosine", at: \.cosine)
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
        taskListField()
    }

    /// Gives the `tasks(filter:)` field of a column, an actor, or a tag.
    ///
    /// - Returns: The field. Its type is nullable, so that a filter that does not parse gives `null` for the field
    ///   only, and the other fields keep their data.
    private static func taskListField<Object: TaskHolderObject>() -> FieldComponent<Object, KanbanContext> {
        Field("tasks", at: Object.tasks) {
            Argument("filter", at: \.filter)
        }
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

/// The aliases of the fields, the arguments, and the `input` fields of the schemas: the other names that the agent can
/// write for each name (plan.md §4.5, step 5).
///
/// The schema has one name for each field, and introspection shows only that name. The forgiving name rewrite reads
/// this table, so that the Swift code stays the one source of the names (plan.md §1). A key is a GraphQL name of the
/// schemas above, and its aliases apply at each position where the schema has the name.
enum GraphQLFieldAliases {
    /// The aliases of each name. The old names `description` (Board, Tag, Task) and `text` (Comment) are aliases of
    /// `body` (plan.md §12, item 19).
    static let byName: [String: [String]] = [
        "body": ["description", "desc", "text", "content"],
        "column": ["status"],
        "assignees": ["assignee"],
        "id": ["task_id"],
        "tag": ["label"],
        "tags": ["labels"],
    ]
}

extension CanonicalName {
    /// Makes the canonical name of a field, an argument, or an `input` field, with its aliases from
    /// ``GraphQLFieldAliases``.
    ///
    /// - Parameter name: The GraphQL name, for example `body`.
    init(field name: String) {
        self.init(name: name, aliases: GraphQLFieldAliases.byName[name] ?? [])
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
            .addBoardMutations()
            .addColumnActorMutations()
            .addTaskMutations()
            .addTaskOperationMutations()
            .addCommentMutations()
            .addTagMutations()
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
    /// throw (plan.md §4.4): a document that does not parse gives a response
    /// with one error and no `data`. With no formatting, the keys of `data`
    /// are in the order of the selection. A `/` is not escaped, so a ref such
    /// as `tag/bug` stays easy to read.
    ///
    /// The name rewrite of plan.md §4.5 changes the document before
    /// validation, and the response has each change in
    /// `extensions.rewrites`. A name that matches two or more names gives an
    /// error, and the document does not run.
    ///
    /// - Parameters:
    ///   - document: The GraphQL document.
    ///   - variables: The values of the variables of the document.
    ///   - operationName: The operation of the document to run, or `nil` when
    ///     the document has one operation.
    ///   - formatting: The formatting of the JSON text, for example
    ///     `.sortedKeys`. Slashes are never escaped.
    ///   - context: The context of each resolver.
    /// - Returns: The response as JSON text.
    /// - Throws: An error that is not a GraphQL error, for example an error
    ///   from the JSON encoder.
    func respond(
        to document: String,
        variables: [String: Map] = [:],
        operationName: String? = nil,
        formattedWith formatting: GraphQLJSONEncoder.OutputFormatting = [],
        context: ContextType
    ) async throws -> String {
        let response: RewriteResponse
        do {
            let rewritten = try DocumentRewriter(for: schema.schema).rewrittenDocument(from: document)
            let result = try await result(
                of: rewritten,
                variables: variables,
                operationName: operationName,
                context: context
            )
            response = RewriteResponse(result: result, rewrites: rewritten.rewrites)
        } catch let error as GraphQLError {
            response = RewriteResponse(result: GraphQLResult(errors: [error]), rewrites: [])
        }
        let encoder = GraphQLJSONEncoder()
        encoder.outputFormatting = formatting.union(.withoutEscapingSlashes)
        return try String(decoding: encoder.encode(response), as: UTF8.self)
    }

    /// Runs a rewritten document, and gives the result in the form of the
    /// document that the caller wrote.
    ///
    /// - Parameters:
    ///   - rewritten: The document after the name rewrite.
    ///   - variables: The values of the variables of the document.
    ///   - operationName: The operation of the document to run, or `nil`.
    ///   - context: The context of each resolver.
    /// - Returns: The result, or the tie errors and no `data` when a name of
    ///   the document has a tie.
    /// - Throws: A `GraphQLError` when the rewritten text does not parse, or
    ///   an error that is not a GraphQL error.
    private func result(
        of rewritten: RewrittenDocument,
        variables: [String: Map],
        operationName: String?,
        context: ContextType
    ) async throws -> GraphQLResult {
        guard rewritten.ties.isEmpty else {
            return GraphQLResult(errors: rewritten.ties)
        }
        let result = try await execute(
            request: rewritten.text,
            context: context,
            variables: variables,
            operationName: operationName
        )
        return rewritten.callerResult(from: result)
    }
}

/// A GraphQL response, with the changes of the name rewrite in
/// `extensions.rewrites` (plan.md §4.5).
///
/// `GraphQLResult` encodes only `data` and `errors`, so this type encodes the
/// same two keys in the same way, and adds `extensions` when the rewrite
/// changed a name.
private struct RewriteResponse: Encodable {
    /// The keys of the response object.
    private enum CodingKeys: String, CodingKey {
        /// The result of the execution.
        case data

        /// The errors of the call.
        case errors

        /// The extensions of the response.
        case extensions
    }

    /// The `extensions` object of the response.
    private struct Extensions: Encodable {
        /// The changes of the name rewrite.
        let rewrites: [NameRewrite]
    }

    /// The result of the document.
    let result: GraphQLResult

    /// The changes of the name rewrite.
    let rewrites: [NameRewrite]

    /// Writes `data` when the result has it, `errors` when there is an error,
    /// and `extensions` when the rewrite changed a name.
    ///
    /// - Parameter encoder: The encoder.
    /// - Throws: An error from the encoder.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(result.data, forKey: .data)
        if !result.errors.isEmpty {
            try container.encode(result.errors, forKey: .errors)
        }
        if !rewrites.isEmpty {
            try container.encode(Extensions(rewrites: rewrites), forKey: .extensions)
        }
    }
}
