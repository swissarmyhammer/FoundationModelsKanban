import Foundation
import FoundationModelsExtras
import GraphQL
import Graphiti

// MARK: - Enums

/// A Swift enum that the public schema shows as a GraphQL enum type, with the descriptions that introspection gives
/// (EXTRAS-9 rule 11). The raw value of each case is the GraphQL name of its value.
protocol DescribedGraphQLEnum: CaseIterable, Encodable, RawRepresentable, Sendable where RawValue == String {
    /// The description of the enum type.
    static var typeDescription: String { get }

    /// The description of the GraphQL value of this case.
    var valueDescription: String { get }
}

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

/// How a node changed from before to after the batch of a change: the GraphQL `UpdateKind` enum (plan.md §6.7, Kind).
/// ``ChangeBuilder`` sets it.
enum UpdateKind: String, Codable, Sendable, CaseIterable {
    /// The graph before the batch does not have the node.
    case created = "CREATED"

    /// The node is in the graph before the batch, and the batch did not delete it or restore it.
    case updated = "UPDATED"

    /// The node was live before the batch and is a tombstone after it.
    case deleted = "DELETED"

    /// The node was a tombstone before the batch and is live after it.
    case restored = "RESTORED"
}

extension NodeType: DescribedGraphQLEnum {
    /// The description of the `NodeType` enum.
    static let typeDescription = "The type of a node."

    /// The description of the value of this case.
    var valueDescription: String {
        switch self {
        case .board: "The board."
        case .column: "A column of the board."
        case .task: "A task."
        case .tag: "A tag."
        case .actor: "An actor: a person or an agent that works on tasks."
        case .comment: "A comment on a task."
        }
    }
}

extension UpdateKind: DescribedGraphQLEnum {
    /// The description of the `UpdateKind` enum.
    static let typeDescription = "How a node changed."

    /// The description of the value of this case.
    var valueDescription: String {
        switch self {
        case .created: "The node is new."
        case .updated: "Each other update: the node is not new, deleted, or restored."
        case .deleted: "The node was deleted: it is a tombstone now."
        case .restored: "The node was undeleted: it is live again."
        }
    }
}

// MARK: - Field change

/// The change of one public field of a node from before to after the batch of a change (``ChangeBuilder``): the
/// GraphQL `FieldChange` type (plan.md §4.1, §6.7).
///
/// A single value gives ``before`` and ``after``. A list gives ``added`` and ``removed``. The `body` field gives only
/// ``diff``, a unified diff from the body before the batch to the body after it. The values are the values that a
/// query shows, not the raw patch.
struct FieldChange: Equatable, Sendable {
    /// The public field name, for example `column`, `tags`, or `ready`.
    let name: String

    /// The value before the batch, for a single value. `nil` is the JSON `null`.
    let before: Map?

    /// The value after the batch, for a single value. `nil` is the JSON `null`.
    let after: Map?

    /// The items that the batch added to a list value, or `nil` for a field that is not a list.
    let added: [Map]?

    /// The items that the batch removed from a list value, or `nil` for a field that is not a list.
    let removed: [Map]?

    /// The unified diff of the body, or `nil` for a field that is not `body`.
    let diff: String?
}

// MARK: - Node update

/// The change of one node from before to after the batch of a change (``ChangeBuilder``): the GraphQL `NodeUpdate`
/// type (plan.md §4.1, §6.7).
struct NodeUpdate: Sendable {
    /// The local ref of the node.
    let ref: LocalRef

    /// The full URI of the node. It is set also for a deleted node.
    let id: NodeID

    /// The type of the node.
    let type: NodeType

    /// How the node changed.
    let kind: UpdateKind

    /// The changes of the public fields of the node, in the order of the fields of the node type.
    let fields: [FieldChange]

    /// The current key of the board of the node. For an update that a transaction of a different board makes
    /// (plan.md §6.7, updates across boards), it is not the first key of ``Change/boards``.
    let boardKey: String

    /// Resolves `NodeUpdate.node`: the node now, in the graph now of the board of the node: the current board or a
    /// related board (plan.md §6.6). For a `DELETED` update, the node is the tombstone with `deleted` set.
    ///
    /// - Parameter context: The context of the call. Its store finds the board of the node.
    /// - Returns: The node, or `nil` when the graph does not have the node now.
    /// - Throws: An error of ``KanbanContext/view(ofBoardOfChange:)``.
    func node(context: KanbanContext, arguments _: NoArguments) async throws(KanbanError) -> (any NodeObject)? {
        let view = try await context.view(ofBoardOfChange: boardKey)
        return view.graph.slot(for: ref).flatMap(view.nodeObject(at:))
    }
}

