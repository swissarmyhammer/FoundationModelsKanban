import Foundation
import FoundationModelsExtras
import Graphiti
import OrderedCollections
import ULID

// MARK: - Kind

/// The kind of one entry of `Task.timeline`: the GraphQL `TimelineKind` enum (divergence.md §23).
enum TimelineKind: String, Codable, Sendable, CaseIterable {
    /// The task moved from one column to a different column.
    case move = "MOVE"

    /// One stored field of the task changed.
    case field = "FIELD"

    /// A comment of the task was added, changed, deleted, or undeleted.
    case comment = "COMMENT"
}

extension TimelineKind: DescribedGraphQLEnum {
    /// The description of the `TimelineKind` enum.
    static let typeDescription = SchemaDescription.timelineKind

    /// The description of the value of this case.
    var valueDescription: String {
        switch self {
        case .move: SchemaDescription.timelineKindMove
        case .field: SchemaDescription.timelineKindField
        case .comment: SchemaDescription.timelineKindComment
        }
    }
}

// MARK: - Cursor

/// The place of one entry in the timeline of a task (divergence.md §23): the transaction of the entry, and the place
/// of the entry among the entries of that transaction. The timeline sorts its entries by this value: the newest
/// transaction first, and the entries of one transaction in their own order.
struct TimelineCursor: Comparable, Sendable {
    /// The character between the transaction and the place in the text of a cursor.
    static let separator: Character = ":"

    /// The number of parts of the text of a cursor: the transaction and the place.
    private static let partCount = 2

    /// The ULID text of the transaction, in uppercase. The ULID text sorts in time order.
    private let txnText: String

    /// The place of the entry among the entries of its transaction, from zero.
    private let index: Int

    /// Makes the cursor of one entry.
    ///
    /// - Parameters:
    ///   - txn: The transaction of the entry.
    ///   - index: The place of the entry among the entries of the transaction, from zero.
    init(txn: ULID, index: Int) {
        txnText = txn.ulidString
        self.index = index
    }

    /// Reads the `after` argument of `Task.timeline`: the cursor of an entry, or the txn of a transaction, in any case
    /// and with white space at its ends. A txn has no place, so the page after it starts at the first entry of an
    /// older transaction. Text that is not a cursor reads as a txn: the ULID text sorts in time order, so the text
    /// does not have to be a transaction of the log, the same as `Board.history(since:)`.
    ///
    /// - Parameter text: The text of the argument.
    init(parsing text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let parts = trimmed.split(separator: Self.separator, omittingEmptySubsequences: false)
        if parts.count == Self.partCount, let txn = parts.first, let place = parts.last, let index = Int(place) {
            txnText = String(txn)
            self.index = index
        } else {
            txnText = trimmed
            index = .max
        }
    }

    /// The text of the cursor: `<txn>:<place>`.
    var text: String {
        "\(txnText)\(Self.separator)\(index)"
    }

    /// Tells if one cursor comes before a different cursor in the timeline.
    ///
    /// - Parameters:
    ///   - lhs: A cursor.
    ///   - rhs: A different cursor.
    /// - Returns: `true` when `lhs` has a newer transaction, or the same transaction and an earlier place.
    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.txnText == rhs.txnText ? lhs.index < rhs.index : lhs.txnText > rhs.txnText
    }
}

// MARK: - Entry

/// What one entry of the timeline of a task changed (divergence.md §23).
enum TimelineChange: Sendable {
    /// The task moved: the stored column edge before and after the transaction. The edge before is `nil` for the
    /// first move of the task.
    case move(from: EdgeTarget?, to: EdgeTarget?)

    /// One stored field of the task changed.
    case field(FieldChange)

    /// One comment of the task changed: the slot of the comment, how it changed, and the diff of its body for a
    /// change of the body.
    case comment(slot: Int, update: UpdateKind, body: FieldChange?)
}

/// One entry of `Task.timeline`: the GraphQL `TimelineEntry` type (divergence.md §23, TestudoApp KANBAN-13).
struct TimelineEntry: Sendable {
    /// The place of the entry in the timeline.
    let place: TimelineCursor

    /// The transaction of the entry.
    let txnID: ULID

    /// The time of the transaction.
    let at: DateTime

    /// The local ref of the actor of the transaction.
    let actorRef: LocalRef

    /// `true` when a later transaction that is not undone reverses the transaction (plan.md §6.5).
    let undone: Bool

    /// What the entry changed.
    let change: TimelineChange

    /// The read view of the board of the task. The nodes of the entry resolve in it.
    let view: BoardView

    /// The cursor of the entry: give it as `after` to get the entries after it.
    var cursor: String {
        place.text
    }

    /// The transaction ULID.
    var txn: NodeID {
        NodeID(text: txnID.ulidString)
    }

