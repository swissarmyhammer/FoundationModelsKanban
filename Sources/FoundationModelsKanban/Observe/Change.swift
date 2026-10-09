import Foundation
import GraphQL
import Graphiti

// MARK: - Enums

/// The type of a node in a ``NodeUpdate``: the GraphQL `NodeType` enum (plan.md §4.1).
enum NodeType: String, Codable, Sendable, CaseIterable {
    /// The board.
    case board = "BOARD"

    /// A column.
    case column = "COLUMN"

    /// A task.
    case task = "TASK"

    /// A tag.
    case tag = "TAG"

    /// An actor.
    case actor = "ACTOR"

    /// A comment.
    case comment = "COMMENT"

    /// Gives the GraphQL node type of a patch node type.
    ///
    /// - Parameter type: The node type of a patch.
    init(_ type: PatchNodeType) {
        switch type {
        case .board: self = .board
        case .column: self = .column
        case .task: self = .task
        case .tag: self = .tag
        case .actor: self = .actor
        case .comment: self = .comment
        }
    }
}

/// How a transaction changed a node: the GraphQL `UpdateKind` enum (plan.md §6.7, Kind).
enum UpdateKind: String, Codable, Sendable, CaseIterable {
    /// The transaction wrote the first patch of the node.
    case created = "CREATED"

    /// The transaction changed the node in a different way.
    case updated = "UPDATED"

    /// The transaction made the node a tombstone (`delete: true`).
    case deleted = "DELETED"

    /// The transaction removed the tombstone of the node (`delete: false`).
    case restored = "RESTORED"
}

// MARK: - Field change

/// The change of one public field of a node in a transaction: the GraphQL `FieldChange` type (plan.md §4.1, §6.7).
///
/// A single value gives ``before`` and ``after``. A list gives ``added`` and ``removed``. The `body` field gives only
/// ``diff``, a unified diff from the body before the transaction to the body after it. The values are the values that
/// a query shows, not the raw patch.
struct FieldChange: Equatable, Sendable {
    /// The public field name, for example `column`, `tags`, or `ready`.
    let name: String

    /// The value before the transaction, for a single value. `nil` is the JSON `null`.
    let before: Map?

    /// The value after the transaction, for a single value. `nil` is the JSON `null`.
    let after: Map?

    /// The items that the transaction added to a list value, or `nil` for a field that is not a list.
    let added: [Map]?

    /// The items that the transaction removed from a list value, or `nil` for a field that is not a list.
    let removed: [Map]?

    /// The unified diff of the body, or `nil` for a field that is not `body`.
    let diff: String?
}

// MARK: - Node update

/// The change of one node in a transaction: the GraphQL `NodeUpdate` type (plan.md §4.1, §6.7).
struct NodeUpdate: Sendable {
    /// The local ref of the node.
    let ref: LocalRef

    /// The full URI of the node. It is set also for a deleted node.
    let id: NodeID

    /// The type of the node.
    let type: NodeType

    /// How the transaction changed the node.
    let kind: UpdateKind

    /// The changes of the public fields of the node, in the order of the fields of the node type.
    let fields: [FieldChange]

    /// The current key of the board of the node. For an update that a transaction of a different board makes
    /// (plan.md §6.7, updates across boards), it is not the first key of ``Change/boards``.
    let boardKey: String

    /// Resolves `NodeUpdate.node`: the node now, in the graph now of the board of the node: the current board or a
    /// related board (plan.md §6.6). For a `DELETED` update, the node is the tombstone with `deleted` set.
    ///
    /// - Parameters:
    ///   - context: The context of the call. Its store finds the board of the node.
    ///   - arguments: The field has no arguments.
    /// - Returns: The node, or `nil` when the graph does not have the node now.
    /// - Throws: An error of ``KanbanContext/view(ofBoardOfChange:)``.
    func node(context: KanbanContext, arguments _: NoArguments) async throws(KanbanError) -> (any NodeObject)? {
        let view = try await context.view(ofBoardOfChange: boardKey)
        return view.graph.slot(for: ref).flatMap(view.nodeObject(at:))
    }
}

// MARK: - Change

/// One transaction (one tool call): the GraphQL `Change` type (plan.md §4.1, §6.5, §6.7).
///
/// A change has one ``NodeUpdate`` for each node that the transaction changed: each node that a patch of the
/// transaction wrote, and each other node whose fields changed because of the transaction. One node has at most one
/// update. ``ChangeBuilder`` makes it from the projection before and after the transaction.
struct Change: Sendable {
    /// The transaction ULID.
    let txn: NodeID

    /// The time of the transaction.
    let at: DateTime

    /// The local ref of the actor of the transaction.
    let actorRef: LocalRef

    /// The names of the public mutations of the tool call.
    let ops: [String]

    /// The keys of the boards that the transaction changed: the key of this board first.
    let boards: [String]

    /// `true` when a later transaction that is not undone reverses this transaction (plan.md §6.5).
    let undone: Bool

    /// The transaction that this transaction reverses, only for `undo` and `redo`.
    let undoes: NodeID?

    /// The updates of the nodes: the updates of the patched nodes in the order of the first patch of each node, then
    /// the updates of the other nodes in slot order.
    let nodeUpdates: [NodeUpdate]

    /// Gives this change with different node updates. This is the one place that copies each field of the envelope.
    ///
    /// - Parameter updates: The node updates of the new change.
    /// - Returns: The change with the same envelope and these updates.
    func replacingNodeUpdates(_ updates: [NodeUpdate]) -> Change {
        Change(
            txn: txn,
            at: at,
            actorRef: actorRef,
            ops: ops,
            boards: boards,
            undone: undone,
            undoes: undoes,
            nodeUpdates: updates
        )
    }

