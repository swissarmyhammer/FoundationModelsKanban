/// The descriptions of the change types, the `changes` subscription, and the result types of the link fields and of
/// `collectBoards` (divergence.md R17, EXTRAS-9 rule 11).
extension SchemaDescription {
    // MARK: - Change

    /// The `Change` type (``ChangeBuilder``).
    static let change = """
        One transaction. A transaction of this board has an update for each node that the transaction wrote, \
        and for each other live node whose tracked fields changed (see NodeUpdate.fields). In \
        Subscription.changes, a transaction of a different board gives a Change with the updates of the live \
        nodes of this board whose tracked fields changed, and of each live task whose assignee is an actor that \
        the transaction wrote, also when no field of the task changed. When one batch of Subscription.changes \
        holds several transactions, a node has one update only: in the last transaction of the batch that wrote \
        the node, else in the last transaction of the batch.
        """

    /// The `Change.txn` field (``UndoLog/target(of:named:by:)``).
    static let changeTxn = """
        The ULID of the transaction. Give it as txn to undo to reverse this change, or to redo to reverse its undo. A \
        collectBoards change cannot be reversed.
        """

    /// The `Change.at` field.
    static let changeAt = "The time of the transaction."

    /// The `Change.actor` field.
    static let changeActor = "The actor that made the transaction."

    /// The `Change.ops` field.
    static let changeOps = "The names of the mutations of the tool call, for example addTask."

    /// The `Change.boards` field.
    static let changeBoards = "The key of each board that the transaction changed, the board of this change first."

    /// The `Change.undone` field.
    static let changeUndone = "True when a later undo or redo that is not undone reverses this transaction."

    /// The `Change.undoes` field.
    static let changeUndoes = "The transaction that this undo or redo reverses. Null for each other transaction."

    /// The `Change.updates` field.
    static let changeUpdates = "The update of each node that the transaction changed and that the filter keeps."

    // MARK: - Node update

    /// The `NodeUpdate` type.
    static let nodeUpdate = "The change of one node in a transaction: how it changed, and each field that changed."

    /// The `NodeUpdate.id` field.
    static let nodeUpdateID = "The full kanban:// URI of the node, also for a deleted node."

    /// The `NodeUpdate.type` field.
    static let nodeUpdateType = "The type of the node."

    /// The `NodeUpdate.kind` field.
    static let nodeUpdateKind = "How the transaction changed the node."

    /// The `NodeUpdate.fields` field (``NodeObject/trackedFields``).
    static let nodeUpdateFields = """
        The change of each tracked field of the node that changed. The tracked fields are body and deleted, and: the \
        name, model, and summary of a board; the name and order of a column; the name, color, and avatar of an actor; \
        the name and color of a tag; the title, column, ordinal, assignees, tags, dependsOn, blockedBy, \
        unresolvedDependsOn, ready, virtualTags, progress, started, and completed of a task; the task and author of a \
        comment. Each other field is not tracked, for example created, updated, taskCount, and readyCount.
        """

    /// The `NodeUpdate.node` field.
    static let nodeUpdateNode = """
        The node now. A deleted node gives its tombstone, with deleted set. Null when the board does not have the \
        node now.
        """

    // MARK: - Field change

    /// The `FieldChange` type.
    static let fieldChange = """
        The change of one tracked field of a node. A single value gives before and after, a list gives added and \
        removed, and body gives diff. The values are the values that a query shows.
        """

    /// The `FieldChange.name` field.
    static let fieldChangeName = "The name of the field, for example column, tags, or ready."

    /// The `FieldChange.before` field.
    static let fieldChangeBefore = """
        The value before the transaction, or null when it had no value. Null for a list field and for body.
        """

    /// The `FieldChange.after` field.
    static let fieldChangeAfter = """
        The value after the transaction, or null when it has no value. Null for a list field and for body.
        """

    /// The `FieldChange.added` field.
    static let fieldChangeAdded = "The items that the transaction added to a list field. Null for a single value."

    /// The `FieldChange.removed` field.
    static let fieldChangeRemoved = "The items that the transaction removed from a list field. Null for a single value."

    /// The `FieldChange.diff` field.
    static let fieldChangeDiff = """
        The unified diff from the body before the transaction to the body after it. Null for each field that is not \
        body. Select node { body } for the full text.
        """

    // MARK: - Subscription

    /// The `Subscription.changes` field.
    static let changesSubscription = """
        Sends a Change for the transactions that change the board: a call of this tool, or a change that a \
        different process, git pull, or a merge writes. A Change with no update after the filter is not sent. The \
        same type as Board.history, so a client can read history(since:) and then subscribe with the same filter.
        """

    // MARK: - Link results

    /// The `LinkCheck` type.
    static let linkCheck = "One stored link of a task, and its class."

    /// The `LinkRepair` type.
    static let linkRepair = """
        One stored link that repairLinks or collectBoards reports, and its new target. A dangling link has no new \
        target and does not change.
        """

    // MARK: - Collect results

    /// The `CollectBoardsResult` type.
    static let collectResult = "The result of collectBoards: the target, the sources, the merges, and the links."

    /// The `CollectedBoard` type.
    static let collectedBoard = "One source board of collectBoards."

    /// The `SlugMerge` type.
    static let slugMerge = "One column, tag, or actor that more than one board has. It is one node in the target now."

    /// The `FieldConflict` type.
    static let fieldConflict = """
        One field of a node that two or more boards set to different values. The winner is the value after the \
        merge of the events of all the boards.
        """
}
