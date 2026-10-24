/// The descriptions of the mutations of the public schema, of their `input` arguments, and of the `input` types and
/// their fields (EXTRAS-9 rule 11: each part of the schema has a description). The texts tell only the behavior that
/// the code has now (plan.md §4.2).
extension SchemaDescription {
    // MARK: - Texts of one form

    /// Gives the description of a mutation that makes a node a tombstone.
    ///
    /// - Parameter type: The node type.
    /// - Returns: The description.
    private static func tombstoneText(of type: PatchNodeType) -> String {
        "Makes the \(noun(of: type)) a tombstone."
    }

    /// Gives the description of a mutation that makes a tombstoned node live again.
    ///
    /// - Parameter type: The node type.
    /// - Returns: The description.
    private static func undeleteText(of type: PatchNodeType) -> String {
        let name = noun(of: type)
        return "Makes a tombstoned \(name) live again. A live \(name) does not change."
    }

    /// Gives the description of the `id` field of an `input` type that makes a node with a slug id (plan.md §3.2,
    /// ``RefResolver/newNodeKey(for:ofType:)``).
    ///
    /// - Parameter type: The node type.
    /// - Returns: The description.
    private static func newIDText(of type: PatchNodeType) -> String {
        let name = noun(of: type)
        return """
            The id of the new \(name): a full URI, the stored form \(name)/<id>, or a name. The slug of the name or of \
            the <id> part is the id. No id gives the slug of the name field.
            """
    }

    /// Gives the description of a field that names a column or an actor that the board has (``RefResolver``): a full
    /// URI, the stored form `<type>/<slug>`, the slug, or a name that gives the slug.
    ///
    /// - Parameter type: The node type.
    /// - Returns: The description.
    private static func slugReferenceText(of type: PatchNodeType) -> String {
        let name = noun(of: type)
        return "The \(name): a full URI, the stored form \(name)/<slug>, the slug, or a name that gives the slug."
    }

    /// The forms of a list of refs to actors (``RefResolver``), for the `assignees` field of a task input.
    private static let actorForms = "full URIs, stored forms actor/<slug>, slugs, or names that give the slug"

    /// Gives the noun of a node type in a description.
    ///
    /// - Parameter type: The node type.
    /// - Returns: The GraphQL name of the type in lowercase, for example `column`.
    private static func noun(of type: PatchNodeType) -> String {
        type.rawValue.lowercased()
    }

    // MARK: - Input arguments

    /// The `input` argument of a mutation (EXTRAS-9 rule 7). The argument is required also when its type has no
    /// required field.
    static let mutationInput = """
        The input object of the call. Its type tells what each field does. The input is required: a call that sets no \
        field sends input: {}.
        """

    /// Gives the description of the `input` type of a mutation whose type has only the fields of the mutation, for
    /// example `AssignTaskInput`.
    ///
    /// - Parameter mutation: The name of the mutation, from ``MutationName``.
    /// - Returns: The description, for example "The fields of assignTask.".
    static func mutationFields(of mutation: String) -> String {
        "The fields of \(mutation)."
    }

    // MARK: - Board mutations

    /// The `Mutation.initBoard` field.
    static let initBoard = """
        Makes the board with the default columns todo, doing, review, and done. On a board that exists, it changes \
        only the given fields that differ, and adds no column.
        """

    /// The `Mutation.updateBoard` field.
    static let updateBoard = "Changes the name, the model, or the body of the board."

    // MARK: - Column and actor mutations

    /// The `Mutation.addColumn` field.
    static let addColumn = "Makes a column."

    /// The `Mutation.updateColumn` field.
    static let updateColumn = "Changes the name, the order, or the body of a column."

    /// The `Mutation.deleteColumn` field.
    static let deleteColumn = tombstoneText(of: .column) + " A column with live tasks gives COLUMN_NOT_EMPTY."

    /// The `Mutation.undeleteColumn` field.
    static let undeleteColumn = undeleteText(of: .column)

    /// The `Mutation.addActor` field.
    static let addActor = "Makes an actor. The input gives an id, a name, or both."

    /// The `Mutation.updateActor` field.
    static let updateActor = "Changes the name, the color, the avatar, or the body of an actor."

    /// The `Mutation.deleteActor` field.
    static let deleteActor = tombstoneText(of: .actor)

    /// The `Mutation.undeleteActor` field.
    static let undeleteActor = undeleteText(of: .actor)

    // MARK: - Task mutations

    /// The `Mutation.addTask` field.
    static let addTask = """
        Makes a task. The task goes to the end of its column, unless a priority moves it to the top. An ordinal gives \
        the place when the priority makes no move. A priority that moves the task wins over the ordinal.
        """

