import Foundation
import GraphQL
import OrderedCollections

// MARK: - Builder

/// Makes the ``Change`` of one transaction from the projection before and after the transaction (plan.md §5.3 step 5,
/// §6.7).
///
/// The change has one `PATCH` update for each node that a patch of the transaction changed, in the order of the first
/// patch of each node. Then it has one `DERIVED` update for each other live node whose field values changed, in slot
/// order: for example a task that becomes ready when the task that it depends on is done, a task whose tags change
/// with a tag rename, and the board, whose summary changes. The values are the values that a query shows before and
/// after the transaction (``NodeObject/trackedFields``), not the raw patches.
struct ChangeBuilder: Sendable {
    /// The read view of the graph before the transaction.
    private let before: BoardView

    /// The read view of the graph after the transaction.
    private let after: BoardView

    /// Makes a builder for one transaction.
    ///
    /// - Parameters:
    ///   - before: The read view of the graph just before the transaction.
    ///   - after: The read view of the graph just after the transaction.
    init(from before: BoardView, to after: BoardView) {
        self.before = before
        self.after = after
    }

    /// Makes the change of the events of one transaction.
    ///
    /// - Parameters:
    ///   - events: The events of the transaction, in the order of their ids. All of them have the same `txn`.
    ///   - isUndone: `true` when a later transaction that is not undone reverses this transaction (plan.md §6.5).
    /// - Returns: The change, or `nil` when there are no events.
    func change(of events: [Event], markingUndone isUndone: Bool) -> Change? {
        let patched = OrderedSet(events.map(\.patch.node))
        return change(of: events, patching: patched, inBoard: after.boardKey, markingUndone: isUndone)
    }

    /// Makes the change that a transaction of a different board makes in this board: only the `DERIVED` updates
    /// (plan.md §6.7, derived updates across boards). For example, a task of a related board becomes done, and a task
    /// of this board that depends on it becomes ready.
    ///
    /// - Parameters:
    ///   - events: The events of the transaction in the other board, in the order of their ids.
    ///   - key: The current key of the other board. It is the first key of `boards`.
    ///   - isUndone: `true` when a later transaction that is not undone reverses this transaction (plan.md §6.5).
    /// - Returns: The change, or `nil` when there are no events.
    func derivedChange(of events: [Event], inBoard key: String, markingUndone isUndone: Bool) -> Change? {
        change(of: events, patching: [], inBoard: key, markingUndone: isUndone)
    }

    /// Makes the change of the events of one transaction.
    ///
    /// - Parameters:
    ///   - events: The events of the transaction, in the order of their ids.
    ///   - patched: The local refs of the nodes of this board that a patch of the transaction changed.
    ///   - key: The current key of the board of the events. It is the first key of `boards`.
    ///   - isUndone: `true` when a later transaction that is not undone reverses this transaction.
    /// - Returns: The change, or `nil` when there are no events.
    private func change(
        of events: [Event],
        patching patched: OrderedSet<LocalRef>,
        inBoard key: String,
        markingUndone isUndone: Bool
    ) -> Change? {
        guard let first = events.first else {
            return nil
        }
        let patchUpdates = patched.compactMap { ref in update(of: ref, from: .patch) }
        let derivedUpdates = after.graph.allSlots.compactMap { slot in derivedUpdate(ofNodeAt: slot, besides: patched) }
        return Change(
            txn: NodeID(text: first.txn.ulidString),
            at: first.at,
            actorRef: first.actor,
            ops: first.ops,
            boards: [key] + (first.boards ?? []),
            undone: isUndone,
            undoes: first.undoes.map { txn in NodeID(text: txn.ulidString) },
            nodeUpdates: patchUpdates + derivedUpdates
        )
    }

    /// Makes the `DERIVED` update of the node in a slot.
    ///
    /// - Parameters:
    ///   - slot: A slot of the graph after the transaction.
    ///   - patched: The local refs of the nodes that a patch of the transaction changed.
    /// - Returns: The update, or `nil` when a patch changed the node, the node is a tombstone, the slot holds no
    ///   node, or no field value of the node changed.
    private func derivedUpdate(ofNodeAt slot: Int, besides patched: OrderedSet<LocalRef>) -> NodeUpdate? {
        guard let node = after.graph.node(at: slot), !patched.contains(node.ref), !node.state.fields.isDeleted else {
            return nil
        }
        return update(of: node.ref, from: .derived)
    }

