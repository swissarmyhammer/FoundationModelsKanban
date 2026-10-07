import Foundation
import Logging
import OrderedCollections
import ULID

/// The log of one node, read and folded (plan.md §5.3 steps 1 to 3).
///
/// Each patch changes exactly one node, and each node has its own log file (plan.md §5.2). Thus, the state of a node
/// depends only on the lines of its own file. The fold sorts the events by event id, so the order of the lines in the
/// file is not important: a `union` merge can put the lines in any order, and the result is the same.
///
/// Replay never refuses a log (plan.md §3.3, rule 7). A line that does not decode, a line whose patch changes a
/// different node, an `edit` whose diff does not parse, and a property value of the wrong kind are skipped. Each skip
/// is recorded with swift-log.
struct NodeLog: Hashable, Sendable {
    /// The events of the log, in the order of their event ids. The loader merges these lists into the global event
    /// list (plan.md §5.3, global order).
    let events: [Event]

    /// The state of the node, or `nil` when the log has no event of the node. A node exists after its first patch
    /// (plan.md §5.1).
    let node: Node?

    /// Reads the lines of the log file of one node, and folds them into the state of the node.
    ///
    /// A line that holds only white space is skipped with no record, because a file ends with a line break. When two
    /// lines hold the same event, the fold applies it one time.
    ///
    /// - Parameters:
    ///   - lines: The lines of the file, in any order.
    ///   - ref: The local ref of the node of the file.
    init(parsing lines: some Sequence<String>, for ref: LocalRef) {
        let parsed = lines.compactMap { line in ParsedLine(parsing: line, for: ref) }
        events = Self.uniqueEvents(of: parsed.sorted(by: ParsedLine.precedes))
        node = NodeFold(folding: events, for: ref)?.node
    }

    /// Gives the events of the sorted lines, with each repeated event removed.
    ///
    /// - Parameter lines: The parsed lines, in replay order.
    /// - Returns: The events, in replay order, each one time.
    private static func uniqueEvents(of lines: [ParsedLine]) -> [Event] {
        let events = OrderedSet(lines.map(\.event))
        if events.count < lines.count {
            Log.kanban.debug("A node log holds a repeated event; replay applies it one time")
        }
        return events.elements
    }
}

// MARK: - Parse

/// One line of a node log that decodes to an event of the node.
private struct ParsedLine {
    /// The event of the line.
    let event: Event

    /// The text of the line. It breaks a tie between two different lines with the same event id, so that the replay
    /// order does not depend on the order of the lines in the file.
    let text: String

    /// Tells if one line comes before a different line in replay order: by event id, then by text.
    ///
    /// - Parameters:
    ///   - lhs: A line.
    ///   - rhs: A different line.
    /// - Returns: `true` when `lhs` comes first.
    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        (lhs.event.id, lhs.text) < (rhs.event.id, rhs.text)
    }

    /// Reads one line of the log of a node.
    ///
    /// - Parameters:
    ///   - text: The text of the line.
    ///   - ref: The local ref of the node of the log.
    /// - Returns: The line, or `nil` when the line is blank, does not decode, or changes a different node.
    init?(parsing text: String, for ref: LocalRef) {
        guard !text.allSatisfy(\.isWhitespace) else {
            return nil
        }
        let event: Event
        do {
            event = try Event(parsing: text)
        } catch {
            Log.kanban.warning(
                "Replay skips a log line that does not decode",
                metadata: ["node": "\(ref)", "error": "\(error)"]
            )
            return nil
        }
        guard event.patch.node == ref else {
            Log.kanban.warning(
                "Replay skips a log line that changes a different node",
                metadata: ["node": "\(ref)", "lineNode": "\(event.patch.node)", "event": "\(event.id)"]
            )
            return nil
        }
        self.event = event
        self.text = text
    }
}

// MARK: - Fold

/// The state of one node while replay applies its patches in event order (plan.md §5.3 steps 2 and 3).
private struct NodeFold {
    /// The local ref of the node.
    let ref: LocalRef

    /// The time of the first patch.
    let created: DateTime

    /// The time of the last patch so far.
    var updated: DateTime

    /// The time of the last `delete: true`, only while the node is a tombstone.
    var deleted: DateTime?

    /// The body after the `edit` patches so far.
    var body = ""

    /// `true` when the body has a full conflict block.
    var hasConflict = false

    /// The properties after the `set`, `unset`, `add`, and `remove` parts so far.
    var properties = PropertyBag()

    /// Each `set column` of a task so far, with its time.
    var columnMoves: [ColumnMove] = []

    /// Folds the events of one node.
    ///
    /// - Parameters:
    ///   - events: The events of the node, in replay order.
    ///   - ref: The local ref of the node.
    /// - Returns: The folded state, or `nil` when there is no event.
    init?(folding events: [Event], for ref: LocalRef) {
        guard let first = events.first else {
            return nil
        }
        self.ref = ref
        created = first.at
        updated = first.at
        for event in events {
            update(with: event)
        }
    }

