/// The descriptions of `Task.timeline`, the `TimelineEntry` type, and the `TimelineKind` enum (divergence.md §23,
/// EXTRAS-9 rule 11).
extension SchemaDescription {
    // MARK: - Task.timeline

    /// The `Task.timeline` field (``TaskObject/timeline(context:arguments:)``).
    static let taskTimeline = """
        The history of the task, newest first: each column move, each change of a stored field (body, deleted, \
        title, assignees, tags, dependsOn), and each change of a comment of the task, with the time, the actor, and \
        the txn. It reads only the logs of the task and of its comments. A change of this call is not in the list.
        """

    /// The `first` argument of `Task.timeline`.
    static let timelineFirst = pageSize(of: "entries")

    /// The `after` argument of `Task.timeline` (``TimelineCursor/init(parsing:)``).
    static let timelineAfter = """
        The cursor of an entry, or the txn of a transaction, for example Change.txn. The page starts after it. No \
        value starts the page at the newest entry.
        """

    // MARK: - TimelineEntry

    /// The `TimelineEntry` type.
    static let timelineEntry = """
        One entry of the history of a task: a column move, the change of one stored field, or the change of one \
        comment. A reorder in the same column gives no entry.
        """

    /// The `TimelineEntry.cursor` field.
    static let timelineCursor = "Give it as after to timeline to get the entries after this one."

    /// The `TimelineEntry.txn` field.
    static let timelineTxn = "The ULID of the transaction. Give it as txn to undoChange to reverse the transaction."

    /// The `TimelineEntry.undone` field. It has the same meaning as `Change.undone`.
    static let timelineUndone = """
        True when a later undo or redo that is not undone reversed this transaction, the same as Change.undone.
        """

    /// The `TimelineEntry.kind` field.
    static let timelineEntryKind = "What the entry changed: a move, one stored field, or one comment."

    /// The `TimelineEntry.from` field.
    static let timelineFrom = """
        The column before a move, live or deleted. Null for the first move of the task and for each other kind.
        """

    /// The `TimelineEntry.to` field.
    static let timelineTo = "The column after a move, live or deleted. Null for each other kind."

    /// The `TimelineEntry.field` field.
    static let timelineField = """
        The change of one stored field for FIELD. For COMMENT with commentUpdate UPDATED, the diff of the comment \
        body. Null for each other entry.
        """

    /// The `TimelineEntry.comment` field.
    static let timelineComment = "The comment of a COMMENT entry, live or deleted. Null for each other kind."

    /// The `TimelineEntry.commentUpdate` field.
    static let timelineCommentUpdate = """
        How the comment changed: CREATED, UPDATED, DELETED, or RESTORED. Null for each other kind.
        """

    // MARK: - TimelineKind

    /// The `TimelineKind` enum.
    static let timelineKind = """
        What one entry of the history of a task changed. A reorder in the same column gives no entry.
        """

    /// The `MOVE` value of `TimelineKind`.
    static let timelineKindMove = "The task moved to a different column."

    /// The `FIELD` value of `TimelineKind`.
    static let timelineKindField = "One stored field of the task changed."

    /// The `COMMENT` value of `TimelineKind`.
    static let timelineKindComment = "A comment of the task was added, changed, deleted, or undeleted."
}
