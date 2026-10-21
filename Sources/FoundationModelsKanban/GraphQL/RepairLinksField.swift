import FoundationModelsExtras
import Graphiti
import OrderedCollections

// MARK: - Names

extension MutationName {
    /// The mutation that rewrites each link with an old board name to the current name of its board (divergence.md
    /// M9).
    static let repairLinks = "repairLinks"
}

// MARK: - Arguments

/// The arguments of `Mutation.repairLinks` (divergence.md M9).
struct RepairLinksArguments: Codable, Sendable {
    /// The boards whose links to rewrite: each a board key, a repo directory name, a path, or the URI of a board.
    /// `nil` or an empty list names the current board.
    let boards: [String]?

    /// `true` to also rewrite the links of each board that the scan reaches: the boards of `Query.boards`. `nil` is
    /// `false`.
    let reach: Bool?

    /// `true` to list the changes and write nothing. `nil` is `false`.
    let dryRun: Bool?
}

/// One board of a `repairLinks` or a `collectBoards` call: the board, and the repairs of its links.
struct BoardRepairs {
    /// The board that holds the links.
    let target: MutationTarget

    /// The repairs of the links of the board, in the order of ``Graph/storedLinks(inBoard:)``.
    let repairs: [LinkRepair]
}

// MARK: - Resolvers

extension KanbanResolver {
    /// Resolves `Mutation.repairLinks`: rewrites each link with an old board name to the current name of its board,
    /// and lists each link with an old name or no board (``BoardStore/repairLinks(_:at:)``, divergence.md M9).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The boards, the reach option, and the dry run option.
    /// - Returns: The links. The list is empty in a run that the engine runs again after it loads a board. The
    ///   optional type makes the GraphQL field nullable, so that an error gives `null` for this field only.
    /// - Throws: The errors of ``BoardStore/repairLinks(_:at:)``.
    fileprivate func repairLinks(
        context: KanbanContext,
        arguments: RepairLinksArguments
    ) async throws -> [LinkRepair]? {
        try await context.store.repairLinks(arguments, at: context.clock()) ?? []
    }
}

// MARK: - Store

extension BoardStore {
    /// The name of the option of `repairLinks` that reaches each board of the scan, for the error of a call that
    /// reaches only the board of its folder.
    static let reachArgument = "\(MutationName.repairLinks)(reach: true)"

    /// Rewrites each stored link with an old board name to the current name of its board (divergence.md M9): the
    /// `dependsOn` edges, the assignee URIs, the task URLs in the bodies of the live tasks, and the line of each
    /// tombstone of a moved task. A link with the current key of its board gets a local ref in the stored form.
    ///
    /// The call writes only to the boards that it names, and with `reach` also to each board that the scan reaches.
    /// All the rewrites are one transaction of the call, so one `undo` reverses them. With `dryRun`, the call lists
    /// the same changes and writes nothing. A dangling link is in the list, and the call does not change it.
    ///
    /// - Parameters:
    ///   - arguments: The boards, the reach option, and the dry run option.
    ///   - time: The time of the change.
    /// - Returns: Each link with an old board name and each dangling link, by board in the order of the boards, or
    ///   `nil` when the engine did not load a board yet. The store then records the requests, and the call runs again
    ///   after the load.
    /// - Throws: ``KanbanError/boardNotFound(reference:searchRoots:)`` when the scan finds no board for a board ref.
    ///   ``KanbanError/notFound(type:reference:)`` for a named board that cannot be read. An ``EventError`` when a
    ///   patch breaks a rule of the log. Then no board keeps a patch.
    func repairLinks(_ arguments: RepairLinksArguments, at time: DateTime) throws -> [LinkRepair]? {
        guard let targets = try repairTargets(of: arguments) else {
            return nil
        }
        let found = targets.map { target in
            checkedLinks(of: view(of: target)).map { links in
                BoardRepairs(target: target, repairs: links.compactMap(LinkRepair.init(of:checked:)))
            }
        }
        guard let boards = found.allValues() else {
            return nil
        }
        if arguments.dryRun != true {
            try write(boards, as: MutationName.repairLinks, at: time)
        }
        return boards.flatMap(\.repairs)
    }

    /// Finds the boards of a `repairLinks` call: the named boards, and with `reach` each board that the scan reaches.
    /// A board that two refs name is one time in the list.
    ///
    /// - Parameter arguments: The boards and the reach option.
    /// - Returns: The boards, the named boards first, or `nil` when the engine did not load a board yet.
    /// - Throws: The errors of ``target(of:)``.
    private func repairTargets(of arguments: RepairLinksArguments) throws(KanbanError) -> [MutationTarget]? {
        let named = try Self.boardReferences(arguments.boards).map { reference throws(KanbanError) in
            try target(of: .named(reference))
        }
        let reached = arguments.reach == true ? try reachableTargets(for: Self.reachArgument) : []
        guard let reached, let named = named.allValues() else {
            return nil
        }
        return (named + reached).firstByKey(\.relatedPath)
    }

