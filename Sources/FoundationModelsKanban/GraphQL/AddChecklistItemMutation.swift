import Foundation
import FoundationModelsExtras
import Graphiti
import GraphQL

// MARK: - Names

extension MutationName {
    /// The mutation that adds one checklist item to the body of a task (divergence.md §31).
    static let addChecklistItem = "addChecklistItem"
}

// MARK: - Arguments

/// The `input` object of `addChecklistItem` (divergence.md §31): the task, the text and the state of the new item,
/// the item to put it before or after, and the board of a short task ref.
private struct AddChecklistItemInput: TaskReferenceInput, TargetBoardInput {
    /// The task: a full URI or a short form (plan.md §3.2).
    let id: NodeID

    /// The text of the new item, as the call wrote it (``ChecklistItemDraft/init(reading:checked:)``).
    let text: String

    /// The state of the new item, or `nil` for the state of the box in ``text``, or an open box.
    let checked: Bool?

    /// The item to put the new item before: an index from 0, or the text of the item (``ChecklistItemMatch``). The
    /// GraphQL type is `ID`, so an index can be an int literal or a string. `nil` for none.
    let before: NodeID?

    /// The item to put the new item after, in the same forms as ``before``. `nil` for none.
    let after: NodeID?

    /// The board of a short task ref: a board key, a repo directory name, or a path, or `nil` for the current board
    /// (plan.md §6.6). A full URI in ``id`` names its own board, and this field is ignored.
    let board: String?
}

// MARK: - Warning

extension ChecklistItemAddition {
    /// The code of the warning for a new item whose text another item already has.
    static let sameTextWarningCode = "DUPLICATE_ITEM_TEXT"

    /// Gives the warning for a new item whose text another item already has: a later text ref of the item is
    /// ambiguous.
    ///
    /// - Parameter task: The task ref as the call wrote it.
    /// - Returns: One warning when ``sameText`` has an item, else no warning.
    func sameTextWarnings(ofTask task: String) -> [ResponseWarning] {
        guard !sameText.isEmpty else {
            return []
        }
        let labels = sameText.map(\.label).joined(separator: KanbanError.listSeparator)
        let message = "The call added the new item at index \(index) of the task \"\(task)\", and other items have the "
            + "same text: \(labels). A text ref of one of these items matches more than one item and gives "
            + "AMBIGUOUS_ITEM, so name the item by its index."
        return [ResponseWarning(message: message, code: Self.sameTextWarningCode)]
    }
}

// MARK: - Resolver

extension KanbanResolver {
    /// Resolves `Mutation.addChecklistItem`: adds one checklist item to the body of a task (divergence.md §31). The
    /// call writes the body diff of `updateTask`, so undo, the change stream, the tag markers, and the timeline work
    /// with it. A text that another item already has gives a warning.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The task, the text, the state, the place, and the board.
    /// - Returns: The task after the change. The GraphQL field is nullable, so that an error gives `null` for this
    ///   field only.
    /// - Throws: The errors of ``ChecklistItemDraft/init(reading:checked:)`` when the text is not one item.
    ///   ``KanbanError/notFound(type:reference:)`` when no live task has the id. The errors of
    ///   ``ChecklistItemAddition/init(adding:to:before:after:ofTask:)`` when the place is not clear. The errors of
    ///   ``WorkingCopy/write(_:toTask:inBoard:at:)``.
    fileprivate func addChecklistItem(
        context: KanbanContext,
        arguments: InputArguments<AddChecklistItemInput>
    ) async throws -> TaskObject? {
        let input = arguments.input
        let draft = try ChecklistItemDraft(reading: input.text, checked: input.checked)
        let board = MutationBoard.holding(input.id, orNamed: input.board)
        return try await context.changeTask(named: MutationName.addChecklistItem, on: board) { work, resolver, time in
            let ref = try resolver.nodeRef(for: input.id, ofType: .task)
            let addition = try ChecklistItemAddition(
                adding: draft,
                to: work.graph.body(of: ref),
                before: input.before?.text,
                after: input.after?.text,
                ofTask: input.id.text
            )
            let change = TaskChange(values: [:], body: .changed(addition.body), edges: [:])
            let warnings = try work.write(change, toTask: ref, inBoard: resolver.boardKey, at: time)
            return TaskWrite(ref: ref, warnings: warnings + addition.sameTextWarnings(ofTask: input.id.text))
        }
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the `addChecklistItem` mutation and its `input` type (divergence.md §31).
    ///
    /// - Returns: This builder, for method chaining.
    func addChecklistItemAdditionMutation() -> Self {
        add {
            Input(AddChecklistItemInput.self) {
                Self.makeTaskReferenceField()
                InputField("text", at: \.text).description(SchemaDescription.newChecklistItemText)
                InputField("checked", at: \.checked).description(SchemaDescription.newChecklistItemChecked)
                InputField(ChecklistItemAddition.beforeField, at: \.before)
                    .description(SchemaDescription.newChecklistItemBefore)
                InputField(ChecklistItemAddition.afterField, at: \.after)
                    .description(SchemaDescription.newChecklistItemAfter)
                Self.makeTargetBoardField()
            }
            .description(SchemaDescription.addChecklistItemInput)
        }
        .addMutation {
            Self.mutationField(
                MutationName.addChecklistItem,
                at: KanbanResolver.addChecklistItem,
                description: SchemaDescription.addChecklistItem
            )
        }
    }
}
