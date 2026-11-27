import Foundation
import FoundationModelsExtras
import Graphiti
import GraphQL

// MARK: - Names

extension MutationName {
    /// The mutation that sets the state of one checklist item of the body of a task, and can change its text
    /// (divergence.md §30).
    static let updateChecklistItem = "updateChecklistItem"
}

// MARK: - Arguments

/// The `input` object of `updateChecklistItem` (divergence.md §30): the task, the item, the new state, the new text,
/// and the board of a short task ref. A state or a text that is not set does not change.
private struct UpdateChecklistItemInput: TaskReferenceInput, TargetBoardInput {
    /// The task: a full URI or a short form (plan.md §3.2).
    let id: NodeID

    /// The item: an index from 0, or the text of the item (``ChecklistItemMatch``). The GraphQL type is `ID`, so an
    /// index can be an int literal, for example `item: 2`, or a string, for example `item: "2"`.
    let item: NodeID

    /// The new state of the item, or `nil` for no change of the state.
    let checked: Bool?

    /// The new text of the item, or `nil` for no change of the text.
    let text: String?

    /// The board of a short task ref: a board key, a repo directory name, or a path, or `nil` for the current board
    /// (plan.md §6.6). A full URI in ``id`` names its own board, and this field is ignored.
    let board: String?
}

// MARK: - Change

/// The rules of the body change of `updateChecklistItem` (divergence.md §30).
enum ChecklistItemUpdate {
    /// The code of the warning for an input with no `checked` and no `text`.
    static let nothingToChangeWarningCode = "NOTHING_TO_CHANGE"

    /// The warning for an input with no `checked` and no `text`: the call writes nothing.
    static let nothingToChangeWarning = ResponseWarning(
        message: "The input of `\(MutationName.updateChecklistItem)` gives no `checked` and no `text`, so the item "
            + "does not change. Give checked: true to check the item, checked: false to uncheck it, or text to change "
            + "its text.",
        code: nothingToChangeWarningCode
    )

    /// The text between two lines of a new item text: an item is one line.
    private static let lineJoiner = " "

    /// Gives the body after the change of one checklist item. Each other line stays byte for byte.
    ///
    /// - Parameters:
    ///   - body: The current body of the task.
    ///   - reference: The item ref as the call wrote it.
    ///   - isChecked: The new state, or `nil` for no change of the state.
    ///   - text: The new text, or `nil` for no change of the text.
    ///   - task: The task ref as the call wrote it, for an error.
    /// - Returns: The new body. It is the current body when the item already has the state and the text.
    /// - Throws: The errors of ``ChecklistItemMatch/item(for:among:ofTask:)``.
    static func body(
        _ body: String,
        changing reference: String,
        checking isChecked: Bool?,
        text: String?,
        ofTask task: String
    ) throws(KanbanError) -> String {
        let lines = BodyLines.lines(of: body)
        let items = ChecklistItem.items(inLines: lines)
        let item = try ChecklistItemMatch.item(for: reference, among: items, ofTask: task)
        let edited = item.editedLine(checking: isChecked, text: text.map(oneLine(of:)))
        let edits = lines.indices.map { line in line == item.line ? edited : nil }
        return BodyLines.body(joining: lines, with: edits)
    }

    /// Gives a new item text as one line: the lines of the text, each without white space around it, joined with one
    /// space. Thus a line break in the text never makes a new line in the body.
    ///
    /// - Parameter text: The new text as the call wrote it.
    /// - Returns: The text of one line.
    private static func oneLine(of text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .map { line in line.trimmingCharacters(in: .whitespaces) }
            .filter { line in !line.isEmpty }
            .joined(separator: lineJoiner)
    }
}

// MARK: - Resolver

extension KanbanResolver {
    /// Resolves `Mutation.updateChecklistItem`: sets the state of one checklist item of the body of a task, and can
    /// change its text (divergence.md §30). The call writes the body diff of `updateTask`, so undo, the change stream,
    /// the tag markers, and the timeline work with it. A state and a text that the item already has write nothing. An
    /// input with no `checked` and no `text` writes nothing, and gives a warning.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The task, the item, the new state, the new text, and the board.
    /// - Returns: The task after the change. The GraphQL field is nullable, so that an error gives `null` for this
    ///   field only.
    /// - Throws: ``KanbanError/notFound(type:reference:)`` when no live task has the id.
    ///   ``KanbanError/checklistItemNotFound(task:item:items:)`` and
    ///   ``KanbanError/ambiguousChecklistItem(task:item:matches:)`` when the item ref does not name one item. The
    ///   errors of ``WorkingCopy/write(_:toTask:inBoard:at:)``.
    fileprivate func updateChecklistItem(
        context: KanbanContext,
        arguments: InputArguments<UpdateChecklistItemInput>
    ) async throws -> TaskObject? {
        let input = arguments.input
        let board = MutationBoard.holding(input.id, orNamed: input.board)
        let name = MutationName.updateChecklistItem
        let task = try await context.changeTask(named: name, on: board) { work, resolver, time in
            let ref = try resolver.nodeRef(for: input.id, ofType: .task)
            let body = try ChecklistItemUpdate.body(
                work.graph.body(of: ref),
                changing: input.item.text,
                checking: input.checked,
                text: input.text,
                ofTask: input.id.text
            )
            let change = TaskChange(values: [:], body: .changed(body), edges: [:])
            let warnings = try work.write(change, toTask: ref, inBoard: resolver.boardKey, at: time)
            return TaskWrite(ref: ref, warnings: warnings)
        }
        if input.checked == nil, input.text == nil {
            await context.warnings.add(contentsOf: [ChecklistItemUpdate.nothingToChangeWarning])
        }
        return task
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the `updateChecklistItem` mutation and its `input` type (divergence.md §30).
    ///
    /// - Returns: This builder, for method chaining.
    func addChecklistItemMutation() -> Self {
        add {
            Input(UpdateChecklistItemInput.self) {
                Self.makeTaskReferenceField()
                InputField("item", at: \.item).description(SchemaDescription.checklistItemReference)
                InputField("checked", at: \.checked).description(SchemaDescription.checklistItemChecked)
                InputField("text", at: \.text).description(SchemaDescription.checklistItemText)
                Self.makeTargetBoardField()
            }
            .description(SchemaDescription.updateChecklistItemInput)
        }
        .addMutation {
            Self.mutationField(
                MutationName.updateChecklistItem,
                at: KanbanResolver.updateChecklistItem,
                description: SchemaDescription.updateChecklistItem
            )
        }
    }
}
