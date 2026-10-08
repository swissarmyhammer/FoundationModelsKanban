import Foundation

/// Loads the related boards of some requests, and gives the new related boards of a run (plan.md §6.6). The new
/// value must answer each request.
typealias RelatedBoardLoad = @Sendable (RelatedBoards, Set<BoardRequest>) async throws -> RelatedBoards

/// One read that a run of a call asks of the related boards (plan.md §6.6).
enum BoardRequest: Hashable, Sendable {
    /// The board that a board ref names: a board key, a repo directory name, a path, or the URI of a board.
    case board(String)

    /// Each copy that a new scan finds, for `Query.boards`.
    case allCopies
}

/// One copy in the list of `Query.boards` (plan.md §6.6).
struct ListedCopy: Sendable {
    /// The board of the copy: the current board, or a copy of a related repo.
    let board: BoardResolution

    /// `true` when the copy has `.kanban/board.jsonl`.
    let isEnabled: Bool
}

/// The parts of a loaded board that a read view needs beyond its graph (plan.md §6.4, §6.5, §6.6).
struct BoardSource: Sendable {
    /// The root directory of the repo of the board.
    let directory: URL

    /// The ranked search over the live tasks of the board.
    let search: TaskSearch

    /// The events of the board, in the order of their ids: the source of `Board.history`.
    let events: [Event]
}

/// A loaded board that the read views of one run read: its key, its graph, and its source.
struct BoardSnapshot: Sendable {
    /// The current key of the board.
    let key: String

    /// The graph of the board, with an empty board node in memory when no log has the board node.
    let graph: Graph

    /// The directory, the search, and the events of the board, or `nil` for a board in memory only (a test
    /// fixture).
    let source: BoardSource?

    /// The live columns of the board in board order. A task in the terminal column is done.
    private let columnOrder: ColumnOrder

    /// Makes a loaded board.
    ///
    /// - Parameters:
    ///   - key: The current key of the board.
    ///   - graph: The graph of the board.
    ///   - source: The directory, the search, and the events of the board, or `nil` for a board in memory only.
    init(key: String, graph: Graph, source: BoardSource?) {
        self.key = key
        self.graph = graph
        self.source = source
        columnOrder = ColumnOrder(of: graph)
    }

    /// Makes the read view of the board.
    ///
    /// - Parameter related: The related boards of the run.
    /// - Returns: The read view.
    func view(reading related: RelatedBoards) -> BoardView {
        BoardView(of: graph, inBoard: key, from: source, reading: related)
    }

    /// Finds the task of a local ref, live or tombstoned.
    ///
    /// - Parameter ref: The local ref of the task.
    /// - Returns: The slot and the state of the task, or `nil` when the graph has no task for the ref.
    func task(for ref: LocalRef) -> (slot: Int, state: TaskNode)? {
        graph.slot(for: ref).flatMap { slot in
            graph.node(at: slot, as: TaskNode.self).map { task in (slot, task) }
        }
    }

    /// Tells if a task of the board is done: it shows in the terminal column.
    ///
    /// - Parameter task: A task of the board.
    /// - Returns: `true` when the task is done.
    func isDone(_ task: TaskNode) -> Bool {
        columnOrder.isTerminal(task.column)
    }
}

/// The related boards that one run of a call reads (plan.md §6.6): the board refs that the run resolved, the loaded
/// boards, and the list of `Query.boards`.
///
/// A resolver never loads a board, because a load is async and can fail with an I/O error. When a resolver needs a
/// board that the value does not have, the store records a ``BoardRequest``. After the run, the commit session gives
/// the requests to the engine, which loads the boards, and the call runs again with the new value
/// (``CommitSession/run(readingRelatedBoardsWith:_:)``). A value that cannot load (``unavailable``) answers each
/// unknown ref as not found.
struct RelatedBoards: Sendable {
    /// The value of a run that cannot load a board, for example a test fixture or a read view of a graph rule: no
    /// board ref resolves, and a cross-board dependency is not done.
    static let unavailable = RelatedBoards(canLoad: false)

    /// The empty value of a run of the engine, before the engine loads a board.
    static let loadable = RelatedBoards(canLoad: true)

    /// `true` when the engine loads the boards that the run asks for.
    private let canLoad: Bool

    /// The places that the scan looked in, in scan order, for the `NOT_FOUND` message of a board.
    private(set) var searchRoots: [URL] = []

    /// The board that each resolved board ref names, by the ref as the call wrote it.
    private var resolutions: [String: BoardResolution] = [:]

    /// The list of `Query.boards`, or `nil` until the engine scans for it.
    private var listing: [ListedCopy]?

    /// The loaded related boards, by the canonical path of their repo directory.
    private var boards: [String: BoardSnapshot] = [:]

    /// The current board as the run sees it now, or `nil` when the value has no current board.
    private var current: BoardSnapshot?

    /// Makes an empty value.
    ///
    /// - Parameter canLoad: `true` when the engine loads the boards that the run asks for.
    private init(canLoad: Bool) {
        self.canLoad = canLoad
    }

    /// Gives this value with the current board as the run sees it now.
    ///
    /// - Parameter board: The current board.
    /// - Returns: The value with the board.
    func with(current board: BoardSnapshot) -> RelatedBoards {
        var related = self
        related.current = board
        return related
    }

    // MARK: - Reads

    /// Gives the board that a board ref names.
    ///
    /// - Parameter reference: The board ref.
    /// - Returns: The board, or `nil` when the engine did not resolve the ref yet. A value that cannot load gives
    ///   ``BoardResolution/notFound`` for an unknown ref.
    func resolution(ofBoard reference: String) -> BoardResolution? {
        resolutions[reference] ?? (canLoad ? nil : .notFound)
    }

