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

/// Why a node is in a ``Change``: the GraphQL `UpdateSource` enum (plan.md §4.1, §6.7).
enum UpdateSource: String, Codable, Sendable, CaseIterable {
    /// A patch of the transaction changed a stored property of the node.
    case patch = "PATCH"

    /// No patch changed the node, but a derived field of the node changed.
    case derived = "DERIVED"
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

    /// `PATCH` when a patch changed the node, `DERIVED` when only a derived field changed.
    let source: UpdateSource

    /// The changes of the public fields of the node, in the order of the fields of the node type.
    let fields: [FieldChange]

    /// Resolves `NodeUpdate.node`: the node now, in the graph of the call. For a `DELETED` update, the node is the
    /// tombstone with `deleted` set.
    ///
    /// - Parameters:
    ///   - context: The context of the call. Its store gives the graph now.
    ///   - arguments: The field has no arguments.
    /// - Returns: The node, or `nil` when the graph does not have the node now.
    func node(context: KanbanContext, arguments _: NoArguments) async -> (any NodeObject)? {
        let view = await context.store.view
        return view.graph.slot(for: ref).flatMap(view.nodeObject(at:))
    }
}

// MARK: - Change

/// The arguments of `Change.updates`: the filters of the updates (plan.md §4.1).
struct UpdatesArguments: Codable, Sendable {
    /// The node types to keep, or `nil` for all types.
    let type: [NodeType]?

    /// The node to keep: a full URI or a short form, or `nil` for all nodes.
    let node: NodeID?
}

/// One transaction (one tool call): the GraphQL `Change` type (plan.md §4.1, §6.5, §6.7).
///
/// A change has one ``NodeUpdate`` for each node that the transaction changed, and one `DERIVED` update for each node
/// whose derived fields changed. ``ChangeBuilder`` makes it from the projection before and after the transaction.
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

    /// The updates of the nodes: the `PATCH` updates in the order of the first patch of each node, then the `DERIVED`
    /// updates in slot order.
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

    /// Resolves `Change.actor`: the actor of the transaction, in the graph of the call. A tombstoned actor resolves to
    /// the tombstone, with `deleted` set (plan.md §5.3, step 5).
    ///
    /// - Parameters:
    ///   - context: The context of the call. Its store gives the graph now.
    ///   - arguments: The field has no arguments.
    /// - Returns: The actor.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when the graph does not have the actor.
    func actor(context: KanbanContext, arguments _: NoArguments) async throws(KanbanError) -> ActorObject {
        let view = await context.store.view
        guard let state = view.graph.actor(for: actorRef), let slot = view.graph.slot(for: actorRef) else {
            throw .notFound(type: .actor, reference: view.id(of: actorRef).text)
        }
        return ActorObject(view: view, slot: slot, state: state)
    }

    /// Resolves `Change.updates`: the updates that match the filters.
    ///
    /// The GraphQL field is nullable: an error gives `null` for the field and one item in `errors`, and the other
    /// fields keep their data.
    ///
    /// - Parameters:
    ///   - context: The context of the call. Its store resolves the `node` filter.
    ///   - arguments: The filters.
    /// - Returns: The updates, in the order of ``nodeUpdates``. The value is never `nil`. The optional type makes the
    ///   GraphQL field nullable.
    /// - Throws: ``KanbanError/ambiguousID(reference:matches:)`` when the `node` filter is a prefix of more than one
    ///   ULID.
    func updates(context: KanbanContext, arguments: UpdatesArguments) async throws(KanbanError) -> [NodeUpdate]? {
        let view = await context.store.view
        let node = try arguments.node.map { id throws(KanbanError) in try view.resolver.anyLocalRef(for: id.text) }
        return nodeUpdates.filter { update in
            (arguments.type?.contains(update.type) ?? true) && (node.map { ref in ref == update.ref } ?? true)
        }
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
            Self.enumType(UpdateSource.self)
            Type(Change.self) {
                Field("txn", at: \.txn)
                Field("at", at: \.at)
                Field("actor", at: Change.actor)
                Field("ops", at: \.ops)
                Field("boards", at: \.boards)
                Field("undone", at: \.undone)
                Field("undoes", at: \.undoes)
                Field("updates", at: Change.updates) {
                    Argument("type", at: \.type)
                    Argument("node", at: \.node)
                }
            }
            Type(NodeUpdate.self) {
                Field("id", at: \.id)
                Field("type", at: \.type)
                Field("kind", at: \.kind)
                Field("source", at: \.source)
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
