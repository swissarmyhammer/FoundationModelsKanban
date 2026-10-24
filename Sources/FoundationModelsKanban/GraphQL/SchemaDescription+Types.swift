/// The descriptions of the query fields and of the object types of the public schema: the `Node` interface, the
/// board types, the task types, and the `Priority` scalar (EXTRAS-9 rule 11). Each part of the schema has a
/// description, because the agent learns the schema with introspection.
extension SchemaDescription {
    // MARK: - Query fields

    /// The `Query.board` field.
    static let queryBoard = """
        One board: the current board, or the board that id names. The board of a different repo is read from its \
        .kanban folder.
        """

    /// The `Query.node` field.
    static let queryNode = """
        One node of any type by its id, live or deleted. Null when no node has the id. A full URI of a different \
        board reads that board.
        """

    /// The `id` argument of `Query.node`, and of the single-item fields of `Board`: `task`, `column`, `actor`, and
    /// `tag`.
    static let nodeID = "The id of the node: its full kanban:// URI, or a short form."

    /// The `Query.nodes` field.
    static let queryNodes = """
        The nodes of the ids, in the order of the ids, live or deleted. An id that names no node is not in the list.
        """

    /// The `ids` argument of `Query.nodes`.
    static let nodeIDs = "The ids of the nodes. Each id is a full kanban:// URI, or a short form."

    /// The `Query.boards` field (``BoardLocator/places(around:)``).
    static let queryBoards = """
        Each board that the scan finds, with its path, in scan order: each repo or board folder one level down in the \
        parent folder of the current repo, the current repo included, then in each search root of the config. A \
        board that cannot be read is not in the list, and the response gives a warning that names it.
        """

    /// The `enabled` argument of `Query.boards`.
    static let boardsEnabled = """
        True lists only the copies that have a board log (.kanban/board.jsonl), false lists only the copies that do \
        not. No value lists each copy.
        """

    // MARK: - Node interface

    /// The `Node` interface.
    static let node = """
        A node of the graph: a board, a column, an actor, a tag, a task, or a comment. Each node has a Markdown body.
        """

    /// The `id` field of `Node`.
    static let nodeIDField = "The full kanban:// URI of the node."

    /// The `body` field of `Node`.
    static let nodeBody = "The Markdown body of the node. Empty when the node has no body."

    /// The `created` field of `Node`.
    static let nodeCreated = "The time of the first change of the node."

    /// The `updated` field of `Node`.
    static let nodeUpdated = "The time of the last change of the node."

    /// The `deleted` field of `Node`.
    static let nodeDeleted = "The time of the delete. Null for a live node; a value means that the node is deleted."

    /// The `version` field of `Node` (divergence.md §18).
    static let nodeVersion = """
        The version of the node: the ULID of its last change. Each change of the node gives a new version. Give it \
        as ifVersion to updateTask, so that the call writes only when no other change came first. Null only for a \
        board that no change wrote yet.
        """

    // MARK: - Board

    /// The `Board` type.
    static let board = """
        A kanban board: the root of its columns, actors, tags, and tasks. The events of the board are in the .kanban \
        folder of its repo.
        """

    /// The `Board.key` field.
    static let boardKey = """
        The current key of the board, for example github.com/owner/repo. The kanban:// URI of each node of the board \
        starts with it.
        """

    /// The `Board.name` field.
    static let boardNameField = "The display name of the board."

    /// The `Board.columns` field.
    static let boardColumns = "The live columns, in board order: the first column first, the terminal column last."

    /// The `Board.actors` field.
    static let boardActors = "The live actors of the board."

    /// The `Board.tags` field.
    static let boardTags = "The live tags of the board. A renamed tag is not in the list; the tag of its new name is."

    /// The `Board.tasks` field.
    static let boardTasks = "One page of the tasks that the filter selects, in board order."

    /// The `first` argument of `Board.tasks`.
    static let tasksFirst = pageSize(of: "tasks")

    /// The `after` argument of `Board.tasks`.
    static let tasksAfter = """
        The cursor of the task before the page: the cursor of an edge, which is the id of the task. A short form also \
        works. No value starts the page at the first task.
        """

    /// The `Board.searchTasks` field.
    static let boardSearchTasks = """
        The tasks that best match the query, highest score first. The filter selects the tasks the same as in tasks.
        """

    /// The `query` argument of `Board.searchTasks`.
    static let searchQuery = "The search text. The search ranks whole words, parts of words, and the meaning."