    /// The list of `Query.boards`, or `nil` when the engine did not scan for it yet. A value that cannot load gives
    /// an empty list.
    var copies: [ListedCopy]? {
        listing ?? (canLoad ? nil : [])
    }

    /// Gives the loaded board of a resolved board ref.
    ///
    /// - Parameter resolution: The board.
    /// - Returns: The loaded board, or `nil` when the board is not found or not loaded.
    func board(resolvedAs resolution: BoardResolution) -> BoardSnapshot? {
        switch resolution {
        case .current: current
        case .copy(let copy): boards[copy.directory.canonicalPath]
        case .notFound: nil
        }
    }

    /// Finds the task of a stored ref to a node of a different board.
    ///
    /// - Parameter ref: The stored ref.
    /// - Returns: The board, the slot, and the state of the task, live or tombstoned. `nil` for a local ref, and for
    ///   a task that no loaded board has.
    func task(for ref: StoredRef) -> (board: BoardSnapshot, slot: Int, state: TaskNode)? {
        guard
            case .remote(let uri) = ref,
            let board = resolution(ofBoard: uri.boardKey).flatMap(board(resolvedAs:)),
            let task = board.task(for: uri.ref)
        else {
            return nil
        }
        return (board, task.slot, task.state)
    }

    /// Tells if a cross-board dependency is done: its task shows in the terminal column of its board. A task that no
    /// loaded board has is not done (plan.md §3.3, rule 4).
    ///
    /// - Parameter ref: The stored ref of the target of the dependency.
    /// - Returns: `true` when the target is done.
    func isDone(_ ref: StoredRef) -> Bool {
        task(for: ref).map { found in found.board.isDone(found.state) } ?? false
    }

    /// Tells if the target of a cross-board dependency is a tombstone. A dependency on a tombstone is ignored
    /// (plan.md §3.3, rule 3).
    ///
    /// - Parameter ref: The stored ref of the target of the dependency.
    /// - Returns: `true` when a loaded board has the task and the task is a tombstone.
    func isTombstone(_ ref: StoredRef) -> Bool {
        task(for: ref)?.state.fields.isDeleted == true
    }

    // MARK: - Requests

    /// Gives the requests for the boards that the cross-board dependencies of a graph and of each loaded board name.
    ///
    /// - Parameters:
    ///   - graph: The graph of a board.
    ///   - key: The current key of that board.
    /// - Returns: One request for the key of each board that a dependency names.
    func dependencyRequests(of graph: Graph, inBoard key: String) -> Set<BoardRequest> {
        Self.dependencyRequests(of: graph, inBoard: key).union(loadedDependencyRequests)
    }

    /// The requests for the boards that the cross-board dependencies of the loaded boards name.
    var loadedDependencyRequests: Set<BoardRequest> {
        Set(boards.values.flatMap { board in Self.dependencyRequests(of: board.graph, inBoard: board.key) })
    }

    /// Tells if the value answers each of some requests.
    ///
    /// - Parameter requests: The requests.
    /// - Returns: `true` when each board ref has a resolution and a found board is loaded, and the list of
    ///   `Query.boards` is there when a request asks for it.
    func satisfies(_ requests: Set<BoardRequest>) -> Bool {
        requests.allSatisfy { request in
            switch request {
            case .board(let reference):
                isAnswered(reference)
            case .allCopies:
                copies != nil
            }
        }
    }

    /// Tells if the value answers a board ref: the ref has a resolution, and the board of a copy is loaded.
    ///
    /// - Parameter reference: The board ref.
    /// - Returns: `true` when a read of the ref needs no load.
    private func isAnswered(_ reference: String) -> Bool {
        guard let resolution = resolution(ofBoard: reference) else {
            return false
        }
        guard case .copy = resolution else {
            return true
        }
        return board(resolvedAs: resolution) != nil
    }

    /// Gives the requests for the boards that the cross-board dependencies of one graph name.
    ///
    /// - Parameters:
    ///   - graph: The graph of a board.
    ///   - key: The current key of that board.
    /// - Returns: One request for the key of each board that a dependency names.
    private static func dependencyRequests(of graph: Graph, inBoard key: String) -> Set<BoardRequest> {
        let targets = graph.allSlots
            .compactMap { slot in graph.node(at: slot, as: TaskNode.self) }
            .flatMap { task in graph.dependencies(of: task, inBoard: key) }
        return Set(
            targets.compactMap { target in
                guard case .unresolved(.remote(let uri)) = target else {
                    return nil
                }
                return .board(uri.boardKey)
            }
        )
    }

    // MARK: - Writes of the engine

    /// Records the board that a board ref names.
    ///
    /// - Parameters:
    ///   - resolution: The board.
    ///   - reference: The board ref.
    mutating func record(_ resolution: BoardResolution, forBoard reference: String) {
        resolutions[reference] = resolution
    }

    /// Records the list of `Query.boards`.
    ///
    /// - Parameter copies: The copies, in scan order.
    mutating func record(listing copies: [ListedCopy]) {
        listing = copies
    }

    /// Records the loaded related boards and the places of the scan.
    ///
    /// - Parameters:
    ///   - loaded: The loaded related boards, by the canonical path of their repo directory.
    ///   - places: The places that the scan looks in, in scan order.
    mutating func install(boards loaded: [String: BoardSnapshot], searchRoots places: [URL]) {
        boards = loaded
        searchRoots = places
    }
}
