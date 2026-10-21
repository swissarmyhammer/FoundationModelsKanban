/// The descriptions of the change types, the `changes` subscription, and the result types of the link fields and of
/// `collectBoards` (divergence.md R17, EXTRAS-9 rule 11).
extension SchemaDescription {
    // MARK: - Change

    /// The `Change` type. The text holds only what is true on each path that gives a change: `Board.history`
    /// (``ChangeBuilder/change(of:markingUndone:)``), `Subscription.changes` (``ChangeRound``), and `undoChange` and
    /// `redoChange` (``BoardStore/reverse(_:with:at:)``). ``ChangeBuilder`` and ``ChangeRound`` hold the exact rules
    /// that put each update in a change.
    static let change = """
        One transaction: its txn, time, actor, mutations, and boards, and its node updates. Board.history and \
        Subscription.changes give the updates of the nodes of one board; undoChange and redoChange give the updates \
        of each board that they changed, those of the first board first. An update tells which node changed and \
        which tracked fields changed; read the nodes again for their new values. Transactions read together, for \
        example after a git pull, give one Change each. The updates need not match the nodes that the transaction \
        wrote: they can hold a node that it did not write, for example a task that becomes ready when its dependency \
        is done, or the board summary, and leave out a node that it wrote, for example when a later transaction read \
        with it wrote that node too.
        """

    /// The `Change.cursor` field (``Change/cursor(context:arguments:)``).
    static let changeCursor = """
        Give it as after to changes to get the changes after this one. A Change of Board.history, undoChange, or \
        redoChange gives the cursor of the first board of boards as the call reads it.
        """

    /// The `Change.added` field.
    static let changeAdded = "The id of each node that the change made or undeleted."

    /// The `Change.changed` field.
    static let changeChanged = """
        The id of each node that the change updated and did not make, undelete, or delete. Read it again for its new \
        values.
        """

    /// The `Change.removed` field.
    static let changeRemoved = "The id of each node that the change deleted."

    /// The `Change.txn` field (``UndoLog/target(of:named:by:)``).
    static let changeTxn = """
        The ULID of the transaction. Give it as txn to undoChange to reverse this change, or to redoChange to reverse \
        its undo. A collectBoards change cannot be reversed.
        """

    /// The `Change.at` field.
    static let changeAt = "The time of the transaction."

    /// The `Change.actor` field.
    static let changeActor = "The actor that made the transaction."

    /// The `Change.ops` field.
    static let changeOps = "The names of the mutations of the tool call, for example addTask."

    /// The `Change.boards` field.
    static let changeBoards = """
        The key of each board that the transaction changed, first the board whose events made this Change. In \
        Subscription.changes, a transaction of a different board gives that board first.
        """

    /// The `Change.undone` field.
    static let changeUndone = """
        True when a later undo or redo that is not undone reversed this transaction at the time that the Change was \
        made.
        """

    /// The `Change.undoes` field.
    static let changeUndoes = "The transaction that this undo or redo reverses. Null for each other transaction."

    /// The `Change.updates` field.
    static let changeUpdates = "The updates of the change that the filter keeps."

    // MARK: - Node update

    /// The `NodeUpdate` type.
    static let nodeUpdate = "The change of one node: how it changed, and each tracked field that changed."

    /// The `NodeUpdate.id` field.
    static let nodeUpdateID = "The full kanban:// URI of the node, also for a deleted node."

    /// The `NodeUpdate.type` field.
    static let nodeUpdateType = "The type of the node."

    /// The `NodeUpdate.kind` field.
    static let nodeUpdateKind = "How the node changed."

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
        The node now. A deleted node gives its tombstone, with deleted set. Null when the board of the node does \
        not have the node now.
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
        The value before the update, or null when it had no value. Null for a list field and for body.
        """

    /// The `FieldChange.after` field.
    static let fieldChangeAfter = """
        The value after the update, or null when it has no value. Null for a list field and for body.
        """

    /// The `FieldChange.added` field.
    static let fieldChangeAdded = "The items that the update added to a list field. Null for a single value."

    /// The `FieldChange.removed` field.
    static let fieldChangeRemoved = "The items that the update removed from a list field. Null for a single value."

    /// The `FieldChange.diff` field.
    static let fieldChangeDiff = """
        The unified diff from the body before the update to the body after it. Null for each field that is not \
        body. Select node { body } for the full text.
        """

    // MARK: - Subscription

    /// The `Subscription.changes` field.
    static let changesSubscription = """
        Sends a Change for each new transaction of the board: a call of this tool, or a change that a different \
        process, git pull, or a merge writes. A transaction of a different board can also give a Change, with the \
        updates of the nodes of this board. A Change with no update after the filter is not sent. The same type as \
        Board.history, so a client can read history(since:) and then subscribe with the same filter.
        """

    /// The `after` argument of `Subscription.changes` (``ChangeFeed``).
    static let changesAfter = """
        A cursor of a query or of a Change. The subscription first sends each change after it, then each new change. \
        A cursor whose changes the board no longer keeps, a cursor from before a restart, and a cursor after the \
        newest change end the subscription with RESYNC_REQUIRED: query again for a new cursor. No value sends only \
        the new changes.
        """

    // MARK: - Cursor

    /// The `Query.cursor` field (``KanbanResolver/cursor(context:arguments:)``).
    static let queryCursor = """
        The cursor of the board as this query reads it. Give it as after to changes to get each change after this \
        read.
        """

    /// The `Board.cursor` field (``BoardObject/cursor(context:arguments:)``).
    static let boardCursor = """
        The cursor of this board as this query reads it. Give it as after to changes, with this board, to get each \
        change after this read.
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
