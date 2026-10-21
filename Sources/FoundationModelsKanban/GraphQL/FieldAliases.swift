import FoundationModelsExtras

/// The aliases of the fields, the arguments, and the `input` fields of the public schema: the other names that the
/// agent can write for each name (plan.md §4.5, step 5; divergence.md Q9, Q14, E5, tables 4.2 and 4.3).
///
/// The schema has one name for each field, and introspection shows only that name. The forgiving name rewrite of the
/// toolkit reads these tables through ``GraphQLNameRules/kanban``, so that the Swift code stays the one source of the
/// names (plan.md §1). An alias applies only in the positions of its table: a name that has one meaning in one
/// position can have a different meaning, or none, in a different position. For example, `assignee` names `assignees`
/// in a task input and `actor` in the input of `assignTask`. When two names of one position have the same alias, the
/// name of the agent gives `AMBIGUOUS_NAME`.
///
/// One input type can be the input of more than one field: `NodeReferenceInput` is the input of `deleteTask` and of
/// `deleteColumn`. So the aliases of its fields come from the mutation that holds it.
enum KanbanFieldAliases {
    /// The aliases that are safe at each position of a document. The old names `description` (Board, Tag, Task) and
    /// `text` (Comment) are aliases of `body` (plan.md §12, item 19). `label` is an alias of `tags`, because no field,
    /// argument, or `input` field has the name `tag`.
    private static let everywhere: [String: [String]] = [
        "body": ["description", "desc", "text", "content"],
        "tags": ["labels", "label"],
        "created": ["createdAt"],
        "updated": ["updatedAt"],
    ]

    /// The aliases that apply to the fields of each `input` object type.
    private static let inEachInput: [String: [String]] = [
        "body": ["notes", "details", "message", "comment"],
    ]

    /// The other names of a node ref in an input of its own node type: the type name, `<type>Id`, `ref`, `uri`, and
    /// `key`.
    ///
    /// - Parameter type: The GraphQL name of the node type in lowercase, for example `task`.
    /// - Returns: The aliases of `id`.
    private static func refAliases(ofType type: String) -> [String] {
        [type, "\(type)Id", "ref", "uri", "key"]
    }

    /// The other keys of a column, an actor, or a tag in its single-item field of the board (EXTRAS-9 rule 5): the
    /// aliases of a node ref, its slug, and its name.
    ///
    /// - Parameter type: The GraphQL name of the node type in lowercase, for example `column`.
    /// - Returns: The aliases of `id`.
    private static func itemAliases(ofType type: String) -> [String] {
        refAliases(ofType: type) + ["slug", "name"]
    }

    /// The aliases of the page size of a list.
    private static let pageSize = ["topK", "limit", "pageSize", "count", "size"]

    /// The aliases of the column of a task.
    private static let column = ["state", "status", "lane", "col", "columnId", "to", "toColumn"]

    /// The aliases of the title of a task.
    private static let title = ["name", "subject", "summary"]

    /// The aliases of the assignees of a task.
    private static let assignees = ["assignTo", "owner", "owners"]

    /// The aliases of the dependencies of a task. `blockedBy` is a synonym here, because the agent means a
    /// dependency (divergence.md Q14).
    private static let dependsOn = [
        "dependencies", "dependency", "depends", "deps", "blockers", "prerequisites", "blockedBy",
    ]

    /// The aliases of the priority value of a task input (divergence.md P2 and K15).
    private static let priority = ["prio", "urgent"]

    /// The aliases of the avatar of an actor input (divergence.md Q19).
    private static let avatar = ["avatarUrl", "image", "imageUrl", "icon", "picture", "photo", "emoji"]

    /// The aliases of the model of a board input (divergence.md Q19).
    private static let model = ["modelId", "chatModel", "agentModel", "llm"]

    /// The aliases of the `id` of an input that names a task.
    private static let taskID = refAliases(ofType: "task")

    /// The aliases of the `id` of an input that names a comment.
    private static let commentID = refAliases(ofType: "comment")

    /// The aliases of a `task` field that holds the task of a comment.
    private static let commentTask = ["taskId"]

    /// The aliases of the fields of the input of `moveTask` and `copyTask`: the task, the column, the neighbors, and
    /// the target board (divergence.md Q21).
    private static let taskPlacement = [
        "id": taskID, "column": column, "before": ["beforeId", "beforeTask"], "after": ["afterId", "afterTask"],
        "board": ["toBoard", "targetBoard", "destination", "repo"],
    ]

    /// The aliases of the `boards` argument of `checkLinks` and `repairLinks`: the boards of the links (divergence.md
    /// M9).
    private static let linkBoards = ["board", "ids", "id", "keys", "key", "repos", "repo", "paths", "path"]

