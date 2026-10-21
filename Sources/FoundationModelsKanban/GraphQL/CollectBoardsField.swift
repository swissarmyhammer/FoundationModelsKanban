import Foundation
import FoundationModelsExtras
import Graphiti

// MARK: - Names

extension MutationName {
    /// The mutation that combines the `.kanban` folders of some source boards into one target board (divergence.md
    /// M9).
    static let collectBoards = "collectBoards"
}

// MARK: - Arguments

/// The `input` object of `collectBoards` (divergence.md M9, EXTRAS-9 rule 7). No field is required.
struct CollectBoardsInput: Codable, Sendable {
    /// The source boards: each a folder that holds a `.kanban/`, or a board ref. `nil` or an empty list collects no
    /// board.
    let sources: [String]?

    /// The target board: a board ref, or `nil` for the current board.
    let target: String?

    /// `true` to also rewrite each link of ``CollectReport/otherLinks``. `nil` is `false`.
    let reach: Bool?

    /// `true` to list the changes and write nothing. `nil` is `false`.
    let dryRun: Bool?
}

// MARK: - Result

/// The result of `Mutation.collectBoards`: the GraphQL `CollectBoardsResult` type (divergence.md M9).
struct CollectReport: Sendable {
    /// The current key of the target board.
    let target: String

    /// Each source board, in the order of the call.
    let sources: [CollectedBoard]

    /// Each column, tag, and actor that more than one board has.
    let slugMerges: [SlugMerge]

    /// Each field that two or more boards set to different values.
    let conflicts: [FieldConflict]

    /// The repairs of the links of the target, and with `reach` the repairs of ``otherLinks``.
    ///
    /// The links of the target are checked in the graph after the merge (``BoardStore/checkedLinks(of:naming:)``),
    /// where a link with a name of a source reads the merged target. Each `OLD_NAME` link gets the current key of its
    /// board, and each `DANGLING` link is in the list with no new URI. An `OK` or a `MISSING_NODE` link is not in the
    /// list (``LinkRepair/init(of:checked:)``).
    let repairs: [LinkRepair]

    /// Each link of a board that the scan reaches, other than the target and the sources, whose board key is a name
    /// of a source, checked against the target after the merge. Only an `OLD_NAME` link is in the list: the name is
    /// an old name of the merged target, and the target has the node. A link to a node that the target does not have
    /// is left out. With `reach`, and no dry run, the call rewrites each of them to the current key of the target.
    let otherLinks: [LinkCheck]

    /// `true` when the call wrote nothing.
    let dryRun: Bool
}

/// One source board of `Mutation.collectBoards`: the GraphQL `CollectedBoard` type.
struct CollectedBoard: Encodable, Sendable {
    /// The folder of the source board.
    let path: String

    /// The names of the source board, which are old names of the target now.
    let names: [String]
}

/// One node that more than one board of `Mutation.collectBoards` has: the GraphQL `SlugMerge` type.
struct SlugMerge: Encodable, Sendable {
    /// The full URI of the node in the target board.
    let node: NodeID

    /// The folder of each board that has the node, the target first.
    let boards: [String]
}

/// One field that two or more boards of `Mutation.collectBoards` set to different values: the GraphQL `FieldConflict`
/// type.
struct FieldConflict: Encodable, Sendable {
    /// The full URI of the node in the target board.
    let node: NodeID

    /// The name of the field.
    let field: String

    /// The value that each board gives the field, each one time.
    let values: [String]

    /// The value after the collect, or `nil` when the field has no value.
    let winner: String?
}

// MARK: - Resolvers

extension KanbanResolver {
    /// Resolves `Mutation.collectBoards`: combines the source boards into the target board
    /// (``BoardStore/collectBoards(_:at:)``, divergence.md M9).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The sources, the target, the reach option, and the dry run option.
    /// - Returns: The result, or `nil` in a run that the engine runs again after it loads a board. The optional type
    ///   makes the GraphQL field nullable, so that an error gives `null` for this field only.
    /// - Throws: The errors of ``BoardStore/collectBoards(_:at:)``.
    fileprivate func collectBoards(
        context: KanbanContext,
        arguments: InputArguments<CollectBoardsInput>
    ) async throws -> CollectReport? {
        try await context.store.collectBoards(arguments.input, at: context.clock())
    }
}