    /// The `Mutation.updateTask` field.
    static let updateTask = """
        Changes the given fields of a task. A list replaces the old list. A column moves the task to the end of that \
        column, or to the top when the priority moves it there. An ifVersion that is not the current version of the \
        task gives STALE_WRITE, and the call writes nothing.
        """

    /// The `Mutation.moveTask` field.
    static let moveTask = """
        Moves a task to a column and to a place in that column. No place puts the task at the end of the column. A \
        board field that names a different board moves the task to that board.
        """

    /// The `Mutation.completeTask` field.
    static let completeTask = "Moves a task to the end of the terminal column."

    /// The `Mutation.assignTask` field.
    static let assignTask = "Adds an actor to the assignees of a task."

    /// The `Mutation.unassignTask` field.
    static let unassignTask = "Removes an actor from the assignees of a task."

    /// The `Mutation.tagTask` field.
    static let tagTask = "Adds tags to a task. A tag that the board does not have is made."

    /// The `Mutation.untagTask` field.
    static let untagTask = "Removes tags from a task: the tag edges, and the #markers of the body."

    /// The `Mutation.deleteTask` field.
    static let deleteTask = tombstoneText(of: .task)

    /// The `Mutation.undeleteTask` field.
    static let undeleteTask = undeleteText(of: .task)

    /// The rule of a list mutation of tasks (divergence.md §20).
    private static let taskListRule = """
        The call is one transaction, so one undoChange reverses it. When a ref names no task, the call writes \
        nothing, and the error names each such ref.
        """

    /// The `Mutation.moveTasks` field (divergence.md §20).
    static let moveTasks = """
        Moves a list of tasks to a column, as one block at one place in that column, in the order of the list. No \
        place puts the tasks at the end of the column. \(taskListRule)
        """

    /// The `Mutation.deleteTasks` field (divergence.md §20).
    static let deleteTasks = "Makes each task of a list a tombstone. \(taskListRule)"

    /// The `Mutation.undeleteTasks` field (divergence.md §20).
    static let undeleteTasks = """
        Makes each tombstoned task of a list live again. A live task does not change. \(taskListRule)
        """

    /// The `Mutation.rejectTask` field (divergence.md §21).
    static let rejectTask = """
        Sends a task back with a comment to the agent: the review verb "reject with a comment". The call adds the \
        comment to the task, with the session actor as the author, and moves the task, in one transaction, so one \
        undoChange reverses both. No column moves the task to the column before the column where it shows, for \
        example from done to review. No place puts the task at the end of the column.
        """

    /// The `Mutation.copyTask` field.
    static let copyTask = """
        Copies a task to a column and to a place in that column, in the same board or in a different board. No board \
        field copies the task in its board.
        """

    // MARK: - Comment mutations

    /// The `Mutation.addComment` field.
    static let addComment = "Adds a comment to a task."

    /// The `Mutation.updateComment` field.
    static let updateComment = "Changes the body of a comment."

    /// The `Mutation.deleteComment` field.
    static let deleteComment = tombstoneText(of: .comment)

    /// The `Mutation.undeleteComment` field.
    static let undeleteComment = undeleteText(of: .comment)

    // MARK: - Tag mutations

    /// The `Mutation.addTag` field.
    static let addTag = """
        Makes a tag. When the board has a tag with the slug, the call writes no name, color, or body: it follows the \
        rename redirect, gives the tag at the end of the rename chain, and makes that tag live again when it is a \
        tombstone.
        """

    /// The `Mutation.updateTag` field.
    static let updateTag = """
        Changes the name, the color, or the body of a tag. A name with a new slug renames the tag, the same as \
        renameTag.
        """

    /// The `Mutation.deleteTag` field.
    static let deleteTag = tombstoneText(of: .tag)

    /// The `Mutation.undeleteTag` field.
    static let undeleteTag = undeleteText(of: .tag)

    /// The `Mutation.renameTag` field.
    static let renameTag = """
        Renames a tag. The old slug redirects to the new slug, so each task with the old tag shows the new tag. A new \
        slug that a tag has already merges the two tags.
        """

    // MARK: - Undo mutations

    /// The `Mutation.undoChange` field.
    static let undoChange = """
        Reverses a transaction: it writes the inverse of each change of the transaction. No txn reverses the newest \
        transaction of the session actor that is not undone, is not an undo or a redo, and comes after the newest \
        collectBoards transaction. A collectBoards transaction cannot be reversed. A later change that conflicts with \
        the inverse gives UNDO_CONFLICT, unless force is true.
        """