    /// Makes the update of one node: the change of each field value from before to after the transaction.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the node.
    ///   - source: `PATCH` when a patch of the transaction changed the node, else `DERIVED`.
    /// - Returns: The update, or `nil` when the graph after the transaction does not have the node, or when a
    ///   `DERIVED` update has no field change.
    private func update(of ref: LocalRef, from source: UpdateSource) -> NodeUpdate? {
        guard let newFields = after.trackedFields(of: ref) else {
            return nil
        }
        let oldFields = before.trackedFields(of: ref)
        let fields = newFields.compactMap { name, value in FieldChange(named: name, from: oldFields?[name], to: value) }
        guard source == .patch || !fields.isEmpty else {
            return nil
        }
        return NodeUpdate(
            ref: ref,
            id: after.id(of: ref),
            type: NodeType(ref.nodeType),
            kind: kind(of: ref),
            source: source,
            fields: fields,
            boardKey: after.boardKey
        )
    }

    /// Tells how the transaction changed a node (plan.md §6.7, Kind).
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: `CREATED` when the graph before the transaction does not have the node, `DELETED` when the node
    ///   became a tombstone, `RESTORED` when the tombstone went away, else `UPDATED`.
    private func kind(of ref: LocalRef) -> UpdateKind {
        guard let old = before.graph.node(for: ref) else {
            return .created
        }
        let wasDeleted = old.state.fields.isDeleted
        switch (wasDeleted, after.graph.node(for: ref)?.state.fields.isDeleted ?? wasDeleted) {
        case (false, true): return .deleted
        case (true, false): return .restored
        default: return .updated
        }
    }
}

extension BoardView {
    /// Gives the values of the public fields of the node of a ref, live or tombstoned.
    ///
    /// - Parameter ref: The local ref of the node.
    /// - Returns: The values, or `nil` when the graph does not have the node.
    fileprivate func trackedFields(of ref: LocalRef) -> TrackedFields? {
        graph.slot(for: ref).flatMap(nodeObject(at:))?.trackedFields
    }

    /// Gives the full URI of the node in a slot as a JSON value.
    ///
    /// - Parameter slot: A slot of the graph, or `nil` for no node.
    /// - Returns: The URI text, or `null` when there is no slot or the slot holds no node.
    fileprivate func idValue(ofNodeAt slot: Int?) -> Map {
        Map(slot.flatMap(graph.node(at:)).map { node in id(of: node.ref).text })
    }
}

// MARK: - Field values

/// The value of one public field of a node, in the form that a field change compares (plan.md §6.7, Fields).
enum TrackedValue: Equatable, Sendable {
    /// A single value, for example a name, the id of a column, or `ready`. A field with no value has `null`.
    case single(Map)

    /// A list value, for example the ids of the tags or the virtual tags.
    case list([Map])

    /// The Markdown body. A field change gives only a diff for it.
    case body(String)

    /// The value of the field of a node that does not exist: `null`, an empty list, or an empty body.
    fileprivate var emptyValue: TrackedValue {
        switch self {
        case .single: .single(.null)
        case .list: .list([])
        case .body: .body("")
        }
    }

    /// Gives the list value of the ids of some nodes.
    ///
    /// - Parameter objects: The nodes, in the order of the field.
    /// - Returns: The full URI of each node.
    fileprivate static func ids(of objects: [some NodeObject]) -> TrackedValue {
        .list(objects.map { object in Map(object.id.text) })
    }
}

/// The values of the public fields of a node, by field name, in the order of the fields of the node type.
///
/// The fields `id` and `shortId` never change. `created` and `updated` are not in the values, because each patch
/// changes `updated`, and `Change.at` gives the time. A field with arguments and a list of child nodes (for example
/// `Board.columns` and `Task.comments`) are not in the values either: the child node has its own update.
typealias TrackedFields = OrderedDictionary<String, TrackedValue>

extension FieldChange {
    /// Makes the change of one field from its value before and after a transaction.
    ///
    /// - Parameters:
    ///   - name: The public field name.
    ///   - before: The value before the transaction, or `nil` when the node did not exist.
    ///   - after: The value after the transaction.
    /// - Returns: The change, or `nil` when the value did not change. A list with the same members in a different
    ///   order did not change.
    fileprivate init?(named name: String, from before: TrackedValue?, to after: TrackedValue) {
        switch (before ?? after.emptyValue, after) {
        case (.single(let old), .single(let new)) where old != new:
            let (oldValue, newValue) = (old.nonNullValue, new.nonNullValue)
            self.init(name: name, before: oldValue, after: newValue, added: nil, removed: nil, diff: nil)
        case (.list(let old), .list(let new)):
            let added = new.filter { item in !old.contains(item) }
            let removed = old.filter { item in !new.contains(item) }
            guard !added.isEmpty || !removed.isEmpty else {
                return nil
            }
            self.init(name: name, before: nil, after: nil, added: added, removed: removed, diff: nil)
        case (.body(let old), .body(let new)) where old != new:
            let diff = UnifiedDiff(from: old, to: new).text
            self.init(name: name, before: nil, after: nil, added: nil, removed: nil, diff: diff)
        default:
            return nil
        }
    }
}

