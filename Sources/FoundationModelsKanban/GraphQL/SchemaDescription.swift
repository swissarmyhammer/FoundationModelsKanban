/// The descriptions of the public schema (divergence.md R17).
///
/// The agent learns the schema with introspection (plan.md §12 item 10). Introspection and the SDL show these texts,
/// so that the agent learns what a field or an argument does when its name does not tell it. Each text is short, so
/// that the SDL stays small. The texts tell only the behavior that the code has now.
enum SchemaDescription {
    /// The form of the full URI of a task, for example a task on a different board.
    static let taskURIForm = "kanban://<board-key>/task/<id>"

    /// The rule for a dependency on a task of a different board: only the full URI names it.
    private static let crossBoardDependency =
        "For a task on a different board, give its full \(taskURIForm) URI."

    /// The forms of a board ref (plan.md §6.6).
    private static let boardForms =
        "A board key, a repo directory name, a repo path, or a kanban://<board-key> URI."

    /// The grammar of a filter (plan.md §6.3).
    private static let filterSyntax = """
        Atoms: #tag, @actor, ^id, %column, ~type, and a kanban:// URI. ^id of a task also matches the tasks that \
        depend on it. A virtual tag, for example #\(VirtualTag.ready.rawValue), is also a #tag atom. Join atoms \
        with && (or a space), ||, and !, and group them with ( ).
        """

    // MARK: - Board refs

    /// The `id` argument of `Query.board`.
    static let boardToRead = "The board to read. \(boardForms) No value reads the current board."

    /// The `board` argument of `Subscription.changes`.
    static let boardToObserve = "The board to observe. \(boardForms) No value observes the current board."

    /// The `board` field of a mutation input.
    static let boardToChange = """
        The board to change. \(boardForms) No value changes the current board. The short refs of the input name \
        nodes of this board.
        """

    /// The `board` field of `UndoInput`.
    static let boardOfTransaction = """
        The board that holds the transaction. \(boardForms) No value searches the current board and the loaded \
        related boards.
        """

    /// The `boards` field of `UndoInput`.
    static let copiesOfTransaction = """
        More copies of the other boards of the transaction to reverse, for example the path of a second worktree of \
        a repo.
        """

    // MARK: - Filters

    /// The `filter` argument of a task list: `Board.tasks`, `Board.searchTasks`, and the `tasks` field of `Column`,
    /// `Actor`, and `Tag`.
    static let taskFilter = """
        The filter of the tasks. \(filterSyntax) No filter gives each live task, done or not. A deleted task shows \
        only when the filter names #\(VirtualTag.deleted.rawValue).
        """

    /// The `filter` argument of `Board.nextTask`.
    static let nextTaskFilter = "The filter that the next task must match. \(filterSyntax)"

    /// The `filter` argument of the change feed: `Board.history`, `Change.updates`, and `Subscription.changes`.
    static let updateFilter = """
        The filter of the updates. An update stays when its node matches. \(filterSyntax) No filter keeps the \
        updates of the live nodes.
        """

    // MARK: - Task fields

    /// The `Task.dependsOn` field.
    static let taskDependsOn = """
        The live tasks that this task depends on: the dependsOn edges and the task URLs in the body. A task on a \
        different board has a full \(taskURIForm) id. A dependency that no loaded board has is not in this list. \
        See unresolvedDependsOn.
        """

    /// The `Task.blockedBy` field.
    static let taskBlockedBy = """
        The live tasks that stop this task: each dependency that is not done, or that is in a dependency cycle with \
        this task. The tasks of other boards are in the list. A dependency that cannot resolve is not in this list. \
        See unresolvedDependsOn.
        """

    /// The `Task.unresolvedDependsOn` field.
    static let taskUnresolvedDependsOn = """
        The full kanban:// URI of each dependency that no loaded board has as a task. For example, a URI with a \
        typo, or a task of a repo that is not on this computer. Each one stops the task.
        """

    /// The `Task.ready` field.
    static let taskReady = """
        True when no dependency stops the task. The column of the task has no effect, so a done task can be ready. \
        The #\(VirtualTag.ready.rawValue) virtual tag gives only the open tasks that are ready.
        """

    /// The `Task.virtualTags` field: the names of all virtual tags, from ``VirtualTag``.
    static let taskVirtualTags = """
        The virtual tags of the task, from its state: \
        \(VirtualTag.allCases.map(\.rawValue).joined(separator: ", ")). A filter can name them, for example \
        #\(VirtualTag.ready.rawValue).
        """

    // MARK: - Connection fields

    /// The `nodes` field of a connection type, for example `TaskConnection` (divergence.md §4).
    static let connectionNodes = """
        The nodes of the page, in the same order as edges. Use it in place of edges { node } when you do not need \
        the cursor of each node.
        """

    // MARK: - Board fields

    /// The `Board.nextTask` field.
    static let nextTask = """
        The first task in board order that has the \(VirtualTag.ready.rawValue) virtual tag and matches the filter: \
        a live task that is not done, with each dependency done. Null when no task is ready.
        """

    // MARK: - Task inputs

    /// The `dependsOn` field of `AddTaskInput`.
    static let addTaskDependsOn = """
        The tasks that this task depends on. A short ref names a task of the board of the input. \
        \(crossBoardDependency) A task URL in the body is also a dependency.
        """

    /// The `dependsOn` field of `UpdateTaskInput`.
    static let updateTaskDependsOn = """
        The new list of the tasks that this task depends on. It replaces the old list, and removes from the body the \
        task URLs that the list drops. A short ref names a task of the board of this task. \(crossBoardDependency)
        """

    /// The `column` field of `UpdateTaskInput` (divergence.md E5).
    static let updateTaskColumn = """
        The column to move the task to, in the same change. The task goes to the end of the column. A slug that no \
        column has makes the column, the same as moveTask.
        """

    // MARK: - Comment inputs

    /// The `task` field of `UpdateCommentInput` and `CommentReferenceInput` (divergence.md E5, K16).
    static let commentTask = """
        The task of the comment. The comment id alone names the comment. When this task is not the task of the \
        comment, the call gives NOT_FOUND and changes nothing.
        """
}