    /// The `first` argument of `Board.searchTasks`.
    static let searchFirst = pageSize(of: "hits")

    /// The `Board.summary` field and the `BoardSummary` type.
    static let boardSummary = "The counts of the live tasks and of the live actors of the board."

    /// The `Board.path` field.
    static let boardPath = "The root folder of the repo of the board. Null for a board in memory only."

    /// The `Board.history` field.
    static let boardHistory = """
        The transactions that changed the board, newest first, that the filter keeps. A change of this call is not in \
        the list.
        """

    /// The `since` argument of `Board.history`.
    static let historySince = """
        The id of a transaction. The list holds only the transactions after it. No value lists each transaction.
        """

    /// The `first` argument of `Board.history`.
    static let historyFirst = pageSize(of: "changes")

    /// Gives the description of the `first` argument of a list.
    ///
    /// - Parameter items: The items of the list in the plural, for example `tasks`.
    /// - Returns: The description.
    static func pageSize(of items: String) -> String {
        "The largest number of \(items) in the list. A negative value gives no \(items)."
    }

    // MARK: - Column, actor, and tag

    /// The `Column` type.
    static let column = """
        A column of the board. Each live task shows in one column. The YAML frontmatter at the top of the body holds \
        the trigger of the column: \(ColumnTrigger.triggerKey): <skill> and \(ColumnTrigger.nextKey): <true or false>.
        """

    /// The `Column.name` field.
    static let columnNameField = "The display name of the column."

    /// The `Column.order` field.
    static let columnOrderField = """
        The sort key of the column on the board. The column with the lowest order is the first column, and the column \
        with the highest order is the terminal column: a task there is done.
        """

    /// The `Column.trigger` field.
    static let columnTriggerField = """
        The skill that runs when a task enters the column, from the \(ColumnTrigger.triggerKey) key of the frontmatter \
        of the body. Null when the body has no trigger, or when its frontmatter is not valid.
        """

    /// The `Column.next` field.
    static let columnNextField = """
        True when the task moves to the next column when the skill of the trigger ends, from the \
        \(ColumnTrigger.nextKey) key of the frontmatter of the body. True when the body does not give a valid value.
        """

    /// The `tasks` field of `Column`, `Actor`, and `Tag`.
    static let nodeTasks = "The tasks of this node that match the filter, in board order."

    /// The `Actor` type.
    static let actor = "A person or an agent: an assignee of tasks, and the author of comments."

    /// The `Tag` type.
    static let tag = "A label of tasks. A task gets a tag from a tag edge or from a #tag marker in its body."

    /// The `name` field of `Actor` and `Tag`.
    static let labelName = "The display name."

    /// The `color` field of `Actor` and `Tag`.
    static let labelColor = """
        The display color: the text that the last write stored, with no check of its form. A tag with no color gets \
        a fixed color from its slug: 6 hex digits with no #. An actor with no color gives null.
        """

    // MARK: - Summary and virtual tags

    /// The `BoardSummary.total` field.
    static let summaryTotal = "The number of live tasks."

    /// The `BoardSummary.ready` field.
    static let summaryReady = "The number of live tasks that no dependency stops. A done task can be ready."

    /// The `BoardSummary.blocked` field.
    static let summaryBlocked = "The number of live tasks that a dependency stops: total minus ready."

    /// The `BoardSummary.done` field.
    static let summaryDone = "The number of live tasks in the terminal column."

    /// The `BoardSummary.percent` field.
    static let summaryPercent = """
        The part of the live tasks that is done, from 0 to 100, rounded to a whole number. 0 when the board has no \
        live task.
        """

    /// The `VirtualTag` type.
    static let virtualTag = """
        A tag that the board calculates from the state of each task. The board does not store it.
        """

    // MARK: - Task and comment

    /// The `Task` type.
    static let task = """
        A task of the board: a title, a Markdown body, a column, and links to actors, tags, and other tasks.
        """

    /// The `shortId` field of `Task` and `Comment`.
    static let shortID = """
        The short id: the last \(ShortID.length) characters of the ULID, in lowercase. The ref ^<short id> names the \
        node.
        """

    /// The `Task.title` field.
    static let taskTitleField = "The title of the task."

    /// The `Task.column` field.
    static let taskColumn = """
        The column where the task shows. A task whose column is not a live column shows in the first column.
        """