// MARK: - Change

/// One transaction: the GraphQL `Change` type (plan.md §4.1, §6.5, §6.7).
///
/// ``ChangeBuilder`` makes it from the projection before and after the batch of the transaction. ``ChangeBuilder``
/// and ``ChangeRound`` tell which ``NodeUpdate`` values each change of a batch has: an update can be in the change
/// of a transaction that did not write its node. `Board.history` and `Subscription.changes` give changes with the
/// updates of one board. `undo` and `redo` give one change with the updates of each board that they changed, the
/// updates of the first board first (``BoardStore/reverse(_:with:at:)``).
struct Change: Sendable {
    /// The transaction ULID.
    let txn: NodeID

    /// The time of the transaction.
    let at: DateTime

    /// The local ref of the actor of the transaction.
    let actorRef: LocalRef

    /// The names of the public mutations of the tool call.
    let ops: [String]

    /// The keys of the boards that the transaction changed: first the key of the board whose events made this change
    /// (``BatchTransaction/boardKey``). For a change of a transaction of a different board in the change feed of a
    /// board (``ChangeBuilder/changesOfOtherBoards(ofBatch:)``), that is the different board.
    let boards: [String]

    /// `true` when a later transaction that is not undone reverses this transaction (plan.md §6.5).
    let undone: Bool

    /// The transaction that this transaction reverses, only for `undo` and `redo`.
    let undoes: NodeID?

    /// The updates of the nodes: the updates of the patched nodes in the order of the first patch of each node, then
    /// the updates of the other nodes in slot order.
    let nodeUpdates: [NodeUpdate]

    /// The cursor of the change in the change log of its board (KANBAN-7), or `nil` for a change that the change log
    /// did not give, for example a change of `Board.history`.
    let logCursor: String?

    /// The ids of the nodes that the change made or restored: `Change.added`, in the order of ``nodeUpdates``.
    var added: [NodeID] {
        ids(ofKinds: [.created, .restored])
    }

    /// The ids of the nodes that the change updated: `Change.changed`, in the order of ``nodeUpdates``.
    var changed: [NodeID] {
        ids(ofKinds: [.updated])
    }

    /// The ids of the nodes that the change deleted: `Change.removed`, in the order of ``nodeUpdates``.
    var removed: [NodeID] {
        ids(ofKinds: [.deleted])
    }

    /// Gives this change with different node updates.
    ///
    /// - Parameter updates: The node updates of the new change.
    /// - Returns: The change with the same envelope, the same cursor, and these updates.
    func replacingNodeUpdates(_ updates: [NodeUpdate]) -> Change {
        copy(nodeUpdates: updates, logCursor: logCursor)
    }

    /// Gives this change as the change of one cursor of the change log of its board.
    ///
    /// - Parameter cursor: The cursor of the change in the change log.
    /// - Returns: The change with the same envelope, the same updates, and the cursor.
    func reading(atCursor cursor: String) -> Change {
        copy(nodeUpdates: nodeUpdates, logCursor: cursor)
    }

    /// Gives a copy of this change with different updates and a different cursor. This is the one place that copies
    /// each field of the envelope.
    ///
    /// - Parameters:
    ///   - updates: The node updates of the copy.
    ///   - cursor: The cursor of the copy in the change log, or `nil`.
    /// - Returns: The copy.
    private func copy(nodeUpdates updates: [NodeUpdate], logCursor cursor: String?) -> Change {
        Change(
            txn: txn,
            at: at,
            actorRef: actorRef,
            ops: ops,
            boards: boards,
            undone: undone,
            undoes: undoes,
            nodeUpdates: updates,
            logCursor: cursor
        )
    }

    /// Gives the ids of the nodes of the updates of some kinds.
    ///
    /// - Parameter kinds: The kinds of the updates.
    /// - Returns: The ids, in the order of ``nodeUpdates``.
    private func ids(ofKinds kinds: Set<UpdateKind>) -> [NodeID] {
        nodeUpdates.filter { update in kinds.contains(update.kind) }.map(\.id)
    }

    /// Resolves `Change.cursor`: the cursor of the change in the change log of its board. A change of `Board.history`,
    /// `undo`, or `redo` has no log cursor: it gives the cursor of the first board of ``boards`` as the call reads it,
    /// so that `changes(after:)` with it gives the changes after that read.
    ///
    /// - Parameter context: The context of the call. Its store finds the board of the transaction.
    /// - Returns: The cursor.
    /// - Throws: An error of ``KanbanContext/view(ofBoardOfChange:)``, or of ``BoardView/changeCursor()`` for a board
    ///   with no change log.
    func cursor(context: KanbanContext, arguments _: NoArguments) async throws(KanbanError) -> String {
        if let logCursor {
            return logCursor
        }
        return try await context.view(ofBoardOfChange: boards[boards.startIndex]).changeCursor()
    }