    /// Writes the rewrites of the links of some boards in one transaction of the call. A board with no link to
    /// rewrite gets no patch. Each board obeys the rules of ``runMutation(named:on:at:_:)``.
    ///
    /// - Parameters:
    ///   - boards: The boards and the repairs of their links.
    ///   - operation: The name of the public mutation of the field: `repairLinks` or `collectBoards`.
    ///   - time: The time of the change.
    /// - Throws: An ``EventError`` when a patch breaks a rule of the log. Then no board keeps a patch.
    func write(_ boards: [BoardRepairs], as operation: String, at time: DateTime) throws {
        let actor = sessionActor
        try runAtomically {
            for board in boards where board.repairs.contains(where: { repair in repair.newURI != nil }) {
                _ = try runField(as: operation, in: board.target) { work, key in
                    try work.applyMutationRules(actingAs: actor, inBoard: key, at: time) { work in
                        try work.rewrite(board.repairs, inBoard: key, at: time)
                    }
                }
            }
        }
    }
}

// MARK: - Patches

extension WorkingCopy {
    /// Writes the rewrites of the links of this board: one patch for each task that holds a link to rewrite.
    ///
    /// - Parameters:
    ///   - repairs: The repairs of the links of this board. A repair with no new URI writes nothing.
    ///   - key: The current key of this board.
    ///   - time: The time of the change.
    /// - Throws: An ``EventError`` when a patch breaks a rule of the log.
    mutating func rewrite(
        _ repairs: [LinkRepair],
        inBoard key: String,
        at time: DateTime
    ) throws(EventError) {
        for (task, links) in OrderedDictionary(grouping: repairs, by: \.link.holder) {
            try rewrite(links, ofTask: task, inBoard: key, at: time)
        }
    }

    /// Writes the rewrites of the links of one task in one patch: the edges that the patch removes and adds, and the
    /// new body. A task with no link to rewrite gets no patch, because a patch that changes nothing writes nothing.
    ///
    /// - Parameters:
    ///   - repairs: The repairs of the links of the task. A repair with no new URI writes nothing.
    ///   - task: The local ref of the task.
    ///   - key: The current key of this board.
    ///   - time: The time of the change.
    /// - Throws: An ``EventError`` when the patch breaks a rule of the log.
    private mutating func rewrite(
        _ repairs: [LinkRepair],
        ofTask task: LocalRef,
        inBoard key: String,
        at time: DateTime
    ) throws(EventError) {
        let rewrites = repairs.compactMap { repair in repair.newURI.map { new in (link: repair.link, new: new) } }
        let edges = Dictionary(
            grouping: rewrites.compactMap { rewrite in
                rewrite.link.field.edgeProperty.map { property in (property: property, rewrite: rewrite) }
            },
            by: \.property
        )
        let oldBody = graph.body(of: task)
        let newBody = rewrites.reduce(oldBody) { body, rewrite in
            rewrite.link.field.rewriting(body, from: rewrite.link.target, to: rewrite.new)
        }
        let patch = try PatchInput(
            changing: task,
            updating: [:],
            adding: edges.mapValues { rows in rows.map { row in StoredRef(uri: row.rewrite.new, inBoard: key) } },
            removing: edges.mapValues { rows in rows.map { row in StoredRef.remote(row.rewrite.link.target) } },
            body: newBody == oldBody ? .unchanged : .changed(newBody),
            from: oldBody
        )
        try apply(patch, at: time)
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the `repairLinks` mutation and its `LinkRepair` type (divergence.md M9).
    ///
    /// - Returns: This builder, for method chaining.
    func addRepairLinksMutation() -> Self {
        add {
            Graphiti.`Type`(
                resolver: KanbanResolver.self,
                context: KanbanContext.self,
                LinkRepair.self,
                fields: Self.linkCheckFields(of: \.check) + Self.linkRepairFields()
            )
        }
        .addMutation {
            Field(MutationName.repairLinks, at: KanbanResolver.repairLinks) {
                Argument("boards", at: \.boards).description(SchemaDescription.boardsToRepair)
                Argument("reach", at: \.reach).description(SchemaDescription.repairReach)
                Argument("dryRun", at: \.dryRun).description(SchemaDescription.repairDryRun)
            }
            .description(SchemaDescription.repairLinks)
        }
    }

    /// Gives the fields of a `LinkRepair` after the fields of its checked link.
    ///
    /// - Returns: The field `newTarget`.
    @FieldComponentBuilder<LinkRepair, KanbanContext>
    private static func linkRepairFields() -> [FieldComponent<LinkRepair, KanbanContext>] {
        Field("newTarget", at: \.newTarget).description(SchemaDescription.linkNewTarget)
    }
}