// MARK: - Store

extension BoardStore {
    /// Combines the `.kanban` folders of the source boards into the target board (divergence.md M9).
    ///
    /// The call adds the events of each node log of each source to the node log with the same name in the target, the
    /// same as a git union merge: tasks and comments keep their ULIDs, and a column, a tag, or an actor with the same
    /// slug becomes one node. Replay decides a field that two boards set by the event order. The call also adds each
    /// line of a source board log whose transaction wrote a merged node log, so that a load of the target applies each
    /// merged transaction. The target keeps its own board ID, git key, and name. One `collected` patch for
    /// each source makes each name of the source an old name of the target. The call rewrites each old-name link of
    /// the target to the current name (`checkLinks` and `repairLinks`), so a `dependsOn` between two sources becomes a
    /// local ref. It lists each link of a different board that names a source and whose node the target has
    /// (``CollectReport/otherLinks``), and rewrites it only with `reach`.
    ///
    /// The commit locks the target and each source, checks that no source changed after the read, writes all the
    /// events, and then removes each source `.kanban/`. The call is final: `undoChange` does not reverse it. With
    /// `dryRun`, the call lists the same changes and writes nothing.
    ///
    /// - Parameters:
    ///   - input: The sources, the target, the reach option, and the dry run option.
    ///   - time: The time of the change.
    /// - Returns: The result, or `nil` when the engine did not load a board yet. The store then records the requests,
    ///   and the call runs again after the load.
    /// - Throws: ``KanbanError/incompatibleBoard(directory:)`` when a source is a board of the old Rust kanban.
    ///   ``KanbanError/boardNotFound(reference:searchRoots:)`` when the scan finds no board for a board ref.
    ///   ``KanbanError/notFound(type:reference:)`` for a board that cannot be read. An ``EventLogError`` when a
    ///   source cannot be read, or an ``EventError`` when a patch breaks a rule of the log. Then nothing is written.
    ///   ``KanbanError/unreachableBoards(field:)`` when the call reaches only the board of its folder: the call reads
    ///   other `.kanban` folders, so it is refused before it reads a source.
    func collectBoards(_ input: CollectBoardsInput, at time: DateTime) throws -> CollectReport? {
        try reach.checkReachesOtherBoards(for: MutationName.collectBoards)
        guard let target = try target(of: .named(input.target)) else {
            return nil
        }
        let targetView = view(of: target)
        guard let root = targetView.source?.directory else {
            throw KanbanError.notFound(type: .board, reference: input.target ?? targetView.boardKey)
        }
        guard
            let sources = try collectedSources(named: input.sources ?? [], besides: root),
            let others = try otherTargets(besides: [root] + sources.map(\.root))
        else {
            return nil
        }
        var merged = workingCopy(of: target)
        merged.merge(sources.flatMap(\.events))
        try merged.addCollected(sources, at: time)
        let names = Set(sources.flatMap(\.names))
        let snapshot = BoardSnapshot(key: targetView.boardKey, graph: merged.graph, source: nil)
        guard let links = checkedLinks(of: snapshot.view(reading: .unavailable), naming: names) else {
            return nil
        }
        let repairs = links.compactMap(LinkRepair.init(of:checked:))
        let otherRepairs = others.map { other in
            BoardRepairs(target: other, repairs: sourceLinks(of: view(of: other), naming: names, in: snapshot))
        }
        let reached = input.reach == true ? otherRepairs : []
        if input.dryRun != true {
            try write(sources, into: target, repairing: repairs, alongside: reached, at: time)
        }
        return CollectReport(
            merging: sources,
            into: targetView,
            besides: workingCopy(of: target),
            repairs: repairs + reached.flatMap(\.repairs),
            otherLinks: otherRepairs.flatMap(\.repairs).map(\.check),
            dryRun: input.dryRun == true
        )
    }

