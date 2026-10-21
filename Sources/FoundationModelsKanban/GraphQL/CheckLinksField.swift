import Graphiti

/// The arguments of `Query.checkLinks` (divergence.md M9).
struct CheckLinksArguments: Codable, Sendable {
    /// The boards whose links to check: each a board key, a repo directory name, a path, or the URI of a board. `nil`
    /// or an empty list checks the current board.
    let boards: [String]?
}

extension KanbanResolver {
    /// Resolves `Query.checkLinks`: each stored link of the named boards, with its class (divergence.md M9). The field
    /// reads only, and writes nothing.
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The boards to check. No `boards` checks the current board.
    /// - Returns: The links. The list is empty in a run that the engine runs again after it loads a board. The
    ///   optional type makes the GraphQL field nullable, so that an error gives `null` for this field only.
    /// - Throws: ``KanbanError/boardNotFound(reference:searchRoots:)`` when the scan finds no board for a board ref.
    func checkLinks(
        context: KanbanContext,
        arguments: CheckLinksArguments
    ) async throws(KanbanError) -> [LinkCheck]? {
        try await context.store.linkChecks(ofBoards: arguments.boards) ?? []
    }
}

extension BoardStore {
    /// Checks each stored link of some boards (divergence.md M9): the `dependsOn` edges, the assignee URIs, and the
    /// task URLs in the bodies of the live tasks, and the line of each tombstone of a moved task
    /// (``Graph/storedLinks(inBoard:)``). A board that two refs name is checked one time.
    ///
    /// - Parameter references: The board refs, or `nil` or an empty list for the current board.
    /// - Returns: The links, by board in the order of the refs, or `nil` when the engine did not load a board yet. The
    ///   store then records the requests, and the call runs again after the load.
    /// - Throws: ``KanbanError/boardNotFound(reference:searchRoots:)`` when the scan finds no board for a ref.
    func linkChecks(ofBoards references: [String]?) throws(KanbanError) -> [LinkCheck]? {
        let views = try Self.boardReferences(references).map { reference throws(KanbanError) in
            try view(ofBoard: reference)
        }
        let checks = views.compactMap(\.self).firstByKey(\.boardKey).map { view in checkedLinks(of: view) }
        guard views.allValues() != nil, let boards = checks.allValues() else {
            return nil
        }
        return boards.flatMap { links in links.map(\.check) }
    }

    /// Gives the board refs of a field that names the boards of its links: `checkLinks` and `repairLinks`
    /// (divergence.md M9).
    ///
    /// - Parameter references: The board refs of the field, or `nil` or an empty list for the current board.
    /// - Returns: The board refs, or one `nil` ref for the current board.
    static func boardReferences(_ references: [String]?) -> [String?] {
        references.flatMap { refs in refs.isEmpty ? nil : refs.map(Optional.some) } ?? [nil]
    }

    /// Checks each stored link of one board (``Graph/storedLinks(inBoard:)``). The check of each link runs, also after
    /// a link whose board is not loaded, so that the store records the requests of all links in one run.
    ///
    /// - Parameters:
    ///   - view: The read view of the board that holds the links.
    ///   - ownNames: More names that name the board of the view itself, each as ``BoardKey/normalizedText(of:)``
    ///     gives it, for example the names of the source boards that `collectBoards` adds to it. A link with such a
    ///     name reads the graph of the view, and not the board that the scan finds for the name. The default is none.
    /// - Returns: Each link with its check, in the order of ``Graph/storedLinks(inBoard:)``, or `nil` when the engine
    ///   did not resolve or load the board of a link yet. The store then records the requests, and the call runs again
    ///   after the load.
    func checkedLinks(
        of view: BoardView,
        naming ownNames: Set<String> = []
    ) -> [(link: StoredLink, check: LinkCheck)]? {
        view.graph.storedLinks(inBoard: view.boardKey).map { link in
            check(link, in: view, naming: ownNames).map { check in (link: link, check: check) }
        }
        .allValues()
    }

    /// Checks one stored link of a board. A link with the current key of its own board, or with one of the own names,
    /// reads the graph of that board.
    ///
    /// - Parameters:
    ///   - link: The link.
    ///   - view: The read view of the board that holds the link.
    ///   - ownNames: More names that name the board of the view itself, as ``checkedLinks(of:naming:)`` gives them.
    /// - Returns: The checked link, or `nil` when the engine did not resolve or load the board of the link yet.
    private func check(_ link: StoredLink, in view: BoardView, naming ownNames: Set<String>) -> LinkCheck? {
        let key = link.target.boardKey
        let linked =
            key == view.boardKey || ownNames.contains(BoardKey.normalizedText(of: key))
            ? LinkedBoard.loaded(BoardSnapshot(key: view.boardKey, graph: view.graph, source: view.source))
            : linkedBoard(named: key)
        return linked.map { linked in LinkCheck(of: link, in: view, against: linked) }
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the `LinkCheck` type of `Query.checkLinks`, and the `LinkField` and `LinkStatus` enums (divergence.md M9).
    ///
    /// - Returns: This builder, for method chaining.
    func addLinkCheckTypes() -> Self {
        add {
            Self.enumType(LinkField.self)
            Self.enumType(LinkStatus.self)
            Graphiti.`Type`(
                resolver: KanbanResolver.self,
                context: KanbanContext.self,
                LinkCheck.self,
                fields: Self.linkCheckFields(of: \.self)
            )
            .description(SchemaDescription.linkCheck)
        }
    }

    /// Gives the fields of a checked link, for the `LinkCheck` type and for the `LinkRepair` type of
    /// `Mutation.repairLinks` (divergence.md M9).
    ///
    /// - Parameter check: The key path from the object to its checked link.
    /// - Returns: The fields `board`, `node`, `field`, `target`, `status`, and `currentName`.
    @FieldComponentBuilder<Object, KanbanContext>
    static func linkCheckFields<Object: Sendable>(
        of check: KeyPath<Object, LinkCheck>
    ) -> [FieldComponent<Object, KanbanContext>] {
        Field("board", at: check.appending(path: \.board)).description(SchemaDescription.linkBoard)
        Field("node", at: check.appending(path: \.node)).description(SchemaDescription.linkNode)
        Field("field", at: check.appending(path: \.field)).description(SchemaDescription.linkField)
        Field("target", at: check.appending(path: \.target)).description(SchemaDescription.linkTarget)
        Field("status", at: check.appending(path: \.status)).description(SchemaDescription.linkStatus)
        Field("currentName", at: check.appending(path: \.currentName)).description(SchemaDescription.linkCurrentName)
    }
}

// MARK: - Enum descriptions

extension LinkField: DescribedGraphQLEnum {
    /// The description of the `LinkField` enum.
    static let typeDescription = "The field of a task that holds a stored link."

    /// The description of the value of this case.
    var valueDescription: String {
        switch self {
        case .dependsOn: "A dependsOn edge of the task."
        case .assignee: "An assignee that is the full URI of an actor of a different board."
        case .body: "A task URL in the body of a live task."
        case .tombstone: "The line of the tombstone of a moved task that points to the task that the move made."
        }
    }
}

extension LinkStatus: DescribedGraphQLEnum {
    /// The description of the `LinkStatus` enum.
    static let typeDescription = "The class of a stored link."

    /// The description of the value of this case.
    var valueDescription: String {
        switch self {
        case .ok: "The link names its board by a current name, and the board has the node."
        case .oldName: "The link names its board by an old name. It still works, and the response gives a warning."
        case .dangling: "No reachable board has the name of the link."
        case .missingNode: "The board of the link is found, and the board does not have the node."
        }
    }
}
