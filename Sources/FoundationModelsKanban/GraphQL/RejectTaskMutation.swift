import Foundation
import FoundationModelsExtras
import Graphiti
import GraphQL

// MARK: - Names

extension MutationName {
    /// The mutation that moves a task back with a comment to the agent, in one transaction (divergence.md §21).
    static let rejectTask = "rejectTask"
}

// MARK: - Arguments

/// The `input` object of `rejectTask` (divergence.md §21): the task, the comment, the column, and one place field or
/// none. The input has no `board` field, so the task stays on its board. It has no `ifVersion` field, because a move
/// is never refused (KanbanViewKit D100).
private struct RejectTaskInput: TaskReferenceInput, TaskPlaceInput {
    /// The keys of the fields of the input that are not place fields. ``Placement`` reads the place fields.
    private enum CodingKeys: String, CodingKey {
        /// The key of the task.
        case id

        /// The key of the comment.
        case comment

        /// The key of the column.
        case column
    }

    /// The task: a full URI or a short form (plan.md §3.2).
    let id: NodeID

    /// The Markdown body of the comment to the agent: the full text. It has a character that is not white space.
    let comment: String

    /// The column: a full URI, the slug, or a name, or `nil` for the column before the column where the task shows. A
    /// slug that no column has makes a new column.
    let column: NodeID?

    /// The place of the task in the column.
    let placement: Placement

    /// Reads the input object of a reject.
    ///
    /// - Parameter decoder: The decoder of the input object.
    /// - Throws: ``KanbanError/emptyComment`` when the comment is empty or holds only white space.
    ///   ``KanbanError/conflictingPlacement(fields:)`` when the input gives more than one place field. A
    ///   `DecodingError` when the input has no `id` or no `comment`, or a field has the wrong type.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(NodeID.self, forKey: .id)
        comment = try container.decode(String.self, forKey: .comment)
        guard !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KanbanError.emptyComment
        }
        column = try container.decodeIfPresent(NodeID.self, forKey: .column)
        placement = try Placement(from: decoder)
    }
}

// MARK: - Resolver

extension KanbanResolver {
    /// Resolves `Mutation.rejectTask`: adds the comment to the task, with the session actor as the author, and moves
    /// the task, in one transaction (divergence.md §21). One `undoChange` reverses both. No column moves the task to
    /// the column before the column where it shows, in board order. The place fields have the rules of `moveTask`. A
    /// move is never refused for a version conflict (KanbanViewKit D100).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The task, the comment, the column, and the place in the column.
    /// - Returns: The task after the move. The GraphQL field is nullable, so that an error gives `null` for this field
    ///   only.
    /// - Throws: The errors of ``KanbanContext/changeTask(_:named:_:)``, and
    ///   ``WorkingCopy/reject(_:with:by:resolvingWith:at:)``. The decode of the input throws
    ///   ``KanbanError/emptyComment`` and ``KanbanError/conflictingPlacement(fields:)`` before this resolver runs, so
    ///   that the field writes nothing.
    fileprivate func rejectTask(
        context: KanbanContext,
        arguments: InputArguments<RejectTaskInput>
    ) async throws -> TaskObject? {
        let input = arguments.input
        let author = context.store.sessionActor.ref
        return try await context.changeTask(input.id, named: MutationName.rejectTask) { work, resolver, ref, time in
            try work.reject(ref, with: input, by: author, resolvingWith: resolver, at: time)
        }
    }
}

// MARK: - Patches

extension WorkingCopy {
    /// Writes the patches of a reject (divergence.md §21): a comment patch with the comment, and a task patch with a
    /// `set` of the column and the ordinal.
    ///
    /// - Parameters:
    ///   - task: The local ref of the live task.
    ///   - input: The task ref as the caller wrote it, the comment, the column, and the place in the column.
    ///   - author: The local ref of the author of the comment: the session actor.
    ///   - resolver: The resolver of the forgiving refs of the board.
    ///   - time: The time of the change.
    /// - Throws: The errors of ``columnRef(forMoveTo:resolvingWith:at:)``, of
    ///   ``Graph/columnRef(before:namedBy:)``, and of ``Graph/ordinal(placing:inColumn:moving:resolvingWith:)``. An
    ///   ``EventError`` when a patch breaks a rule of the log.
    fileprivate mutating func reject(
        _ task: LocalRef,
        with input: RejectTaskInput,
        by author: LocalRef,
        resolvingWith resolver: RefResolver,
        at time: DateTime
    ) throws {
        let column = try input.column.map { named in
            try columnRef(forMoveTo: named, resolvingWith: resolver, at: time)
        } ?? graph.columnRef(before: task, namedBy: input.id)
        let ordinal = try graph.ordinal(
            placing: input.placement,
            inColumn: column,
            moving: task,
            resolvingWith: resolver
        )
        _ = try addComment(to: task, by: author, saying: input.comment, at: time)
        try move(task, to: column, placingAt: ordinal, at: time)
    }
}

// MARK: - Graph

extension Graph {
    /// Gives the column before the column where a task shows, in board order (divergence.md §21). This is the column
    /// of a reject with no `column` field: from `done` to `review`, for example.
    ///
    /// - Parameters:
    ///   - task: The local ref of the live task.
    ///   - id: The task ref as the caller wrote it, for an error.
    /// - Returns: The local ref of the column.
    /// - Throws: ``KanbanError/noPreviousColumn(task:column:)`` when the task shows in the first column.
    ///   ``KanbanError/notFound(type:reference:)`` when the graph does not have the task, or the board has no live
    ///   column.
    fileprivate func columnRef(before task: LocalRef, namedBy id: NodeID) throws(KanbanError) -> LocalRef {
        guard let node = node(for: task)?.state as? TaskNode else {
            throw .notFound(type: .task, reference: id.text)
        }
        let order = ColumnOrder(of: self)
        let shown = order.displaySlot(of: node.column)
        guard let index = shown.flatMap(order.slots.firstIndex(of:)) else {
            throw .notFound(type: .column, reference: "")
        }
        guard index > order.slots.startIndex else {
            let first = try columnRef(atSlot: shown)
            throw .noPreviousColumn(task: id.text, column: first.localID ?? first.description)
        }
        return try columnRef(atSlot: order.slots[order.slots.index(before: index)])
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// The input fields of `RejectTaskInput`.
    ///
    /// - Returns: The fields `id`, `comment`, `column`, `ordinal`, `before`, and `after`.
    fileprivate static func rejectTaskFields() -> [InputFieldComponent<RejectTaskInput, KanbanContext>] {
        let head: [InputFieldComponent<RejectTaskInput, KanbanContext>] = [
            makeTaskReferenceField(),
            InputField("comment", at: \.comment).description(SchemaDescription.rejectComment),
            InputField("column", at: \.column).description(SchemaDescription.rejectColumn),
        ]
        return head + placeFields(describedBy: .oneTask)
    }

    /// Adds the `rejectTask` mutation and its `input` type (divergence.md §21): the review verb "reject with a
    /// comment" of KanbanViewKit. The review has no accept verb.
    ///
    /// - Returns: This builder, for method chaining.
    func addRejectTaskMutation() -> Self {
        add {
            Input(RejectTaskInput.self, Self.rejectTaskFields).description(SchemaDescription.rejectTaskInput)
        }
        .addMutation {
            Self.mutationField(
                MutationName.rejectTask,
                at: KanbanResolver.rejectTask,
                description: SchemaDescription.rejectTask
            )
        }
    }
}