    /// Finds the source boards of a `collectBoards` call, and reads each one. A source that is the target, and a
    /// source that two refs name, is one time or not in the list.
    ///
    /// - Parameters:
    ///   - references: The refs of the sources: each a folder that holds a `.kanban/`, or a board ref.
    ///   - root: The root directory of the target board.
    /// - Returns: The sources, in the order of the refs, or `nil` when the engine did not load a board of a ref yet.
    /// - Throws: ``KanbanError/incompatibleBoard(directory:)`` for a board of the old Rust kanban. The errors of
    ///   ``view(ofBoard:)``. An ``EventLogError`` when a source cannot be read.
    private func collectedSources(named references: [String], besides root: URL) throws -> [CollectedSource]? {
        let currentRoot = view.source?.directory ?? root
        let found = try references.map { reference throws(KanbanError) in
            try sourceBoard(named: reference, currentRoot: currentRoot)
        }
        guard let boards = found.allValues() else {
            return nil
        }
        let targetPath = root.canonicalPath
        return try boards.filter { board in board.root.canonicalPath != targetPath }
            .firstByKey(\.root.canonicalPath)
            .map(Self.read)
    }

    /// Finds the root directory of one source board of a `collectBoards` call. A path to a folder that holds a
    /// `.kanban/` names that folder, also a subfolder of a git repo whose board is at the top of the repo. A path to a
    /// `.kanban/` itself names its parent. Each other ref is a board ref.
    ///
    /// - Parameters:
    ///   - reference: The ref of the source.
    ///   - currentRoot: The root directory of the current board, for a path that starts with `./` or `../`.
    /// - Returns: The root directory, and the current key of a board that a board ref names, or `nil` when the engine
    ///   did not load the board of the ref yet.
    /// - Throws: The errors of ``view(ofBoard:)``. ``KanbanError/notFound(type:reference:)`` for a board in memory
    ///   only.
    private func sourceBoard(
        named reference: String,
        currentRoot: URL
    ) throws(KanbanError) -> (root: URL, key: String?)? {
        let text = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let folder = BoardIndex.directory(ofPath: text, currentRoot: currentRoot).map(Self.boardRoot(ofFolder:)),
            BoardWatcher.existingBoardDirectory(ofBoardAt: folder) != nil
        {
            return (folder, nil)
        }
        guard let board = try view(ofBoard: text) else {
            return nil
        }
        guard let directory = board.source?.directory else {
            throw .notFound(type: .board, reference: text)
        }
        return (directory, board.boardKey)
    }

    /// Gives the root directory of a board from a folder that a path names: the parent of a `.kanban/` folder, else
    /// the folder itself.
    ///
    /// - Parameter folder: The folder.
    /// - Returns: The root directory.
    private static func boardRoot(ofFolder folder: URL) -> URL {
        folder.lastPathComponent == EventLog.directoryName ? folder.deletingLastPathComponent() : folder
    }

    /// Reads one source board, and gives a board of the old Rust kanban as
    /// ``KanbanError/incompatibleBoard(directory:)``.
    ///
    /// - Parameter board: The root directory of the source, and its current key when a board ref named it.
    /// - Returns: The source.
    /// - Throws: ``KanbanError/incompatibleBoard(directory:)``, or an ``EventLogError`` when the source cannot be read.
    private static func read(_ board: (root: URL, key: String?)) throws -> CollectedSource {
        do {
            return try CollectedSource.read(fromBoardAt: board.root, currentKey: board.key)
        } catch {
            throw KanbanError(callFailure: error) ?? error
        }
    }