    /// The `Mutation.redoChange` field.
    static let redoChange = """
        Reverses the undo of a transaction. No txn reverses the newest undo of the session actor that is not undone, \
        is not a redo, and comes after the newest collectBoards transaction.
        """

    // MARK: - Shared input fields

    /// The `body` field of an `input` type that makes a node.
    static let newNodeBody = "The Markdown body: the full text. No body gives an empty body."

    /// The `body` field of an `input` type that changes a node.
    static let changedBody = "The new Markdown body: the full text. The call writes the diff from the current body."

    /// The rule of `null` on a required text field of an `input` type that changes a node (``IgnoredNull``).
    static let nullIgnored = "Null gives no change and a warning."

    /// The rule of a tag ref that is a slug that a rename redirects (plan.md §6.2).
    static let renamedSlugRule = "A renamed slug names the tag that it redirects to."

    /// The rule of the place fields of `MoveTaskInput` and `CopyTaskInput`.
    static let placementRule = "Give at most one of ordinal, before, and after."

    /// The rule of a `before` or `after` ref that names no live task (divergence.md P1).
    static let missingNeighbor = "A ref that names no live task puts the task at the end of the column, with a warning."

    /// The `name` field of an `input` type that changes a column or an actor.
    static let changedName = "The new name. \(nullIgnored)"

    /// The `color` field of an `input` type that changes an actor or a tag.
    static let changedColor = "The new color."

    /// The `id` field of an `input` type that names a task.
    static let taskReference = "The task: a full URI or a short form."

    /// The `id` field of an `input` type that names a comment.
    static let commentReference = "The comment: a full URI or a short form."

    /// The `actor` field of `AssignTaskInput`, and the `id` field of `UpdateActorInput`.
    static let actorReference = slugReferenceText(of: .actor)

    /// The tag forms of a list of tags in an `input` type.
    static let tagForms = "Each tag is a tag name, a slug, the stored form tag/<slug>, or a tag URI."

    // MARK: - Board input

    /// Gives the description of the `input` type of a board mutation: `InitBoardInput` or `UpdateBoardInput`.
    ///
    /// - Parameter mutation: The name of the mutation: `initBoard` or `updateBoard`.
    /// - Returns: The description.
    static func boardInput(of mutation: String) -> String {
        "\(mutationFields(of: mutation)) A name, model, or body that is not set does not change, and null clears it."
    }

    /// The `name` field of `InitBoardInput` and `UpdateBoardInput`.
    static let boardName = "The name of the board."

    // MARK: - Column and actor inputs

    /// The `AddColumnInput` type.
    static let addColumnInput = "The fields of addColumn."

    /// The `id` field of `AddColumnInput`.
    static let newColumnID = newIDText(of: .column)

    /// The `name` field of `AddColumnInput`.
    static let columnName = "The name of the column."

    /// The `order` field of `AddColumnInput`.
    static let columnOrder = "The sort key of the column. No order puts the column after the terminal column."

    /// The `UpdateColumnInput` type.
    static let updateColumnInput = """
        The fields of updateColumn. A field that is not set does not change. Null for the order gives the order 0; \
        null clears the body; null for the name gives no change and a warning.
        """

    /// The `id` field of `UpdateColumnInput`.
    static let columnReference = slugReferenceText(of: .column)

    /// The `order` field of `UpdateColumnInput`.
    static let changedColumnOrder = "The new sort key of the column."

    /// The `AddActorInput` type.
    static let addActorInput = "The fields of addActor. The input gives an id, a name, or both."

    /// The `id` field of `AddActorInput`.
    static let newActorID = newIDText(of: .actor)

    /// The `color` field of `AddActorInput`.
    static let actorColor = "The color of the actor. No color gives an actor with no color."

    /// The `ensure` field of `AddActorInput` (divergence.md Q16).
    static let actorEnsure = """
        True gives the actor with the id when the board has it: a tombstoned actor is live again, and each given \
        name, color, and avatar that differs is written. Else an actor with the id gives DUPLICATE_ID.
        """

    /// The `UpdateActorInput` type.
    static let updateActorInput = """
        The fields of updateActor. A field that is not set does not change. Null clears the color, the avatar, or the \
        body; null for the name gives no change and a warning.
        """

    /// Gives the description of the `input` type of a mutation that names one node and has no other field: the type of
    /// ``NodeReferenceInput``, for example `DeleteTaskInput`.
    ///
    /// - Parameter mutation: The name of the mutation, for example `deleteTask`.
    /// - Returns: The description, for example "The node of deleteTask.".
    static func nodeReferenceInput(of mutation: String) -> String {
        "The node of \(mutation)."
    }