extension Map {
    /// The value, or `nil` for the JSON `null`.
    fileprivate var nonNullValue: Map? {
        isNull ? nil : self
    }
}

extension BoardSummary {
    /// The summary as the JSON object that `Board.summary` shows, with its keys in sorted order.
    fileprivate var jsonValue: Map {
        ["blocked": Map(blocked), "done": Map(done), "percent": Map(percent), "ready": Map(ready), "total": Map(total)]
    }
}

extension TaskProgress {
    /// The progress as the JSON object that `Task.progress` shows, with its keys in sorted order.
    fileprivate var jsonValue: Map {
        ["completed": Map(completed), "fraction": Map(fraction), "total": Map(total)]
    }
}

// MARK: - Node objects

extension GraphNodeObject {
    /// Gives the values of the fields of the `Node` interface that a change compares, `body` and `deleted`, then the
    /// values of the fields of the node type.
    ///
    /// - Parameter fields: The values of the fields of the node type, in the order of the fields.
    /// - Returns: The values.
    fileprivate func nodeFields(adding fields: [(String, TrackedValue)]) -> TrackedFields {
        let interfaceFields: [(String, TrackedValue)] = [
            ("body", .body(body)),
            ("deleted", .single(Map(deleted?.rfc3339))),
        ]
        return TrackedFields(uniqueKeysWithValues: interfaceFields + fields)
    }

    /// Gives the values of the fields of the `Node` interface, then the value of `name`, then the values of the other
    /// fields of the node type.
    ///
    /// - Parameters:
    ///   - name: The name of the node.
    ///   - fields: The values of the other fields of the node type, in the order of the fields.
    /// - Returns: The values.
    fileprivate func nodeFields(named name: String, adding fields: [(String, TrackedValue)]) -> TrackedFields {
        nodeFields(adding: [("name", .single(Map(name)))] + fields)
    }
}

extension LabelObject {
    /// Gives the values of the public fields of an actor or a tag: the fields of the `Node` interface, `name`, and
    /// `color`.
    ///
    /// - Parameter colorValue: The value of the `color` field. The color type of an actor and of a tag is not the
    ///   same, so each type gives its color as a JSON value.
    /// - Returns: The values.
    fileprivate func labelFields(withColor colorValue: Map) -> TrackedFields {
        nodeFields(named: name, adding: [("color", .single(colorValue))])
    }
}

extension BoardObject {
    /// The values of the public fields of the board: `name` and the derived `summary`.
    var trackedFields: TrackedFields {
        nodeFields(named: name, adding: [("summary", .single(summary.jsonValue))])
    }
}

extension ColumnObject {
    /// The values of the public fields of the column: `name` and `order`.
    var trackedFields: TrackedFields {
        nodeFields(named: name, adding: [("order", .single(Map(order)))])
    }
}

extension ActorObject {
    /// The values of the public fields of the actor: `name` and `color`.
    var trackedFields: TrackedFields {
        labelFields(withColor: Map(color))
    }
}

extension TagObject {
    /// The values of the public fields of the tag: `name` and `color`.
    var trackedFields: TrackedFields {
        labelFields(withColor: Map(color))
    }
}

extension TaskObject {
    /// The values of the public fields of the task: the stored fields, the read-time `tags` and `dependsOn`
    /// (plan.md §6.1), and the derived fields (plan.md §5.3 step 4).
    var trackedFields: TrackedFields {
        nodeFields(adding: [
            ("title", .single(Map(title))),
            ("column", .single(view.idValue(ofNodeAt: view.readiness.column(ofTaskAt: slot)))),
            ("ordinal", .single(Map(ordinal))),
            ("assignees", .ids(of: assignees)),
            ("tags", .ids(of: tags)),
            ("dependsOn", .ids(of: dependsOn)),
            ("blockedBy", .ids(of: blockedBy)),
            ("blocks", .ids(of: blocks)),
            ("ready", .single(Map(ready))),
            ("virtualTags", .list(virtualTags.map { tag in Map(tag) })),
            ("progress", .single(progress.jsonValue)),
            ("started", .single(Map(started?.rfc3339))),
            ("completed", .single(Map(completed?.rfc3339))),
        ])
    }
}

extension CommentObject {
    /// The values of the public fields of the comment: the `task` and the `author`.
    var trackedFields: TrackedFields {
        nodeFields(adding: [
            ("task", .single(view.idValue(ofNodeAt: state.task?.resolvedSlot))),
            ("author", .single(view.idValue(ofNodeAt: authorSlot))),
        ])
    }
}