    /// Gives the boards that the scan reaches, other than the target and the sources of a `collectBoards` call.
    ///
    /// - Parameter roots: The root directories of the target and of each source.
    /// - Returns: The boards in scan order, or `nil` when the engine did not scan or load a board yet.
    /// - Throws: ``KanbanError/unreachableBoards(field:)`` when the call reaches only the board of its folder.
    private func otherTargets(besides roots: [URL]) throws(KanbanError) -> [MutationTarget]? {
        let paths = Set(roots.map(\.canonicalPath))
        return try reachableTargets(for: MutationName.collectBoards)?.filter { target in
            view(of: target).source.map { source in !paths.contains(source.directory.canonicalPath) } ?? false
        }
    }

    /// Gives the repair of each link of a different board that names a source: the link then names the target.
    ///
    /// - Parameters:
    ///   - view: The read view of the board that holds the links.
    ///   - names: The names of the sources, each as ``BoardKey/normalizedText(of:)`` gives it.
    ///   - target: The target board after the merge. Its old names hold the names of the sources.
    /// - Returns: The repairs, in the order of ``Graph/storedLinks(inBoard:)``. A link to a node that the target does
    ///   not have is not in the list.
    private func sourceLinks(
        of view: BoardView,
        naming names: Set<String>,
        in target: BoardSnapshot
    ) -> [LinkRepair] {
        view.graph.storedLinks(inBoard: view.boardKey)
            .filter { link in names.contains(BoardKey.normalizedText(of: link.target.boardKey)) }
            .compactMap { link in
                LinkRepair(of: link, checked: LinkCheck(of: link, in: view, against: .loaded(target)))
            }
    }

    /// Writes a `collectBoards` call in one transaction: the events of the sources, their board lines, one board patch
    /// that keeps the names of the target, one `collected` patch for each source, the repairs of the links of the
    /// target, and the repairs of the links of the other boards. The target obeys the rules of
    /// ``runMutation(named:on:at:_:)``: a target with no board gets its board, with a new board ID.
    ///
    /// Each source that the engine loaded is a board of the commit too, with no patch. The commit removes its
    /// `.kanban/`, and its engine then holds no event of it: `undo` searches the loaded boards, and must not find a
    /// transaction of a removed source (divergence.md M9).
    ///
    /// - Parameters:
    ///   - sources: The source boards.
    ///   - target: The target board.
    ///   - repairs: The repairs of the links of the target after the merge.
    ///   - others: The other boards and the repairs of their links.
    ///   - time: The time of the change.
    /// - Throws: An ``EventError`` when a patch breaks a rule of the log. Then no board keeps a patch.
    private func write(
        _ sources: [CollectedSource],
        into target: MutationTarget,
        repairing repairs: [LinkRepair],
        alongside others: [BoardRepairs],
        at time: DateTime
    ) throws {
        let actor = sessionActor
        let events = sources.flatMap(\.events)
        try runAtomically {
            _ = try runField(as: MutationName.collectBoards, in: target) { work, key in
                work.merge(events)
                try work.applyMutationRules(actingAs: actor, inBoard: key, at: time) { work in
                    try work.addCollected(sources, at: time)
                    try work.rewrite(repairs, inBoard: key, at: time)
                }
            }
            try write(others, as: MutationName.collectBoards, at: time)
        }
        addToCommit(loadedBoardsAt: sources.map(\.root.canonicalPath))
    }
}

extension CollectReport {
    /// Makes the result of a `collectBoards` call.
    ///
    /// - Parameters:
    ///   - sources: The source boards.
    ///   - target: The read view of the target before the call.
    ///   - work: The working copy of the target before the call: its events give the nodes of the target.
    ///   - repairs: The repairs of the links.
    ///   - otherLinks: The links of the other boards that name a source, with the rule of ``otherLinks``.
    ///   - dryRun: `true` when the call wrote nothing.
    init(
        merging sources: [CollectedSource],
        into target: BoardView,
        besides work: WorkingCopy,
        repairs: [LinkRepair],
        otherLinks: [LinkCheck],
        dryRun: Bool
    ) {
        let targetPath = target.source?.directory.path ?? target.boardKey
        let sourceBoards = sources.map { source in
            CollectMerge.Board(path: source.root.path, events: Dictionary(grouping: source.events, by: \.patch.node))
        }
        let targetBoard = CollectMerge.Board(path: targetPath, events: work.eventsByNode(besides: sources))
        let merge = CollectMerge(boards: [targetBoard] + sourceBoards)
        self.init(
            target: target.boardKey,
            sources: sources.map { source in CollectedBoard(path: source.root.path, names: source.names) },
            slugMerges: merge.slugMerges.map { shared in
                SlugMerge(node: target.id(of: shared.node), boards: shared.paths)
            },
            conflicts: merge.conflicts.map { conflict in
                FieldConflict(
                    node: target.id(of: conflict.node),
                    field: conflict.field,
                    values: conflict.values,
                    winner: conflict.winner
                )
            },
            repairs: repairs,
            otherLinks: otherLinks,
            dryRun: dryRun
        )
    }
}