    /// The kind of the entry.
    var kind: TimelineKind {
        switch change {
        case .move: .move
        case .field: .field
        case .comment: .comment
        }
    }

    /// The column before a move, live or tombstoned, or `nil` for each other entry and for the first move.
    var from: ColumnObject? {
        guard case .move(let column, _) = change else {
            return nil
        }
        return view.column(atEdge: column)
    }

    /// The column after a move, live or tombstoned, or `nil` for each other entry.
    var to: ColumnObject? {
        guard case .move(_, let column) = change else {
            return nil
        }
        return view.column(atEdge: column)
    }

    /// The change of the field, or the diff of the body of a changed comment, else `nil`.
    var field: FieldChange? {
        switch change {
        case .field(let field): field
        case .comment(_, _, let body): body
        case .move: nil
        }
    }

    /// The comment of a comment entry, live or tombstoned, else `nil`.
    var comment: CommentObject? {
        guard case .comment(let slot, _, _) = change else {
            return nil
        }
        return view.object(at: slot)
    }

    /// How the comment of a comment entry changed, else `nil`.
    var commentUpdate: UpdateKind? {
        guard case .comment(_, let update, _) = change else {
            return nil
        }
        return update
    }

    /// Resolves `TimelineEntry.actor`: the actor of the transaction, the same as `Change.actor`.
    ///
    /// - Parameters:
    ///   - context: The context of the call. The field does not read it.
    ///   - arguments: The field has no arguments.
    /// - Returns: The actor, live or tombstoned.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` for the actor when the board does not have the actor.
    func actor(context _: KanbanContext, arguments _: NoArguments) throws(KanbanError) -> ActorObject {
        try view.envelopeActor(for: actorRef)
    }
}

extension BoardView {
    /// Gives the column at a stored column edge, live or tombstoned.
    ///
    /// - Parameter edge: The edge, or `nil` for no edge.
    /// - Returns: The column, or `nil` when there is no edge, or the graph has no column for it.
    fileprivate func column(atEdge edge: EdgeTarget?) -> ColumnObject? {
        switch edge {
        case .slot(let slot)?: object(at: slot)
        case .unresolved(.local(let ref))?: graph.slot(for: ref).flatMap { slot in object(at: slot) }
        case .unresolved(.remote)?, nil: nil
        }
    }
}

// MARK: - Timeline

/// One change of the timeline before it has its place: the first event of its transaction on the node, and the change.
private struct StepChange {
    /// The first event of the transaction on the node. It gives the transaction, the time, and the actor.
    let event: Event

    /// What the step changed.
    let change: TimelineChange
}

extension TaskObject {
    /// The name of the body field: the field change of a comment entry for a change of the body of the comment.
    private static let bodyField = "body"

    /// Gives the entries of the timeline of the task, newest first (divergence.md §23).
    ///
    /// The timeline reads only the log of the task and the log of each of its comments, live or tombstoned, from
    /// `logs`. It folds each log one transaction at a time (``TransactionStep``), and compares the state of the node
    /// just before and just after each transaction. The entries of one transaction come in this order: the move of the
    /// task, the change of each stored field of the task in the order of ``storedFields``, and then the change of each
    /// comment in the order of the comment ULIDs.
    ///
    /// - Parameter logs: The node logs of the board of the task.
    /// - Returns: The entries, sorted by ``TimelineCursor``.
    func timelineEntries(reading logs: some NodeLogReading) -> [TimelineEntry] {
        let taskChanges = TransactionStep.steps(folding: logs.events(of: state.ref), for: state.ref)
            .flatMap(changes(madeBy:))
        let commentChanges = view.graph.allComments(ofTaskAt: slot).flatMap { commentSlot in
            commentChanges(ofCommentAt: commentSlot, reading: logs)
        }
        let undone = logs.undoneState
        let byTransaction = OrderedDictionary(grouping: taskChanges + commentChanges, by: \.event.txn)
        return byTransaction.keys.sorted(by: >).flatMap { txn in
            byTransaction[txn, default: []].enumerated().map { index, step in
                TimelineEntry(
                    place: TimelineCursor(txn: txn, index: index),
                    txnID: txn,
                    at: step.event.at,
                    actorRef: step.event.actor,
                    undone: undone.isUndone(txn: txn),
                    change: step.change,
                    view: view
                )
            }
        }
    }

