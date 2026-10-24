import Foundation

/// Loads the related boards of some requests, and gives the new related boards of a run (plan.md §6.6). The new
/// value must answer each request.
typealias RelatedBoardLoad = @Sendable (RelatedBoards, Set<BoardRequest>) async throws -> RelatedBoards

/// Stores the sessions of the related boards that a commit attempt changed, by the canonical path of their repo
/// directory, and gives the related boards of the next run (plan.md §5.4 step 5, §6.6).
typealias RelatedBoardStore = @Sendable ([String: CommitSession], RelatedBoards) async -> RelatedBoards

/// One read that a run of a call asks of the related boards (plan.md §6.6).
enum BoardRequest: Hashable, Sendable {
    /// The board that a board ref names: a board key, a repo directory name, a path, or the URI of a board.
    case board(String)

    /// Each copy of the current scan index of the host, for `Query.boards`.
    case allCopies

    /// Each copy with a key that the table of the host has loaded, for `undo` and `redo` of a transaction that
    /// changed a board with that key (plan.md §6.5, many boards; divergence.md X5). Each worktree of a repo has its
    /// own board with the same key, so the key alone does not tell which copy the transaction changed.
    case loadedCopies(key: String)

    /// `true` when the answer reads the scan index of the host: a board ref, or the list of `Query.boards`. The
    /// response of such a run warns about the board IDs that more than one board outside git has in the index
    /// (``SharedBoardID``).
    var readsScanIndex: Bool {
        switch self {
        case .board, .allCopies: true
        case .loadedCopies: false
        }
    }
}

/// What the related boards of a run know of the target of a cross-board dependency (divergence.md Q3). The write
/// stores the dependency in each state. Only the warning of the response depends on the state.
enum DependencyTargetState: Sendable {
    /// A loaded board has the task, live or tombstoned.
    case found

    /// The board is found and loaded, and it has no task for the URI.
    case missingTask

    /// The scan finds no board for the key of the URI. The repo can be absent on this machine.
    case boardNotFound

    /// The run does not know yet: the engine did not resolve the key, or the board cannot be read. A board that
    /// cannot be read has a warning of its own (divergence.md Q7).
    case unknown
}

/// One copy in the list of `Query.boards` (plan.md §6.6).
struct ListedCopy: Sendable {
    /// The board of the copy: the current board, a copy of a related repo, or a copy whose board cannot be read.
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

    /// The events of the board by node: the source of `Task.timeline` (divergence.md §23).
    let logs: NodeLogs

    /// The readiness cache of the board, which its live graph keeps (divergence.md §16 Gap 3).
    let readiness: ReadinessCache

    /// The cursor of the change log of the board at this read (KANBAN-7), or `nil` when the read gave no cursor. The
    /// root `cursor` and `Board.cursor` give it.
    let cursor: String?

