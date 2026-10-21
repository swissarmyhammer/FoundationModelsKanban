import FoundationModelsExtras

extension GraphQLNameRules {
    /// The rules of the forgiving name rewrite of the public schema (plan.md §4.5): the alias tables of
    /// ``KanbanFieldAliases``, the Rust verbs, the query verbs of the board, the `board { … }` root container, and the
    /// removed Rust parameters of ``RemovedParameter``.
    static let kanban = GraphQLNameRules(
        aliases: KanbanFieldAliases.table,
        verbSynonyms: standardVerbSynonyms.merging(KanbanVerbs.synonyms) { _, kanban in kanban },
        nounVerbSynonyms: KanbanVerbs.nounSynonyms,
        queryVerbs: standardQueryVerbs.merging(KanbanVerbs.queryVerbs) { _, kanban in kanban },
        rootContainer: GraphQLRootContainer(field: KanbanVerbs.boardField, responseKeyPrefix: KanbanVerbs.rootMoveKey),
        removedParameters: RemovedParameter.allCases.map(\.toolkitParameter)
    )
}

/// The verbs that the kanban name rewrite adds to the general verbs of the toolkit.
private enum KanbanVerbs {
    /// The verb synonyms of a top-level mutation that the Rust kanban has and the general table does not: `archive`
    /// maps to `delete` and `unarchive` maps to `undelete` (plan.md §12, item 21). The Rust alias `create` → `init` is in
    /// ``nounSynonyms``, for the noun `board` only.
    static let synonyms: [String: String] = [
        "archive": "delete",
        "done": "complete", "finish": "complete", "close": "complete",
        "label": "tag", "unlabel": "untag",
        "restore": "undelete", "unarchive": "undelete", "recover": "undelete",
    ]

    /// The verb synonyms of a top-level mutation for one noun. The schema has `initBoard` and no `addBoard`, so
    /// `createBoard` and `newBoard` give `initBoard` (divergence.md Q11).
    static let nounSynonyms: [String: [String: String]] = [
        "board": ["create": "init", "new": "init"],
    ]

    /// The query verbs of the board that the general table does not have (divergence.md Q10): `search` and `next`
    /// give `searchTasks` and `nextTask`.
    static let queryVerbs: [String: GraphQLQueryVerb] = [
        "search": GraphQLQueryVerb(fieldWords: ["search"], defaultNoun: ["task"], number: .plural),
        "next": GraphQLQueryVerb(fieldWords: ["next"], defaultNoun: ["task"], number: .singular),
    ]

    /// The name of the root query field that holds the fields of a board.
    static let boardField = "board"

    /// The start of the response key of a `board` field that the rewrite adds. The number of the root move follows it.
    static let rootMoveKey = "_kanbanRoot"
}