    /// Gives the changes of the task that one transaction made: the move, then each stored field.
    ///
    /// - Parameter step: The task just before and just after the transaction.
    /// - Returns: The changes. A transaction that changed no stored field and no column gives none.
    private func changes(madeBy step: TransactionStep) -> [StepChange] {
        guard let event = step.events.first, let after = step.after?.state as? TaskNode else {
            return []
        }
        let before = step.before?.state as? TaskNode
        let isMove = before?.column != after.column
        let move: [TimelineChange] = isMove ? [.move(from: before?.column, to: after.column)] : []
        let oldFields = before.map { state in TaskObject(view: view, slot: slot, state: state).storedFields }
        let newFields = TaskObject(view: view, slot: slot, state: after).storedFields
        let fields = newFields.compactMap { name, value in FieldChange(named: name, from: oldFields?[name], to: value) }
        return (move + fields.map(TimelineChange.field)).map { change in StepChange(event: event, change: change) }
    }

    /// Gives the changes of one comment of the task, one for each transaction that wrote the comment.
    ///
    /// - Parameters:
    ///   - commentSlot: The slot of the comment.
    ///   - logs: The node logs of the board of the task.
    /// - Returns: The changes, in the order of the transaction ULIDs.
    private func commentChanges(ofCommentAt commentSlot: Int, reading logs: some NodeLogReading) -> [StepChange] {
        guard let ref = view.graph.node(at: commentSlot)?.ref else {
            return []
        }
        return TransactionStep.steps(folding: logs.events(of: ref), for: ref).compactMap { step in
            guard let event = step.events.first, let after = step.after else {
                return nil
            }
            let update = UpdateKind(from: step.before, to: after)
            let oldBody = step.before.map { node in TrackedValue.body(node.state.fields.body) }
            let body = update == .updated
                ? FieldChange(named: Self.bodyField, from: oldBody, to: .body(after.state.fields.body))
                : nil
            return StepChange(event: event, change: .comment(slot: commentSlot, update: update, body: body))
        }
    }

    /// Resolves `Task.timeline` (divergence.md §23): one page of the entries of the timeline, newest first.
    ///
    /// The timeline reads the committed log of the board of the task, the same as `Board.history`: a patch of the same
    /// call is not in the log yet, so it is not in the list. A board in memory only has no node logs, so the call
    /// groups the global event list of the working copy.
    ///
    /// - Parameters:
    ///   - context: The context of the call. Its store holds the global event list of a board in memory only.
    ///   - arguments: The page size and the cursor before the page.
    /// - Returns: The newest `first` entries after `after`. The value is never `nil`. The optional type makes the
    ///   GraphQL field nullable.
    func timeline(context: KanbanContext, arguments: TimelineArguments) async -> [TimelineEntry]? {
        let logs: NodeLogs
        if let source = view.source {
            logs = source.logs
        } else {
            logs = NodeLogs(of: await context.store.work.liveEvents)
        }
        let start = arguments.after.map(TimelineCursor.init(parsing:))
        let entries = timelineEntries(reading: logs).drop { entry in
            start.map { start in entry.place <= start } ?? false
        }
        return Array(entries.prefix(max(arguments.first ?? TimelineArguments.defaultPageSize, .zero)))
    }
}

/// The arguments of `Task.timeline`: the page size and the cursor before the page (divergence.md §23).
struct TimelineArguments: Codable, Sendable {
    /// The number of entries when the call does not give `first`: the default page of `Board.history`.
    static let defaultPageSize = HistoryArguments.defaultPageSize

    /// The largest number of entries. A negative value gives no entry. An explicit `null` gives ``defaultPageSize``.
    let first: Int?

    /// The cursor of the entry before the page, or the txn of a transaction, or `nil` to start at the newest entry.
    let after: String?
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the `TimelineEntry` type and the `TimelineKind` enum (divergence.md §23). `Task.timeline` gives them.
    ///
    /// - Returns: This builder, for method chaining.
    func addTimelineTypes() -> Self {
        add {
            Self.enumType(TimelineKind.self)
            Type(TimelineEntry.self) {
                Field("cursor", at: \.cursor).description(SchemaDescription.timelineCursor)
                Field("txn", at: \.txn).description(SchemaDescription.timelineTxn)
                Field("at", at: \.at).description(SchemaDescription.changeAt)
                Field("actor", at: TimelineEntry.actor).description(SchemaDescription.changeActor)
                Field("undone", at: \.undone).description(SchemaDescription.timelineUndone)
                Field("kind", at: \.kind).description(SchemaDescription.timelineEntryKind)
                Field("from", at: \.from).description(SchemaDescription.timelineFrom)
                Field("to", at: \.to).description(SchemaDescription.timelineTo)
                Field("field", at: \.field).description(SchemaDescription.timelineField)
                Field("comment", at: \.comment).description(SchemaDescription.timelineComment)
                Field("commentUpdate", at: \.commentUpdate).description(SchemaDescription.timelineCommentUpdate)
            }
            .description(SchemaDescription.timelineEntry)
        }
    }
}