    /// Gives this source as the source of a read at one cursor of the change log of the board.
    ///
    /// - Parameter cursor: The cursor of the change log at the read, or `nil` for no cursor.
    /// - Returns: The source with the cursor.
    func reading(atCursor cursor: String?) -> BoardSource {
        BoardSource(
            directory: directory,
            search: search,
            events: events,
            logs: logs,
            readiness: readiness,
            cursor: cursor
        )
    }
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
        node(for: ref, as: TaskNode.self)
    }

    /// Finds the node of one type for a local ref, live or tombstoned.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the node.
    ///   - type: The state type of the node, for example `ActorNode.self`.
    /// - Returns: The slot and the state of the node, or `nil` when the graph has no node of the type for the ref.
    func node<State: NodeState>(for ref: LocalRef, as type: State.Type) -> (slot: Int, state: State)? {
        graph.slot(for: ref).flatMap { slot in
            graph.node(at: slot, as: type).map { node in (slot, node) }
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

    /// The board IDs that more than one board outside git has in the scan index that the run read (divergence.md
    /// M9). The response of the run has one warning for each of them.
    private(set) var sharedBoardIDs: [SharedBoardID] = []

    /// The board that each resolved board ref names, by the ref as the call wrote it.
    private var resolutions: [String: BoardResolution] = [:]

    /// The list of `Query.boards`, or `nil` until the engine scans for it.
    private var listing: [ListedCopy]?

    /// The copies that the table of the host has loaded, by the key that the run asked for.
    private var keyCopies: [String: [BoardResolution]] = [:]

    /// The loaded related boards as the reads of the run see them, by the canonical path of their repo directory.
    private var boards: [String: BoardSnapshot] = [:]

    /// The session of each loaded related board, by the canonical path of its repo directory. A mutation on a
    /// related board makes its working copy from the session (plan.md §6.6).
    private var sessions: [String: CommitSession] = [:]

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

    /// Gives this value with the working graph of each related board that the run changed, so that the reads of the
    /// run see the changes of the run.
    ///
    /// - Parameter changed: The working copy of each related board that the run changed.
    /// - Returns: The value with the working graphs.
    func with(working changed: some Sequence<RelatedWork>) -> RelatedBoards {
        changed.reduce(self) { related, work in related.with(board: work.snapshot, atPath: work.path) }
    }

    /// Gives this value with one loaded related board as the reads see it, for example the graph of the board just
    /// before a change of the change feed (plan.md §6.7).
    ///
    /// - Parameters:
    ///   - board: The board.
    ///   - path: The canonical path of the repo directory of the board.
    /// - Returns: The value with the board.
    func with(board: BoardSnapshot, atPath path: String) -> RelatedBoards {
        var related = self
        related.boards[path] = board
        return related
    }

    /// Gives this value as the reads of one loaded related board see it, for example the resolvers of an event of a
    /// subscriber on that board (plan.md §6.7): that board is the current board, and the current board of this value
    /// is a related board. Each key then reads the board that it names: the key of the old current board reads the
    /// old current board, and the key of the new current board reads the new current board.
    ///
    /// The value has no session for the new current board, and no session for the old current board. Thus it serves
    /// reads only.
    ///
    /// - Parameters:
    ///   - path: The canonical path of the repo directory of the loaded related board.
    ///   - formerCurrent: The copy of the repo of the current board of this value.
    /// - Returns: The value with the board at `path` as its current board.
    func centered(onBoardAt path: String, movingCurrentTo formerCurrent: BoardCopy) -> RelatedBoards {
        let recenter = { (resolution: BoardResolution) in
            Self.resolution(resolution, centeredOnBoardAt: path, movingCurrentTo: formerCurrent)
        }
        var related = self
        related.current = boards[path]
        related.boards[path] = nil
        related.boards[formerCurrent.directory.canonicalPath] = current
        related.sessions[path] = nil
        related.resolutions = resolutions.mapValues(recenter)
        related.listing = listing?.map { listed in
            ListedCopy(board: recenter(listed.board), isEnabled: listed.isEnabled)
        }
        related.keyCopies = keyCopies.mapValues { copies in copies.map(recenter) }
        return related
    }

    /// Gives a resolution as the reads of one loaded related board see it.
    ///
    /// - Parameters:
    ///   - resolution: The resolution as the reads of the current board see it.
    ///   - path: The canonical path of the repo directory of the loaded related board.
    ///   - formerCurrent: The copy of the repo of the current board.
    /// - Returns: The copy of the old current board for ``BoardResolution/current``, ``BoardResolution/current`` for
    ///   the copy at `path`, and the same resolution for each other board.
    private static func resolution(
        _ resolution: BoardResolution,
        centeredOnBoardAt path: String,
        movingCurrentTo formerCurrent: BoardCopy
    ) -> BoardResolution {
        switch resolution {
        case .current:
            .copy(formerCurrent)
        case .copy(let copy) where copy.directory.canonicalPath == path:
            .current
        case .copy, .notFound, .unreadable:
            resolution
        }
    }

    /// Gives the session of a loaded copy of a related repo.
    ///
    /// - Parameter copy: The copy.
    /// - Returns: The session, or `nil` when the engine did not load the copy.
    func session(of copy: BoardCopy) -> CommitSession? {
        session(atPath: copy.directory.canonicalPath)
    }

    /// Gives the session of a loaded related board.
    ///
    /// - Parameter path: The canonical path of the repo directory of the board.
    /// - Returns: The session, or `nil` when the engine did not load the board.
    func session(atPath path: String) -> CommitSession? {
        sessions[path]
    }

    /// The session of each loaded related board with the canonical path of its repo directory, in the sort order of
    /// the path. `undo` and `redo` with no board ref search these boards (plan.md §6.5, scope).
    var loadedSessions: [(path: String, session: CommitSession)] {
        sessions.sorted { lhs, rhs in lhs.key < rhs.key }.map { path, session in (path, session) }
    }

    // MARK: - Reads

    /// Gives the board that a board ref names.
    ///
    /// - Parameter reference: The board ref.
    /// - Returns: The board, or `nil` when the engine did not resolve the ref yet. A value that cannot load gives
    ///   ``BoardResolution/notFound`` for an unknown ref.
    func resolution(ofBoard reference: String) -> BoardResolution? {
        answer(resolutions[reference], otherwise: .notFound)
    }

    /// The list of `Query.boards`, or `nil` when the engine did not scan for it yet. A value that cannot load gives
    /// an empty list.
    var copies: [ListedCopy]? {
        answer(listing, otherwise: [])
    }

    /// Gives the copies with a key that the table of the host has loaded (plan.md §6.5, many boards).
    ///
    /// - Parameter key: The key, with the host in lowercase.
    /// - Returns: The copies, or `nil` when the engine did not read the table for the key yet. A value that cannot
    ///   load gives an empty list.
    func loadedCopies(ofKey key: String) -> [BoardResolution]? {
        answer(keyCopies[key], otherwise: [])
    }

    /// Gives the answer of a read from a stored value: the stored value when the engine found it, `nil` when the
    /// engine can still load it, or the empty value when the value cannot load.
    ///
    /// - Parameters:
    ///   - stored: The value that the engine stored, or `nil` when it stored none yet.
    ///   - empty: The value to give when the value cannot load.
    /// - Returns: The stored value, `nil` when the engine did not load the value yet, or `empty`.
    private func answer<Value>(_ stored: Value?, otherwise empty: Value) -> Value? {
        stored ?? (canLoad ? nil : empty)
    }

    /// Gives the loaded board of a resolved board ref.
    ///
    /// - Parameter resolution: The board.
    /// - Returns: The loaded board, or `nil` when the board is not found, cannot be read, or is not loaded.
    func board(resolvedAs resolution: BoardResolution) -> BoardSnapshot? {
        switch resolution {
        case .current: current
        case .copy(let copy): boards[copy.directory.canonicalPath]
        case .notFound, .unreadable: nil
        }
    }

    /// Each related board that the run reached and that cannot be read: by a board ref, by a dependency, or in the
    /// list of `Query.boards` (divergence.md Q7). Each board is one time in the list, in the sort order of the path
    /// of its repo directory.
    var unreadableBoards: [UnreadableBoard] {
        let named = resolutions.values.compactMap(\.unreadableBoard)
        let listed = (listing ?? []).compactMap(\.board.unreadableBoard)
        let byPath = Dictionary(
            (named + listed).map { board in (board.copy.directory.canonicalPath, board) },
            uniquingKeysWith: { first, _ in first }
        )
        return byPath.keys.sorted().compactMap { path in byPath[path] }
    }

    /// Each board ref of the run that names a loaded board by an old name (divergence.md M9): a ref of the call, a
    /// cross-board dependency, or an assignee URI. Each old name is one time in the list, in the sort order of the
    /// name.
    var oldBoardNames: [OldBoardName] {
        let named = resolutions.compactMap { reference, resolution in
            BoardIndex.boardKey(in: reference.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { key in
                board(resolvedAs: resolution)?.oldName(named: key)
            }
        }
        return Set(named).sorted { lhs, rhs in lhs.name < rhs.name }
    }

    /// Finds the task of a stored ref to a node of a different board.
    ///
    /// - Parameter ref: The stored ref.
    /// - Returns: The board, the slot, and the state of the task, live or tombstoned. `nil` for a local ref, and for
    ///   a task that no loaded board has.
    func task(for ref: StoredRef) -> (board: BoardSnapshot, slot: Int, state: TaskNode)? {
        node(for: ref, as: TaskNode.self)
    }

    /// Finds the node of one type for a stored ref to a node of a different board, for example the actor of an
    /// assignee that a move or a copy carried from a different board (divergence.md Q21).
    ///
    /// - Parameters:
    ///   - ref: The stored ref.
    ///   - type: The state type of the node, for example `ActorNode.self`.
    /// - Returns: The board, the slot, and the state of the node, live or tombstoned. `nil` for a local ref, and for a
    ///   node that no loaded board has.
    func node<State: NodeState>(
        for ref: StoredRef,
        as type: State.Type
    ) -> (board: BoardSnapshot, slot: Int, state: State)? {
        guard
            case .remote(let uri) = ref,
            let board = board(forKey: uri.boardKey),
            let node = board.node(for: uri.ref, as: type)
        else {
            return nil
        }
        return (board, node.slot, node.state)
    }

    /// Gives the loaded board that the key of a cross-board ref names: the board that each read of a task of the key
    /// reads.
    ///
    /// - Parameter key: The board key of a URI, as the URI holds it.
    /// - Returns: The board, or `nil` when no loaded board has the key.
    func board(forKey key: String) -> BoardSnapshot? {
        resolution(ofBoard: key).flatMap(board(resolvedAs:))
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

    /// Tells what the run knows of the target of a cross-board dependency that a field writes (divergence.md Q3).
    ///
    /// - Parameter uri: The full URI of the target, with the key of a different board.
    /// - Returns: The state of the target. A key that the engine did not resolve yet, and a board that cannot be
    ///   read, give ``DependencyTargetState/unknown``.
    func state(ofDependencyOn uri: NodeURI) -> DependencyTargetState {
        guard let resolution = resolution(ofBoard: uri.boardKey) else {
            return .unknown
        }
        switch resolution {
        case .notFound:
            return .boardNotFound
        case .unreadable:
            return .unknown
        case .current, .copy:
            guard let board = board(resolvedAs: resolution) else {
                return .unknown
            }
            return board.task(for: uri.ref) == nil ? .missingTask : .found
        }
    }

    // MARK: - Requests

    /// Gives the requests for the boards that the cross-board refs of a graph and of each loaded board name: the
    /// cross-board dependencies, and the assignees that are actors of a different board (divergence.md Q21).
    ///
    /// - Parameters:
    ///   - graph: The graph of a board.
    ///   - key: The current key of that board.
    /// - Returns: One request for the key of each board that a dependency or an assignee names.
    func crossBoardRequests(of graph: Graph, inBoard key: String) -> Set<BoardRequest> {
        Self.crossBoardRequests(of: graph, inBoard: key).union(loadedCrossBoardRequests)
    }

    /// The requests for the boards that the cross-board dependencies and assignees of the loaded boards name.
    var loadedCrossBoardRequests: Set<BoardRequest> {
        Set(boards.values.flatMap { board in Self.crossBoardRequests(of: board.graph, inBoard: board.key) })
    }

    /// Tells if the value answers each of some requests.
    ///
    /// - Parameter requests: The requests.
    /// - Returns: `true` when each board ref has a resolution and a found board is loaded, the list of
    ///   `Query.boards` is there when a request asks for it, and the loaded copies of each asked key are there.
    func satisfies(_ requests: Set<BoardRequest>) -> Bool {
        requests.allSatisfy { request in
            switch request {
            case .board(let reference):
                resolution(ofBoard: reference).map(isLoaded) ?? false
            case .allCopies:
                copies != nil
            case .loadedCopies(let key):
                loadedCopies(ofKey: key)?.allSatisfy(isLoaded) ?? false
            }
        }
    }

    /// Tells if a read of a resolved board needs no load: the board of a copy is loaded.
    ///
    /// - Parameter resolution: The board.
    /// - Returns: `true` when the board is not a copy, or when the copy is loaded.
    private func isLoaded(_ resolution: BoardResolution) -> Bool {
        guard case .copy = resolution else {
            return true
        }
        return board(resolvedAs: resolution) != nil
    }

    /// Gives the requests for the boards that the cross-board dependencies and assignees of one graph name.
    ///
    /// - Parameters:
    ///   - graph: The graph of a board.
    ///   - key: The current key of that board.
    /// - Returns: One request for the key of each board that a dependency or an assignee names.
    private static func crossBoardRequests(of graph: Graph, inBoard key: String) -> Set<BoardRequest> {
        Set(graph.remoteDependencyKeys(inBoard: key).union(graph.remoteAssigneeKeys).map(BoardRequest.board))
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

    /// Records the copies with a key that the table of the host has loaded.
    ///
    /// - Parameters:
    ///   - copies: The copies.
    ///   - key: The key, with the host in lowercase.
    mutating func record(loadedCopies copies: [BoardResolution], ofKey key: String) {
        keyCopies[key] = copies
    }

    /// Records the board IDs that more than one board outside git has in the scan index that the run read.
    ///
    /// - Parameter shared: The shared board IDs, in the order of the first copy with each ID.
    mutating func record(sharedBoardIDs shared: [SharedBoardID]) {
        sharedBoardIDs = shared
    }

    /// Records the loaded related boards and the places of the scan.
    ///
    /// - Parameters:
    ///   - loaded: The session of each loaded related board, by the canonical path of its repo directory.
    ///   - places: The places that the scan looks in, in scan order.
    mutating func install(boards loaded: [String: CommitSession], searchRoots places: [URL]) {
        sessions = loaded
        boards = loaded.mapValues(\.snapshot)
        searchRoots = places
    }
}

extension Graph {
    /// The board keys of the assignees of the tasks of the graph that are actors of a different board, as the URIs
    /// hold them. A move or a copy to a different board stores each assignee as the full URI of the actor on the old
    /// board (divergence.md Q21), and `Task.assignees` reads that actor from its own board.
    var remoteAssigneeKeys: Set<String> {
        remoteBoardKeys(of: \.assignees)
    }

    /// Gives the board keys of the targets of one edge list of the tasks of the graph that are nodes of a different
    /// board, as the URIs hold them. A slot or a local ref gives no key.
    ///
    /// - Parameter edges: Gives the edge list of a task, for example its assignees or the targets of its dependencies.
    /// - Returns: The keys.
    func remoteBoardKeys(of edges: (TaskNode) -> [EdgeTarget]) -> Set<String> {
        Set(
            allSlots.compactMap { slot in node(at: slot, as: TaskNode.self) }
                .flatMap(edges)
                .compactMap(\.remoteBoardKey)
        )
    }
}