    /// The `id` field of the `input` type of ``NodeReferenceInput``.
    static let nodeReference = "The node: a full URI or a short form."

    // MARK: - Task inputs

    /// The `AddTaskInput` type.
    static let addTaskInput = "The fields of addTask."

    /// The `title` field of `AddTaskInput`.
    static let taskTitle = "The title of the task."

    /// The `column` field of `AddTaskInput`.
    static let newTaskColumn = "The column of the task. No column gives the column with the lowest order."

    /// The `ordinal` field of `AddTaskInput`.
    static let newTaskOrdinal = """
        The place of the task in its column, as a fractional index. No ordinal puts the task at the end of the \
        column, unless the priority moves it. A priority that moves the task wins over the ordinal.
        """

    /// The `assignees` field of `AddTaskInput`.
    static let newTaskAssignees = """
        The actors of the task: \(actorForms). No list gives the session actor, when it is a live actor of the board \
        before the call.
        """

    /// The `tags` field of `AddTaskInput`.
    static let newTaskTags = "The tags of the task. \(tagForms) A tag that the board does not have is made."

    /// The `UpdateTaskInput` type.
    static let updateTaskInput = """
        The fields of updateTask. A field that is not set does not change. Null clears the body, the assignees, the \
        tags, or dependsOn; null for the title gives no change and a warning; null for the column or the priority is \
        the same as no value. A list replaces the old list.
        """

    /// The `title` field of `UpdateTaskInput`.
    static let changedTaskTitle = "The new title. \(nullIgnored)"

    /// The `assignees` field of `UpdateTaskInput`.
    static let changedTaskAssignees = "The new actors of the task: \(actorForms)."

    /// The `tags` field of `UpdateTaskInput`.
    static let changedTaskTags = "The new tags of the task. \(tagForms)"

    /// The `MoveTaskInput` type.
    static let moveTaskInput = "The fields of moveTask. \(placementRule)"

    /// The `CopyTaskInput` type.
    static let copyTaskInput = "The fields of copyTask. \(placementRule)"

    /// The `column` field of `MoveTaskInput` and `CopyTaskInput`.
    static let placementColumn = """
        The column: a full URI, the slug, or a name. A slug that no column has makes the column. No column gives the \
        column where the task shows. On a different board, no column gives the live column with the same slug, else \
        the first column.
        """

    /// The descriptions of the place fields `ordinal`, `before`, and `after` of the `input` type of a move or a copy.
    struct PlaceFields: Sendable {
        /// The description of the `ordinal` field.
        let ordinal: String

        /// The description of the `before` field (divergence.md P1).
        let before: String

        /// The description of the `after` field (divergence.md P1).
        let after: String

        /// The place fields of `MoveTaskInput` and `CopyTaskInput`: the place of one task.
        static let oneTask = PlaceFields(
            ordinal: """
                The place in the column, as a fractional index. No ordinal, before, or after puts the task at the end \
                of the column.
                """,
            before: "The task to put this task before: a full URI or a short form. \(missingNeighbor)",
            after: "The task to put this task after: a full URI or a short form. \(missingNeighbor)"
        )

        /// The place fields of `MoveTasksInput`: the place of the block of tasks (divergence.md §20).
        static let taskBlock = PlaceFields(
            ordinal: """
                The place of the first task in the column, as a fractional index. Each next task goes after the task \
                before it. No ordinal, before, or after puts the tasks at the end of the column.
                """,
            before: "The task to put the tasks before: a full URI or a short form. \(missingNeighbor)",
            after: "The task to put the tasks after: a full URI or a short form. \(missingNeighbor)"
        )
    }

    /// The `MoveTasksInput` type (divergence.md §20).
    static let moveTasksInput = "The fields of moveTasks. \(placementRule)"

    /// The `column` field of `MoveTasksInput` (divergence.md §20).
    static let taskBlockColumn = """
        The column: a full URI, the slug, or a name. A slug that no column has makes the column. No column gives the \
        column where the first task of the list shows.
        """

    /// The `id` field of the `input` type of a list mutation of tasks (divergence.md §20).
    static let taskListReference = """
        The tasks: a list of full URIs or short forms, or one of them. A JSON array in one string is also a list. The \
        result gives each task one time, in the order of the list. When a ref names no task, the call writes nothing, \
        and the error names each such ref.
        """

    /// Gives the description of the `input` type of a list mutation of tasks that names only the tasks.
    ///
    /// - Parameter mutation: The name of the mutation, for example `deleteTasks`.
    /// - Returns: The description, for example "The tasks of deleteTasks.".
    static func taskListInput(of mutation: String) -> String {
        "The tasks of \(mutation)."
    }