    /// Resolves `Change.actor`: the actor of the transaction, in the graph now of the board of the transaction. The
    /// first key of ``boards`` names that board: the current board or a related board (plan.md §6.6). The ref of the
    /// actor is local to that board, also for a change that a board gets for a transaction of a board that it depends
    /// on (plan.md §6.7). A tombstoned actor resolves to the tombstone, with `deleted` set (plan.md
    /// §5.3, step 5).
    ///
    /// - Parameter context: The context of the call. Its store finds the board of the transaction.
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
    /// - Throws: An error of ``ChangeFilter/init(parsing:)`` or of ``KanbanContext/view(ofBoardOfChange:)``.
    func updates(context: KanbanContext, arguments: FilterArguments) async throws(KanbanError) -> [NodeUpdate]? {
        let filter = try ChangeFilter(parsing: arguments.filter)
        guard arguments.filter != nil, let first = nodeUpdates.first else {
            return nodeUpdates
        }
        let view = try await context.view(ofBoardOfChange: first.boardKey)
        return filter.updates(of: nodeUpdates, readingNodesOf: view)
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
    /// Adds the `Change`, `NodeUpdate`, and `FieldChange` types and their enums (plan.md §4.1). `Board.history`,
    /// `Subscription.changes`, `Mutation.undo`, and `Mutation.redo` give these types.
    ///
    /// - Returns: This builder, for method chaining.
    func addChangeTypes() -> Self {
        add {
            Self.enumType(NodeType.self)
            Self.enumType(UpdateKind.self)
            Type(Change.self) {
                Field("cursor", at: Change.cursor).description(SchemaDescription.changeCursor)
                Field("txn", at: \.txn).description(SchemaDescription.changeTxn)
                Field("at", at: \.at).description(SchemaDescription.changeAt)
                Field("added", at: \.added).description(SchemaDescription.changeAdded)
                Field("changed", at: \.changed).description(SchemaDescription.changeChanged)
                Field("removed", at: \.removed).description(SchemaDescription.changeRemoved)
                Field("actor", at: Change.actor).description(SchemaDescription.changeActor)
                Field("ops", at: \.ops).description(SchemaDescription.changeOps)
                Field("boards", at: \.boards).description(SchemaDescription.changeBoards)
                Field("undone", at: \.undone).description(SchemaDescription.changeUndone)
                Field("undoes", at: \.undoes).description(SchemaDescription.changeUndoes)
                Field("updates", at: Change.updates) {
                    Argument("filter", at: \.filter).description(SchemaDescription.updateFilter)
                }
                .description(SchemaDescription.changeUpdates)
            }
            .description(SchemaDescription.change)
            Type(NodeUpdate.self) {
                Field("id", at: \.id).description(SchemaDescription.nodeUpdateID)
                Field("type", at: \.type).description(SchemaDescription.nodeUpdateType)
                Field("kind", at: \.kind).description(SchemaDescription.nodeUpdateKind)
                Field("fields", at: \.fields).description(SchemaDescription.nodeUpdateFields)
                Field("node", at: NodeUpdate.node).description(SchemaDescription.nodeUpdateNode)
            }
            .description(SchemaDescription.nodeUpdate)
            Type(FieldChange.self) {
                Field("name", at: \.name).description(SchemaDescription.fieldChangeName)
                Field("before", at: \.before).description(SchemaDescription.fieldChangeBefore)
                Field("after", at: \.after).description(SchemaDescription.fieldChangeAfter)
                Field("added", at: \.added).description(SchemaDescription.fieldChangeAdded)
                Field("removed", at: \.removed).description(SchemaDescription.fieldChangeRemoved)
                Field("diff", at: \.diff).description(SchemaDescription.fieldChangeDiff)
            }
            .description(SchemaDescription.fieldChange)
        }
    }

    /// Makes a GraphQL enum type with one value for each case of a Swift enum, with the description of the type and
    /// of each value.
    ///
    /// - Parameter type: The Swift enum. The raw value of each case is the GraphQL name of the value.
    /// - Returns: The enum type.
    static func enumType<Cases: DescribedGraphQLEnum>(
        _ type: Cases.Type
    ) -> Graphiti.Enum<KanbanResolver, KanbanContext, Cases> {
        Graphiti.Enum(type) {
            // The explicit `return` turns off the result builder, so the closure gives the array as it is.
            return type.allCases.map { value in Value(value).description(value.valueDescription) }
        }
        .description(type.typeDescription)
    }
}