    /// Applies the patch of one event, and records its time values.
    ///
    /// - Parameter event: The next event in replay order.
    mutating func update(with event: Event) {
        let patch = event.patch
        updated = event.at
        properties.update(with: patch)
        recordColumnMove(of: patch, at: event.at)
        if let delete = patch.delete {
            deleted = delete ? event.at : nil
        }
        if let edit = patch.edit {
            applyEdit(edit, ofEvent: event.id)
        }
    }

    /// Records a move of a task to a column. Only a task records moves (plan.md §5.3 step 3).
    ///
    /// - Parameters:
    ///   - patch: The patch.
    ///   - time: The envelope time of the patch.
    private mutating func recordColumnMove(of patch: PatchInput, at time: DateTime) {
        guard case .task = ref, let column = patch.set[PropertyName.column]?.storedRef else {
            return
        }
        columnMoves.append(ColumnMove(at: time, column: .unresolved(column)))
    }

    /// Applies the diff of an `edit` to the body (plan.md §5.5). A diff that does not parse changes nothing.
    ///
    /// - Parameters:
    ///   - edit: The edit.
    ///   - id: The id of the event of the edit. A conflict block names it.
    private mutating func applyEdit(_ edit: PatchEdit, ofEvent id: ULID) {
        let diff: UnifiedDiff
        do {
            diff = try UnifiedDiff(parsing: edit.body)
        } catch {
            Log.kanban.warning(
                "Replay skips an edit whose diff does not parse",
                metadata: ["node": "\(ref)", "event": "\(id)", "error": "\(error)"]
            )
            return
        }
        let applied = diff.applied(to: body, withConflictLabel: id.ulidString)
        body = applied.text
        hasConflict = applied.hasConflict
    }
}

// MARK: - Node

extension NodeFold {
    /// The folded node. The properties that its node type does not read stay in
    /// ``NodeFields/unknownProperties``.
    var node: Node {
        var unread = properties
        var state = makeState(taking: &unread)
        state.fields.unknownProperties = unread
        return state.node
    }

    /// The body and the time values of the node.
    private var fields: NodeFields {
        NodeFields(body: body, created: created, updated: updated, deleted: deleted, hasConflict: hasConflict)
    }

    /// Makes the typed state of the node. Each property that the node type reads is removed from the bag.
    ///
    /// - Parameter properties: The folded properties. On return, it holds the properties that the type does not read.
    /// - Returns: The state of the node.
    private func makeState(taking properties: inout PropertyBag) -> any NodeState {
        switch ref {
        case .board:
            BoardNode(fields: fields, name: properties.removeName())
        case .column(let slug):
            ColumnNode(
                slug: slug,
                fields: fields,
                name: properties.removeName(),
                order: properties.removeInteger(forKey: PropertyName.order) ?? 0
            )
        case .actor(let slug):
            ActorNode(
                slug: slug,
                fields: fields,
                name: properties.removeName(),
                color: properties.removeText(forKey: PropertyName.color)
            )
        case .tag(let slug):
            TagNode(
                slug: slug,
                fields: fields,
                name: properties.removeName(),
                color: properties.removeText(forKey: PropertyName.color),
                renamedTo: properties.removeEdge(forKey: PropertyName.renamedTo)
            )
        case .task(let id):
            makeTask(withID: id, taking: &properties)
        case .comment(let id):
            CommentNode(
                id: id,
                fields: fields,
                task: properties.removeEdge(forKey: PropertyName.task),
                author: properties.removeEdge(forKey: PropertyName.author)
            )
        }
    }

    /// Makes the state of a task.
    ///
    /// - Parameters:
    ///   - id: The ULID of the task.
    ///   - properties: The folded properties. On return, it holds the properties that a task does not read.
    /// - Returns: The state of the task.
    private func makeTask(withID id: ULID, taking properties: inout PropertyBag) -> TaskNode {
        TaskNode(
            id: id,
            fields: fields,
            title: properties.removeText(forKey: PropertyName.title) ?? "",
            column: properties.removeEdge(forKey: PropertyName.column),
            ordinal: properties.removeOrdinal(forKey: PropertyName.ordinal) ?? .first,
            assignees: properties.removeEdges(forKey: PropertyName.assignees),
            tags: properties.removeEdges(forKey: PropertyName.tags),
            dependsOn: properties.removeEdges(forKey: PropertyName.dependsOn),
            columnMoves: columnMoves
        )
    }
}

// MARK: - Property names

/// The names of the properties that replay reads into the typed node state (plan.md §4.1).
enum PropertyName {
    /// The name of a board, a column, an actor, or a tag.
    static let name = "name"

    /// The title of a task.
    static let title = "title"

    /// The sort key of a column.
    static let order = "order"

    /// The color of an actor or a tag.
    static let color = "color"

    /// The rename target of a tag.
    static let renamedTo = "renamedTo"