    /// Resolves `Change.actor`: the actor of the transaction, in the graph now of the board of the transaction. The
    /// first key of ``boards`` names that board: the current board or a related board (plan.md §6.6). The ref of the
    /// actor is local to that board, also for a change that a board gets for a transaction of a board that it depends
    /// on (plan.md §6.7). A tombstoned actor resolves to the tombstone, with `deleted` set (plan.md
    /// §5.3, step 5).
    ///
    /// - Parameters:
    ///   - context: The context of the call. Its store finds the board of the transaction.
    ///   - arguments: The field has no arguments.
    /// - Returns: The actor.
    /// - Throws: An error of ``KanbanContext/view(ofBoardOfChange:)``. ``KanbanError/notFound(type:reference:)`` for
    ///   the actor when the board does not have the actor.
    func actor(context: KanbanContext, arguments _: NoArguments) async throws(KanbanError) -> ActorObject {
        let view = try await context.view(ofBoardOfChange: boards[boards.startIndex])
        guard let state = view.graph.actor(for: actorRef), let slot = view.graph.slot(for: actorRef) else {
            throw .notFound(type: .actor, reference: view.id(of: actorRef).text)
        }
        return ActorObject(view: view, slot: slot, state: state)
    }

    /// Resolves `Change.updates`: the updates whose node matches the filter (``ChangeFilter``).
    ///
    /// The filter tests each node in the graph now of the board of the updates: the current board or a related board
    /// (plan.md §6.6). The GraphQL field is nullable: an error gives `null` for the field and one item in `errors`,
    /// and the other fields keep their data.
    ///
    /// - Parameters:
    ///   - context: The context of the call. Its store finds the board of the updates.
    ///   - arguments: The filter.
    /// - Returns: The updates that the filter keeps, in the order of ``nodeUpdates``. With no filter, each update. The
    ///   value is never `nil`. The optional type makes the GraphQL field nullable.
    /// - Throws: An error of ``ChangeFilter/init(parsing:)``, of ``KanbanContext/view(ofBoardOfChange:)``, or of
    ///   ``ChangeFilter/updates(of:readingNodesOf:)``.
    func updates(context: KanbanContext, arguments: FilterArguments) async throws(KanbanError) -> [NodeUpdate]? {
        let filter = try ChangeFilter(parsing: arguments.filter)
        guard arguments.filter != nil, let first = nodeUpdates.first else {
            return nodeUpdates
        }
        let view = try await context.view(ofBoardOfChange: first.boardKey)
        return try filter.updates(of: nodeUpdates, readingNodesOf: view)
    }
}

// MARK: - Board of a change

extension KanbanContext {
    /// Gives the read view of a board that a change names by its key: the board of the transaction, or the board of
    /// a node of an update. It is the current board or a related board (plan.md §6.6).
    ///
    /// - Parameter key: The current key of the board.
    /// - Returns: The read view of the board now.
    /// - Throws: ``KanbanError/boardNotFound(reference:searchRoots:)`` when the scan finds no board for the key.
    ///   ``KanbanError/notFound(type:reference:)`` for the board when the engine did not load the board yet: the
    ///   store then records the request, and the call runs again after the load.
    fileprivate func view(ofBoardOfChange key: String) async throws(KanbanError) -> BoardView {
        guard let view = try await store.view(ofBoardNamed: key) else {
            throw .notFound(type: .board, reference: key)
        }
        return view
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the `Change`, `NodeUpdate`, and `FieldChange` types and their enums (plan.md §4.1). `Board.history` and
    /// `Subscription.changes` give these types.
    ///
    /// - Returns: This builder, for method chaining.
    func addChangeTypes() -> Self {
        add {
            Self.enumType(NodeType.self)
            Self.enumType(UpdateKind.self)
            Type(Change.self) {
                Field("txn", at: \.txn)
                Field("at", at: \.at)
                Field("actor", at: Change.actor)
                Field("ops", at: \.ops)
                Field("boards", at: \.boards)
                Field("undone", at: \.undone)
                Field("undoes", at: \.undoes)
                Field("updates", at: Change.updates) {
                    Argument("filter", at: \.filter)
                }
            }
            Type(NodeUpdate.self) {
                Field("id", at: \.id)
                Field("type", at: \.type)
                Field("kind", at: \.kind)
                Field("fields", at: \.fields)
                Field("node", at: NodeUpdate.node)
            }
            Type(FieldChange.self) {
                Field("name", at: \.name)
                Field("before", at: \.before)
                Field("after", at: \.after)
                Field("added", at: \.added)
                Field("removed", at: \.removed)
                Field("diff", at: \.diff)
            }
        }
    }

    /// Makes a GraphQL enum type with one value for each case of a Swift enum.
    ///
    /// - Parameter type: The Swift enum. The raw value of each case is the GraphQL name of the value.
    /// - Returns: The enum type.
    private static func enumType<Cases: CaseIterable & Encodable & RawRepresentable>(
        _ type: Cases.Type
    ) -> Graphiti.Enum<KanbanResolver, KanbanContext, Cases> where Cases.RawValue == String {
        Graphiti.Enum(type) {
            // The explicit `return` turns off the result builder, so the closure gives the array as it is.
            return type.allCases.map(Value.init)
        }
    }
}
