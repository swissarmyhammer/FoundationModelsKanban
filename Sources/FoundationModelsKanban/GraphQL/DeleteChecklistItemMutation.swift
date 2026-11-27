import Foundation
import FoundationModelsExtras
import Graphiti
import GraphQL

// MARK: - Names

extension MutationName {
    /// The mutation that removes one checklist item from the body of a task (divergence.md §32).
    static let deleteChecklistItem = "deleteChecklistItem"
}

// MARK: - Arguments

/// The `input` object of `deleteChecklistItem` (divergence.md §32): the task, the item, and the board of a short task
/// ref.
private struct DeleteChecklistItemInput: TaskReferenceInput, TargetBoardInput {
    /// The task: a full URI or a short form (plan.md §3.2).
    let id: NodeID

    /// The item: an index from 0, or the text of the item (``ChecklistItemMatch``). The GraphQL type is `ID`, so an
    /// index can be an int literal, for example `item: 2`, or a string, for example `item: "2"`.
    let item: NodeID

    /// The board of a short task ref: a board key, a repo directory name, or a path, or `nil` for the current board
    /// (plan.md §6.6). A full URI in ``id`` names its own board, and this field is ignored.
    let board: String?
}

// MARK: - Resolver

extension KanbanResolver {
    /// Resolves `Mutation.deleteChecklistItem`: removes one checklist item from the body of a task (divergence.md
    /// §32). The call writes the body diff of `updateTask`, so undo gives the line back.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The task, the item, and the board.
    /// - Returns: The task after the change. The GraphQL field is nullable, so that an error gives `null` for this
    ///   field only.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the id.
    ///   ``KanbanError/checklistItemNotFound(task:item:items:field:)`` and
    ///   ``KanbanError/ambiguousChecklistItem(task:item:matches:field:)`` when the item ref does not name one item.
    ///   The errors of ``KanbanContext/changeTaskBody(named:of:inBoard:_:)``.
    fileprivate func deleteChecklistItem(
        context: KanbanContext,
        arguments: InputArguments<DeleteChecklistItemInput>
    ) async throws -> TaskObject? {
        let input = arguments.input
        let name = MutationName.deleteChecklistItem
        return try await context.changeTaskBody(named: name, of: input.id, inBoard: input.board) { body in
            let edited = try ChecklistItemDeletion.body(body, removing: input.item.text, ofTask: input.id.text)
            return (edited, [])
        }
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the `deleteChecklistItem` mutation and its `input` type (divergence.md §32).
    ///
    /// - Returns: This builder, for method chaining.
    func addChecklistItemDeletionMutation() -> Self {
        add {
            Input(DeleteChecklistItemInput.self) {
                Self.makeTaskReferenceField()
                InputField("item", at: \.item).description(SchemaDescription.checklistItemReference)
                Self.makeTargetBoardField()
            }
            .description(SchemaDescription.deleteChecklistItemInput)
        }
        .addMutation {
            Self.mutationField(
                MutationName.deleteChecklistItem,
                at: KanbanResolver.deleteChecklistItem,
                description: SchemaDescription.deleteChecklistItem
            )
        }
    }
}