    /// The column of a task.
    static let column = "column"

    /// The position of a task in its column.
    static let ordinal = "ordinal"

    /// The actors of a task.
    static let assignees = "assignees"

    /// The tags of a task.
    static let tags = "tags"

    /// The tasks that a task waits for.
    static let dependsOn = "dependsOn"

    /// The task of a comment.
    static let task = "task"

    /// The author of a comment.
    static let author = "author"
}

// MARK: - Property bag

extension PropertyBag {
    /// Applies the `set`, `unset`, `add`, and `remove` parts of a patch, in that order.
    ///
    /// - Parameter patch: The patch.
    mutating func update(with patch: PatchInput) {
        values.merge(patch.set) { _, new in new }
        for name in patch.unset {
            values[name] = nil
        }
        for (name, refs) in patch.add {
            replaceMembers(of: name, with: Array(OrderedSet((members[name] ?? []) + refs)))
        }
        for (name, refs) in patch.remove {
            replaceMembers(of: name, with: (members[name] ?? []).filter { !refs.contains($0) })
        }
    }

    /// Replaces the members of a set-valued property. A property with no members gets no entry.
    ///
    /// - Parameters:
    ///   - name: The name of the property.
    ///   - list: The new members.
    private mutating func replaceMembers(of name: String, with list: [StoredRef]) {
        members[name] = list.isEmpty ? nil : list
    }

    /// Removes the `name` property, and gives its text.
    ///
    /// - Returns: The name, or the empty text when no patch set a name.
    mutating func removeName() -> String {
        removeText(forKey: PropertyName.name) ?? ""
    }

    /// Removes a property, and gives its text.
    ///
    /// - Parameter name: The name of the property.
    /// - Returns: The text, or `nil` when the property has no value or a value that is not text.
    mutating func removeText(forKey name: String) -> String? {
        removeValue(forKey: name, readingWith: \.text)
    }

    /// Removes a property, and gives its whole number.
    ///
    /// - Parameter name: The name of the property.
    /// - Returns: The number, or `nil` when the property has no value or a value that is not a whole number.
    mutating func removeInteger(forKey name: String) -> Int? {
        removeValue(forKey: name, readingWith: \.integer)
    }

    /// Removes a property, and gives its ordinal.
    ///
    /// - Parameter name: The name of the property.
    /// - Returns: The ordinal, or `nil` when the property has no value or a value that is not an ordinal.
    mutating func removeOrdinal(forKey name: String) -> Ordinal? {
        removeValue(forKey: name, readingWith: \.ordinal)
    }

    /// Removes a ref property, and gives its edge.
    ///
    /// - Parameter name: The name of the property.
    /// - Returns: The unresolved edge to the target, or `nil` when the property has no value.
    mutating func removeEdge(forKey name: String) -> EdgeTarget? {
        removeValue(forKey: name, readingWith: \.storedRef).map(EdgeTarget.unresolved)
    }

    /// Removes a set-valued property, and gives its edges.
    ///
    /// - Parameter name: The name of the property.
    /// - Returns: The unresolved edges to the members, in the order of their first `add`.
    mutating func removeEdges(forKey name: String) -> [EdgeTarget] {
        (members.removeValue(forKey: name) ?? []).map(EdgeTarget.unresolved)
    }

    /// Removes a property, and reads its value. A value of the wrong kind is recorded with swift-log and not read.
    ///
    /// - Parameters:
    ///   - name: The name of the property.
    ///   - read: Gives the typed value, or `nil` when the value is of the wrong kind.
    /// - Returns: The typed value, or `nil` when the property has no value or a value of the wrong kind.
    private mutating func removeValue<Value>(
        forKey name: String,
        readingWith read: (PatchValue) -> Value?
    ) -> Value? {
        guard let value = values.removeValue(forKey: name) else {
            return nil
        }
        guard let typed = read(value) else {
            Log.kanban.warning(
                "Replay skips a property value of the wrong kind",
                metadata: ["property": "\(name)", "value": "\(value.map)"]
            )
            return nil
        }
        return typed
    }
}

// MARK: - Typed values

extension PatchValue {
    /// The text of a JSON string, or `nil` for a different value.
    var text: String? {
        guard case .json(.string(let text)) = self else {
            return nil
        }
        return text
    }

    /// The whole number of a JSON number, or `nil` for a different value or a number with a fraction.
    var integer: Int? {
        guard case .json(.number(let number)) = self else {
            return nil
        }
        return Int(exactly: number.doubleValue)
    }

    /// The ordinal of a JSON string, or `nil` for a different value or a text that is not an ordinal.
    var ordinal: Ordinal? {
        text.flatMap { text in try? Ordinal(parsing: text) }
    }

    /// The stored ref of a ref value, or `nil` for a JSON value.
    var storedRef: StoredRef? {
        guard case .ref(let ref) = self else {
            return nil
        }
        return ref
    }
}
