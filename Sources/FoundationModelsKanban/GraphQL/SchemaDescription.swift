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

    /// The rule for a task ref that is the slug of a task title (divergence.md C3, E4).
    private static let taskTitleSlugRef = """
        A task ref can also be the title slug of a task, for example fix-login-bug for the title Fix login bug. A \
        ULID or a short id wins over a title slug. When two tasks have the title slug, the call uses the first \
        (a live task, then the lowest id) and gives a \(RefResolver.sharedTitleSlugWarningCode) warning.
        """

    /// The grammar of a filter (plan.md §6.3, divergence.md Q25).
    private static let filterSyntax = """
        Atoms: #tag, @actor, ^id, %column, ~type, and a kanban:// URI. ^id takes a ULID, a short id (^short or \
        ^^short), or the title slug of a task, for example ^fix-login-bug; it matches each task with that id or \
        title slug, and the tasks of the board that depend on one of them. A virtual tag, for example \
        #\(VirtualTag.ready.rawValue), is also a #tag atom. Join atoms with && (or a space), ||, and !, and group \
        them with ( ).
        """

    // MARK: - Board refs

    /// The `id` argument of `Query.board`.
    static let boardToRead = "The board to read. \(boardForms) No value reads the current board."

    /// The `boards` argument of `Query.checkLinks`.
    static let boardsToCheck = """
        The boards whose links to check. Each item is a board ref. \(boardForms) No value, or an empty list, checks \
        the current board.
        """

    /// The `board` argument of `Subscription.changes`.
    static let boardToObserve = "The board to observe. \(boardForms) No value observes the current board."

    /// The `board` argument of `Query.cursor`.
    static let cursorBoard = "The board of the cursor. \(boardForms) No value gives the cursor of the current board."

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
        only when the filter names #\(VirtualTag.deleted.rawValue), or has a ^id or a ~task atom.
        """

    /// The `filter` argument of `Board.nextTask`.
    static let nextTaskFilter = "The filter that the next task must match. \(filterSyntax)"

    /// The `filter` argument of the change feed: `Board.history`, `Change.updates`, and `Subscription.changes`.
    static let updateFilter = """
        The filter of the updates. An update stays when its node matches. \(filterSyntax) No filter in history and \
        changes keeps each update, except the updates of a deleted task: of these, only its delete stays. No filter \
        in Change.updates keeps each update of the change.
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

    /// The `Board.task` field (EXTRAS-9 rule 5).
    static let boardTask = singleItem(
        of: "task",
        forms: "its ULID, a ULID prefix, ^<short id>, its title slug, task/<ULID>"
    )

    /// The `Board.column` field (EXTRAS-9 rule 5).
    static let boardColumn = singleItem(of: "column", forms: "its slug, its name, column/<slug>")

    /// The `Board.actor` field (EXTRAS-9 rule 5).
    static let boardActor = singleItem(of: "actor", forms: "its slug, its name, actor/<slug>")

    /// The `Board.tag` field (EXTRAS-9 rule 5).
    static let boardTag = singleItem(of: "tag", forms: "its slug, its name, tag/<slug>")

    /// Gives the description of a single-item field of the board (EXTRAS-9 rule 5).
    ///
    /// - Parameters:
    ///   - noun: The node type in lowercase, for example `column`.
    ///   - forms: The short forms of the id of the node, for example `its slug, its name, column/<slug>`.
    /// - Returns: The description.
    private static func singleItem(of noun: String, forms: String) -> String {
        "One live \(noun) of the board by its id: \(forms), or the full kanban:// URI. Null, with no error, when no "
            + "live \(noun) has the id."
    }

    /// The `Board.nextTask` field.
    static let nextTask = """
        The first task in board order that has the \(VirtualTag.ready.rawValue) virtual tag and matches the filter: \
        a live task that is not done, and that no dependency stops. Null when no task is ready.
        """

    /// The `Board.model` field and the `model` field of `BoardInput` (divergence.md Q19).
    static let boardModel = """
        The model of the board as text, for example the chat model haiku, or null. The board does not check the text.
        """

    /// The `Board.virtualTags` field (divergence.md Q19).
    static let boardVirtualTags = """
        Each virtual tag, with its name, color, and description. A virtual tag is not stored: the board calculates \
        it for each task. See Task.virtualTags.
        """

    /// The `BoardSummary.totalActors` field (divergence.md Q19).
    static let summaryTotalActors = "The number of live actors of the board."

    /// The `Column.taskCount` field (divergence.md Q19).
    static let columnTaskCount = """
        The number of live tasks in the column. A task whose column is not a live column counts in the first column.
        """

    /// The `Column.readyCount` field (divergence.md Q19).
    static let columnReadyCount = """
        The number of live tasks in the column that no dependency stops. A done task can be ready, the same as \
        Task.ready.
        """

    // MARK: - Virtual tag fields

    /// The `VirtualTag.name` field.
    static let virtualTagName = """
        The name of the virtual tag, for example \(VirtualTag.ready.rawValue). A filter atom #name matches it.
        """

    /// The `VirtualTag.color` field.
    static let virtualTagColor = "The display color of the virtual tag: 6 hex digits with no #."

    /// The `VirtualTag.description` field.
    static let virtualTagDescription = "The meaning of the virtual tag in one sentence."

    // MARK: - Actor and progress fields

    /// The `Actor.avatar` field and the `avatar` field of `AddActorInput` and `UpdateActorInput` (divergence.md Q19).
    static let actorAvatar = """
        The avatar of the actor as text, for example a URL or an emoji. Null when the actor has no avatar.
        """

    /// The `name` field of `AddActorInput`.
    static let addActorName = "The name of the actor. No name gives the slug of the id as the name."

    /// The `Progress.percent` field (divergence.md Q19).
    static let progressPercent = "The part of the checklist that is checked, from 0 to 100: fraction times 100."

    // MARK: - Task inputs

    /// The `board` field of `MoveTaskInput` and `CopyTaskInput` (divergence.md Q21, E6).
    static let taskTargetBoard = """
        The board to move or copy the task to. \(boardForms) No value, or the board of the task, keeps the task in \
        its board. The new task keeps its tags (a missing tag is made), and each ref to the old board becomes a full \
        URI. A move tombstones the old task and adds a line with the new URI to its body. One undo reverses both \
        boards.
        """

    /// The `dependsOn` field of `AddTaskInput`.
    static let addTaskDependsOn = """
        The tasks that this task depends on. A short ref names a task of the board of the input. \
        \(taskTitleSlugRef) \(crossBoardDependency) A task URL in the body is also a dependency.
        """

    /// The `dependsOn` field of `UpdateTaskInput`.
    static let updateTaskDependsOn = """
        The new list of the tasks that this task depends on. It replaces the old list, and removes from the body the \
        task URLs that the list drops. A short ref names a task of the board of this task. \(taskTitleSlugRef) \
        \(crossBoardDependency)
        """

    /// The `column` field of `UpdateTaskInput` (divergence.md E5).
    static let updateTaskColumn = """
        The column to move the task to, in the same change. The task goes to the end of the column, or to the top \
        when the priority moves it there. A slug that no column has makes the column, the same as moveTask.
        """

    /// The `priority` field of `AddTaskInput` and `UpdateTaskInput` (divergence.md P2 and K15).
    static let taskPriority = """
        Not stored: a task has no priority field, and the place in the column is the priority. urgent, critical, \
        high, P0, P1, or true moves the task to the top of its column; low, P3, or P4 moves it to the end. Each other \
        value makes no move. The case does not matter, and the response gives a warning.
        """

    // MARK: - Comment inputs

    /// The `task` field of `UpdateCommentInput` and `CommentReferenceInput` (divergence.md E5, K16).
    static let commentTask = """
        The task of the comment. The comment id alone names the comment. When this task is not the task of the \
        comment, the call gives NOT_FOUND and changes nothing.
        """

    // MARK: - Link checks

    /// The `Query.checkLinks` field (divergence.md M9).
    static let checkLinks = """
        Reads each stored link of the boards and gives its class. The links are the dependsOn edges, the assignee \
        URIs, and the task URLs in the body of each live task, and the moved line of each tombstone. Reads only.
        """

    /// The `LinkCheck.board` field.
    static let linkBoard = "The current key of the board that holds the link."

    /// The `LinkCheck.node` field.
    static let linkNode = "The full URI of the task that holds the link."

    /// The `LinkCheck.field` field.
    static let linkField = """
        Where the task holds the link: \(LinkField.dependsOn.rawValue), \(LinkField.assignee.rawValue), \
        \(LinkField.body.rawValue) (a task URL in the body), or \(LinkField.tombstone.rawValue) (the line of a moved \
        task).
        """

    /// The `LinkCheck.target` field.
    static let linkTarget = "The link as the board stores it: a full kanban:// URI."

    /// The `LinkCheck.status` field.
    static let linkStatus = """
        \(LinkStatus.ok.rawValue): the board and the node are found. \(LinkStatus.oldName.rawValue): the link names \
        the board by an old name; currentName gives the name now. \(LinkStatus.dangling.rawValue): no reachable \
        board has the name. \(LinkStatus.missingNode.rawValue): the board is found, the node is not.
        """

    /// The `LinkCheck.currentName` field.
    static let linkCurrentName = """
        The current key of the board that the link names. Null for a \(LinkStatus.dangling.rawValue) link.
        """

    // MARK: - Link repairs

    /// The `Mutation.repairLinks` field (divergence.md M9).
    static let repairLinks = """
        Rewrites each \(LinkStatus.oldName.rawValue) link of the boards to the current name of its board, and lists \
        each \(LinkStatus.oldName.rawValue) and \(LinkStatus.dangling.rawValue) link. A \
        \(LinkStatus.dangling.rawValue) link does not change. One undo reverses the rewrite in each board.
        """

    /// The `boards` argument of `Mutation.repairLinks`.
    static let boardsToRepair = """
        The boards whose links to rewrite. Each item is a board ref. \(boardForms) No value, or an empty list, names \
        the current board. The call writes to no other board, unless reach is true.
        """

    /// The `reach` argument of `Mutation.repairLinks`.
    static let repairReach = """
        True also rewrites the links of each board that the scan reaches: the boards of Query.boards.
        """

    /// The `dryRun` argument of `Mutation.repairLinks`.
    static let repairDryRun = "True lists the same links and writes nothing."

    /// The `LinkRepair.newTarget` field.
    static let linkNewTarget = """
        The link after the rewrite: the full kanban:// URI with the current name of its board. Null for a \
        \(LinkStatus.dangling.rawValue) link, which does not change.
        """

    // MARK: - Collect

    /// The `Mutation.collectBoards` field (divergence.md M9).
    static let collectBoards = """
        Combines the .kanban folders of the source boards into the target board, the same as a git union merge. Tasks \
        and comments keep their ids. A column, a tag, or an actor with the same slug becomes one node, and the event \
        order decides a field that two boards set. Each name of a source becomes an old name of the target, and the \
        call removes each source .kanban folder. The call rewrites each \(LinkStatus.oldName.rawValue) link of the \
        target to the current name. Undo does not reverse the call. A board of the old Rust kanban gives \
        INCOMPATIBLE_BOARD and the call writes nothing.
        """

    /// The `sources` argument of `Mutation.collectBoards`.
    static let collectSources = """
        The boards to combine into the target. Each item is a folder that holds a .kanban folder (also a subfolder of \
        a git repo), or a board ref. \(boardForms) A source that is the target is left out.
        """

    /// The `target` argument of `Mutation.collectBoards`.
    static let collectTarget = """
        The board that gets the sources: a board ref. \(boardForms) No value names the current board. A target with \
        no board gets a new board with a new board ID. In a git repo, the target is the top folder of the repo.
        """

    /// The `reach` argument of `Mutation.collectBoards`.
    static let collectReach = """
        True also rewrites each link of a different board that the scan reaches and that names a source: the link \
        then names the target. With no value, the call only lists these links in otherLinks.
        """

    /// The `dryRun` argument of `Mutation.collectBoards`.
    static let collectDryRun = "True lists the slug merges, the conflicts, and the link repairs, and writes nothing."

    /// The `CollectBoardsResult.target` field.
    static let collectResultTarget = "The current key of the target board."

    /// The `CollectBoardsResult.sources` field.
    static let collectResultSources = "Each source board: its folder and its names, which are old names of the target."

    /// The `CollectBoardsResult.slugMerges` field.
    static let collectResultSlugMerges = "Each column, tag, and actor that more than one board has: one node now."

    /// The `CollectBoardsResult.conflicts` field.
    static let collectResultConflicts = "Each field that two or more boards set to different values, and the winner."

    /// The `CollectBoardsResult.repairs` field.
    static let collectResultRepairs = """
        The \(LinkStatus.oldName.rawValue) and \(LinkStatus.dangling.rawValue) links of the target, and with reach the \
        links of other boards that name a source, each with its new target.
        """

    /// The `CollectBoardsResult.otherLinks` field.
    static let collectResultOtherLinks = """
        Each link of a different board that names a source by a name that is now an old name of the target. Without \
        reach, the call does not change these links.
        """

    /// The `CollectBoardsResult.dryRun` field.
    static let collectResultDryRun = "True for a dry run: the call wrote nothing."

    /// The `CollectedBoard.path` field.
    static let collectedPath = "The folder of the source board."

    /// The `CollectedBoard.names` field.
    static let collectedNames = """
        The names of the source board, each one time: the key that the board ref of the call gave, its board IDs, its \
        git key, and its old names.
        """

    /// The `SlugMerge.node` field and the `FieldConflict.node` field.
    static let collectNode = "The full URI of the node in the target board."

    /// The `SlugMerge.boards` field.
    static let slugMergeBoards = "The folder of each board that has the node, the target first."

    /// The `FieldConflict.field` field.
    static let conflictField = "The name of the field, for example name, or body."

    /// The `FieldConflict.values` field.
    static let conflictValues = "The value that each board gives the field, each one time."

    /// The `FieldConflict.winner` field.
    static let conflictWinner = """
        The value after the collect: the merge of the events of all the boards. Null when a property has no value. An \
        empty body gives the empty text.
        """
}