extension WorkingCopy {
    /// Gives the events of each node of this board that a source of a `collectBoards` call also has, from the events
    /// of the live graph.
    ///
    /// - Parameter sources: The source boards.
    /// - Returns: The events of each such node.
    fileprivate func eventsByNode(besides sources: [CollectedSource]) -> [LocalRef: [Event]] {
        let nodes = Set(sources.flatMap { source in source.events.map(\.patch.node) })
        return Dictionary(grouping: liveEvents.filter { event in nodes.contains(event.patch.node) }, by: \.patch.node)
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the `collectBoards` mutation, its `input` type `CollectBoardsInput`, and its `CollectBoardsResult`,
    /// `CollectedBoard`, `SlugMerge`, and `FieldConflict` types (divergence.md M9, EXTRAS-9 rule 7).
    ///
    /// - Returns: This builder, for method chaining.
    func addCollectBoardsMutation() -> Self {
        add {
            Type(CollectedBoard.self) {
                Field("path", at: \.path).description(SchemaDescription.collectedPath)
                Field("names", at: \.names).description(SchemaDescription.collectedNames)
            }
            .description(SchemaDescription.collectedBoard)
            Type(SlugMerge.self) {
                Field("node", at: \.node).description(SchemaDescription.collectNode)
                Field("boards", at: \.boards).description(SchemaDescription.slugMergeBoards)
            }
            .description(SchemaDescription.slugMerge)
            Type(FieldConflict.self) {
                Field("node", at: \.node).description(SchemaDescription.collectNode)
                Field("field", at: \.field).description(SchemaDescription.conflictField)
                Field("values", at: \.values).description(SchemaDescription.conflictValues)
                Field("winner", at: \.winner).description(SchemaDescription.conflictWinner)
            }
            .description(SchemaDescription.fieldConflict)
            Type(CollectReport.self, as: "CollectBoardsResult") {
                Field("target", at: \.target).description(SchemaDescription.collectResultTarget)
                Field("sources", at: \.sources).description(SchemaDescription.collectResultSources)
                Field("slugMerges", at: \.slugMerges).description(SchemaDescription.collectResultSlugMerges)
                Field("conflicts", at: \.conflicts).description(SchemaDescription.collectResultConflicts)
                Field("repairs", at: \.repairs).description(SchemaDescription.collectResultRepairs)
                Field("otherLinks", at: \.otherLinks).description(SchemaDescription.collectResultOtherLinks)
                Field("dryRun", at: \.dryRun).description(SchemaDescription.collectResultDryRun)
            }
            .description(SchemaDescription.collectResult)
            Input(CollectBoardsInput.self) {
                InputField("sources", at: \.sources).description(SchemaDescription.collectSources)
                InputField("target", at: \.target).description(SchemaDescription.collectTarget)
                InputField("reach", at: \.reach).description(SchemaDescription.collectReach)
                InputField("dryRun", at: \.dryRun).description(SchemaDescription.collectDryRun)
            }
            .description(SchemaDescription.collectBoardsInput)
        }
        .addMutation {
            Self.mutationField(
                MutationName.collectBoards,
                at: KanbanResolver.collectBoards,
                description: SchemaDescription.collectBoards
            )
        }
    }
}