    /// The aliases of the reach option and the dry run option of `repairLinks` and `collectBoards` (divergence.md M9).
    private static let repairOptions = [
        "reach": ["reachable", "includeReachable", "related", "allBoards"],
        "dryRun": ["dry", "preview", "simulate", "whatIf", "plan"],
    ]

    /// The aliases of the arguments of `repairLinks` (divergence.md M9): the boards, the reach option, and the dry run
    /// option.
    private static let linkRepair = repairOptions.merging(["boards": linkBoards]) { option, _ in option }

    /// The aliases of the arguments of `collectBoards` (divergence.md M9): the source boards, the target board, the
    /// reach option, and the dry run option.
    private static let boardCollect = repairOptions.merging([
        "sources": ["source", "boards", "board", "from", "folders", "folder", "paths", "path", "repos", "repo"],
        "target": ["into", "to", "destination", "targetBoard", "toBoard"],
    ]) { option, _ in option }

    /// The aliases of each object type and each `input` object type, by its GraphQL name.
    private static let byType: [String: [String: [String]]] = [
        "Task": ["column": ["status", "state", "lane"]],
        "TaskConnection": ["totalCount": ["count", "total"]],
        "Mutation": ["unassignTask": ["removeAssignee"], "assignTask": ["addAssignee"]],
        "Subscription": ["changes": ["kanbanChanges"]],
        "AddTaskInput": [
            "title": title, "column": column, "assignees": assignees, "dependsOn": dependsOn, "priority": priority,
        ],
        "UpdateTaskInput": [
            "id": taskID, "title": title, "column": column, "assignees": assignees, "dependsOn": dependsOn,
            "priority": priority,
        ],
        "MoveTaskInput": taskPlacement,
        "CopyTaskInput": taskPlacement,
        "AssignTaskInput": ["id": taskID, "actor": ["assignee", "actorId", "user", "who"]],
        "TagTaskInput": ["id": taskID],
        "AddCommentInput": ["task": commentTask, "actor": ["author", "user"]],
        "UpdateCommentInput": ["id": commentID, "task": commentTask],
        "CommentReferenceInput": ["id": commentID, "task": commentTask],
        "UpdateColumnInput": ["id": refAliases(ofType: "column")],
        "AddActorInput": ["avatar": avatar],
        "UpdateActorInput": ["id": refAliases(ofType: "actor"), "avatar": avatar],
        "BoardInput": ["model": model],
        "UpdateTagInput": ["id": refAliases(ofType: "tag")],
        "RenameTagInput": ["from": ["tag", "old", "oldName"], "to": ["name", "new", "newName"]],
        "UndoInput": ["txn": ["transaction", "txnId", "id"]],
    ]

    /// The aliases of the arguments of each field, and of the `input` fields under each field, by the coordinate
    /// `Type.field`. The input of the delete and the undelete mutations is `NodeReferenceInput` for each node type,
    /// so its aliases come from the mutation.
    private static let byField: [String: [String: [String]]] = [
        "Query.board": ["id": ["path", "board", "key", "repo"]],
        "Query.checkLinks": ["boards": linkBoards],
        "Mutation.repairLinks": linkRepair,
        "Mutation.collectBoards": boardCollect,
        "Query.node": ["id": ["task", "column", "actor", "tag", "comment", "ref", "uri", "key", "nodeId"]],
        "Board.task": ["id": taskID],
        "Board.column": ["id": itemAliases(ofType: "column")],
        "Board.actor": ["id": itemAliases(ofType: "actor")],
        "Board.tag": ["id": itemAliases(ofType: "tag")],
        "Board.tasks": ["first": pageSize, "after": ["cursor"]],
        "Board.searchTasks": ["first": pageSize],
        "Board.history": ["first": pageSize],
        "Mutation.completeTask": ["id": taskID],
        "Mutation.deleteTask": ["id": taskID],
        "Mutation.undeleteTask": ["id": taskID],
        "Mutation.deleteColumn": ["id": refAliases(ofType: "column")],
        "Mutation.undeleteColumn": ["id": refAliases(ofType: "column")],
        "Mutation.deleteActor": ["id": refAliases(ofType: "actor")],
        "Mutation.undeleteActor": ["id": refAliases(ofType: "actor")],
        "Mutation.deleteTag": ["id": refAliases(ofType: "tag")],
        "Mutation.undeleteTag": ["id": refAliases(ofType: "tag")],
    ]

    /// The alias tables of the public schema, for the toolkit name rewrite.
    static let table = GraphQLAliasTable(
        everywhere: everywhere,
        inEachInput: inEachInput,
        byType: byType,
        byField: byField
    )
}