    /// The `RejectTaskInput` type (divergence.md §21).
    static let rejectTaskInput = "The fields of rejectTask. \(placementRule)"

    /// The `comment` field of `RejectTaskInput` (divergence.md §21).
    static let rejectComment = """
        The Markdown body of the comment to the agent: why the task goes back. A comment that is empty or holds only \
        white space gives EMPTY_COMMENT, and the call writes nothing.
        """

    /// The `column` field of `RejectTaskInput` (divergence.md §21).
    static let rejectColumn = """
        The column: a full URI, the slug, or a name. A slug that no column has makes the column. No column gives the \
        column before the column where the task shows, in board order. For a task in the first column, no column \
        gives NO_PREVIOUS_COLUMN, and the call writes nothing.
        """

    /// The `tags` field of `TagTaskInput` and `UntagTaskInput`.
    static let tagTaskTags = "The tags to add or to remove. \(tagForms)"

    // MARK: - Comment inputs

    /// The `AddCommentInput` type.
    static let addCommentInput = "The fields of addComment."

    /// The `task` field of `AddCommentInput`.
    static let newCommentTask = "The task of the comment: a full URI or a short form."

    /// The `body` field of `AddCommentInput`.
    static let newCommentBody = "The Markdown body of the comment: the full text."

    /// The `actor` field of `AddCommentInput`.
    static let commentAuthor = """
        The author of the comment: a full URI, a slug, or a name. A slug or a name that no actor has makes the actor. \
        No actor gives the session actor.
        """

    /// The `UpdateCommentInput` type.
    static let updateCommentInput = """
        The fields of updateComment. A body that is not set does not change, and null clears it.
        """

    /// Gives the description of the `input` type of a comment mutation that names one comment: the type of
    /// ``CommentReferenceInput``, `DeleteCommentInput` or `UndeleteCommentInput`.
    ///
    /// - Parameter mutation: The name of the mutation: `deleteComment` or `undeleteComment`.
    /// - Returns: The description, for example "The comment of deleteComment.".
    static func commentReferenceInput(of mutation: String) -> String {
        "The comment of \(mutation)."
    }

    // MARK: - Tag inputs

    /// The `AddTagInput` type.
    static let addTagInput = "The fields of addTag. The input gives an id, a name, or both."

    /// The `id` field of `AddTagInput`.
    static let newTagID = newIDText(of: .tag)

    /// The `name` field of `AddTagInput` (``TagName/init(normalizing:)``).
    static let newTagName = """
        The tag name. The tag name rule removes NUL and the white space at the two ends, and changes each run of white \
        space to _. No name gives the id after this rule: a short form, or the <id> part of a full URI or of the \
        stored form tag/<id>.
        """

    /// The `color` field of `AddTagInput`.
    static let newTagColor = "The color of the tag. No color gives the auto color of the slug."

    /// The `UpdateTagInput` type.
    static let updateTagInput = """
        The fields of updateTag. A field that is not set does not change. Null clears the color or the body; null \
        for the name gives no change and a warning.
        """

    /// The forms of a ref to one tag (``RefResolver``).
    private static let tagReferenceForms = "a full URI, the stored form tag/<slug>, the slug, or a tag name"

    /// The `id` field of `UpdateTagInput`.
    static let tagReference = "The tag: \(tagReferenceForms). \(renamedSlugRule)"

    /// The `name` field of `UpdateTagInput` (divergence.md C4).
    static let changedTagName = """
        The new tag name. A name with the same slug changes only the display name, and a name with a new slug renames \
        the tag. \(nullIgnored)
        """

    /// The `RenameTagInput` type.
    static let renameTagInput = "The fields of renameTag."

    /// The `from` field of `RenameTagInput`.
    static let renameFrom = """
        The tag to rename: \(tagReferenceForms). \(renamedSlugRule) A full URI names the board, and the board field is \
        then ignored.
        """

    /// The `to` field of `RenameTagInput`.
    static let renameTo = "The new tag name."

    // MARK: - Undo inputs

    /// The `txn` field of `UndoChangeInput` and `RedoChangeInput`.
    static let undoTransaction = """
        For undoChange, the transaction to reverse. For redoChange, the original transaction whose undo to reverse. \
        No txn gives the newest target of the session actor after the newest collectBoards transaction: for \
        undoChange, a transaction that is not undone and is not an undo or a redo; for redoChange, an undo that is \
        not undone and is not a redo.
        """

    /// The `force` field of `UndoChangeInput` and `RedoChangeInput`.
    static let undoForce = "True writes the inverse also when a later change conflicts with it."
}
