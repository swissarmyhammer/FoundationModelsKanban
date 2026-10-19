import Graphiti
import OrderedCollections

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
        let named = references.flatMap { refs in refs.isEmpty ? nil : refs.map(Optional.some) } ?? [nil]
        let views = try named.map { reference throws(KanbanError) in try view(ofBoard: reference) }
        let boards = OrderedDictionary(
            views.compactMap(\.self).map { view in (view.boardKey, view) },
            uniquingKeysWith: { first, _ in first }
        )
        let checks = boards.values.flatMap { view in
            view.graph.storedLinks(inBoard: view.boardKey).map { link in check(link, in: view) }
        }
        guard views.allSatisfy({ view in view != nil }), checks.allSatisfy({ check in check != nil }) else {
            return nil
        }
        return checks.compactMap(\.self)
    }

    /// Checks one stored link of a board. A link with the current key of its own board reads the graph of that board.
    ///
    /// - Parameters:
    ///   - link: The link.
    ///   - view: The read view of the board that holds the link.
    /// - Returns: The checked link, or `nil` when the engine did not resolve or load the board of the link yet.
    private func check(_ link: StoredLink, in view: BoardView) -> LinkCheck? {
        let key = link.target.boardKey
        let linked =
            key == view.boardKey
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
            Type(LinkCheck.self) {
                Field("board", at: \.board).description(SchemaDescription.linkBoard)
                Field("node", at: \.node).description(SchemaDescription.linkNode)
                Field("field", at: \.field).description(SchemaDescription.linkField)
                Field("target", at: \.target).description(SchemaDescription.linkTarget)
                Field("status", at: \.status).description(SchemaDescription.linkStatus)
                Field("currentName", at: \.currentName).description(SchemaDescription.linkCurrentName)
            }
        }
    }
}