    /// The `Task.ordinal` field.
    static let taskOrdinal = """
        The place of the task in its column, as a fractional index: the column sorts the tasks by this text.
        """

    /// The `Task.assignees` field.
    static let taskAssignees = """
        The live actors of the task. An actor of a different board is in the list when a loaded board has it.
        """

    /// The `Task.tags` field.
    static let taskTags = "The live tags of the task, from the tag edges and the #tag markers of the body, by slug."

    /// The `Task.progress` field.
    static let taskProgress = "The counts of the checklist lines of the body."

    /// The `Task.comments` field.
    static let taskComments = "The live comments of the task, oldest first. Empty for a deleted task."

    /// The `Task.started` field.
    static let taskStarted = """
        The time of the first change that put the task in a column that is not the first column, the add included. \
        Null when no change did.
        """

    /// The `Task.completed` field.
    static let taskCompleted = """
        The time of the last column move of the task, when the task is now done. Null when the task is not done, or \
        when no change set its column.
        """

    /// The `Comment` type.
    static let comment = "A comment on a task, with its author."

    /// The `Comment.task` field.
    static let commentTaskField = "The task of the comment, live or deleted."

    /// The `Comment.author` field.
    static let commentAuthorField = "The actor that wrote the comment, live or deleted."

    // MARK: - Progress

    /// The `Progress` type.
    static let progress = """
        The counts of the Markdown checklist lines of a task body: an open line is - [ ], a checked line is - [x] \
        or - [X].
        """

    /// The `Progress.total` field.
    static let progressTotal = "The number of checklist lines."

    /// The `Progress.completed` field.
    static let progressCompleted = "The number of checked checklist lines."

    /// The `Progress.fraction` field.
    static let progressFraction = """
        The part of the checklist that is checked, from 0 to 1. 0 when the body has no checklist line.
        """

    // MARK: - Pages

    /// The `TaskConnection` type.
    static let taskConnection = "One page of tasks, with the cursor of each task."

    /// The `TaskConnection.edges` field.
    static let connectionEdges = "The tasks of the page, each with its cursor."

    /// The `TaskConnection.totalCount` field.
    static let connectionTotalCount = "The number of tasks in the full list, on all pages."

    /// The `TaskEdge` type.
    static let taskEdge = "One task of a page, with its cursor."

    /// The `TaskEdge.node` field and the `TaskHit.task` field.
    static let theTask = "The task."

    /// The `TaskEdge.cursor` field.
    static let edgeCursor = "The cursor of the task: its id. Give it as after to get the page after this task."

    /// The `PageInfo` type and the `TaskConnection.pageInfo` field.
    static let pageInfo = "The place of a page in the full list."

    /// The `PageInfo.hasPreviousPage` field.
    static let hasPreviousPage = "True when the full list has tasks before the page."

    /// The `PageInfo.hasNextPage` field.
    static let hasNextPage = "True when the full list has tasks after the page."

    /// The `PageInfo.startCursor` field.
    static let startCursor = "The cursor of the first task of the page. Null for an empty page."

    /// The `PageInfo.endCursor` field.
    static let endCursor = "The cursor of the last task of the page. Null for an empty page."

    // MARK: - Search

    /// The `TaskHit` type.
    static let taskHit = "One task that a search found, with its score."

    /// The `TaskHit.score` field.
    static let hitScore = "The score of the hit from all signals, from 0 to 1. A higher score is a better match."

    /// The `TaskHit.signals` field.
    static let hitSignals = "The score of each signal. Null when the search gives no signals."

    /// The `SearchSignals` type.
    static let searchSignals = "The score of each signal of one search hit."

    /// The `SearchSignals.bm25` field.
    static let signalBM25 = "The BM25 score: the match of whole words."

    /// The `SearchSignals.trigram` field.
    static let signalTrigram = "The trigram score: the match of parts of words, also with typing errors."

    /// The `SearchSignals.cosine` field.
    static let signalCosine = """
        The embedding cosine score: the match of the meaning. Null when the keyword searcher ranked the hit: the \
        search has no embedder, or the embeddings of the newest task list are not done yet.
        """

    // MARK: - Scalars

    /// The `Priority` scalar (``PriorityMove/init(of:)``).
    static let priority = """
        A priority value of a task input: text, a word, a number, or a Boolean. The board stores no priority: urgent, \
        critical, high, p0, p1, or true moves the task to the top of its column; low, p3, or p4 moves it to the end; \
        each other value keeps its place. The case does not matter.
        """
}
