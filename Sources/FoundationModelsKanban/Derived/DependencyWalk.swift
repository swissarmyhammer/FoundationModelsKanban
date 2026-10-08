import Foundation

/// A walk over the `dependsOn` edges and the dependency markers of the tasks of many boards (plan.md §3.3 rule 6,
/// §6.6). A mutation that writes a dependency uses it to refuse a cycle.
///
/// The walk reads the board of the field from the working graph of the field, and each other board from the related
/// boards of the run. It records the repo directory of each other board that it reads, so that the commit locks and
/// checks that board too (plan.md §5.4 steps 4.4 and 5.1). A target that no loaded board has ends its path of the
/// walk. The walk stops at each task that it already visited, so it always ends.
struct DependencyWalk {
    /// The current key of the board of the field.
    private let boardKey: String

    /// The working graph of the board of the field.
    private let graph: Graph

    /// The related boards of the run, as the field reads them.
    private let related: RelatedBoards

    /// The readiness of each board that the walk read, by the current key of the board. It holds the dependencies of
    /// each task of the board.
    private var readiness: [String: Readiness] = [:]

    /// The canonical paths of the repo directories of the other boards that the walk read.
    private(set) var readBoards: Set<String> = []

    /// Makes a walk.
    ///
    /// - Parameters:
    ///   - graph: The working graph of the board of the field.
    ///   - boardKey: The current key of the board of the field.
    ///   - related: The related boards of the run, as the field reads them.
    init(of graph: Graph, inBoard boardKey: String, reading related: RelatedBoards) {
        self.graph = graph
        self.boardKey = boardKey
        self.related = related
    }

    /// Finds the shortest `dependsOn` cycle through a task of the board of the field.
    ///
    /// - Parameter ref: The local ref of the task.
    /// - Returns: The tasks on the cycle: the task, each task on the walk, and the task again. `nil` when no walk from
    ///   the task comes back to the task.
    mutating func cycle(throughTask ref: LocalRef) -> [NodeURI]? {
        let start = NodeURI(boardKey: boardKey, ref: ref)
        var parents: [NodeURI: NodeURI] = [:]
        var pending = [start]
        var index = pending.startIndex
        while index < pending.endIndex {
            let current = pending[index]
            index += 1
            for next in dependencies(of: current) where parents[next] == nil {
                guard next != start else {
                    return Array(sequence(first: current) { step in step == start ? nil : parents[step] }.reversed())
                        + [start]
                }
                parents[next] = current
                pending.append(next)
            }
        }
        return nil
    }

    /// Gives the text of each task of a cycle, for the error of the cycle: the short id of a task of the board of the
    /// field, and the full URI of a task of a different board.
    ///
    /// - Parameter cycle: The tasks of the cycle.
    /// - Returns: The texts, in the order of the cycle.
    func path(of cycle: [NodeURI]) -> [String] {
        cycle.map { task in
            guard task.boardKey == boardKey, let localID = task.ref.localID else {
                return task.description
            }
            return "\(ShortID.sigil)\(ShortID(ofULIDString: localID).value)"
        }
    }

    /// Gives the dependencies of a task that a loaded board has.
    ///
    /// - Parameter task: The URI of the task.
    /// - Returns: The URI of each target of a dependency that is not a tombstone. A target of an unknown local ref is
    ///   not in the list. A task that no loaded board has gives no dependency.
    private mutating func dependencies(of task: NodeURI) -> [NodeURI] {
        guard let board = board(holding: task), let slot = board.graph.slot(for: task.ref) else {
            return []
        }
        let readiness = readiness(of: board)
        return readiness.dependencies(ofTaskAt: slot).compactMap { target in
            switch target {
            case .slot(let targetSlot):
                board.graph.node(at: targetSlot).map { node in NodeURI(boardKey: board.key, ref: node.ref) }
            case .unresolved(.remote(let uri)):
                uri
            case .unresolved(.local):
                nil
            }
        }
    }

    /// Finds the board of a task: the working graph of the field for the key of the board of the field, else the
    /// loaded board of the key. The walk records the repo directory of each other board that it finds.
    ///
    /// - Parameter task: The URI of the task.
    /// - Returns: The current key and the graph of the board, or `nil` when no loaded board has the task.
    private mutating func board(holding task: NodeURI) -> (key: String, graph: Graph)? {
        guard task.boardKey != boardKey else {
            return (boardKey, graph)
        }
        guard let found = related.task(for: .remote(task)) else {
            return nil
        }
        if let directory = found.board.source?.directory {
            readBoards.insert(directory.canonicalPath)
        }
        return (found.board.key, found.board.graph)
    }

    /// Gives the readiness of a board, and keeps it for the next task of the board.
    ///
    /// - Parameter board: The current key and the graph of the board.
    /// - Returns: The readiness.
    private mutating func readiness(of board: (key: String, graph: Graph)) -> Readiness {
        if let known = readiness[board.key] {
            return known
        }
        let made = Readiness(of: board.graph, inBoard: board.key, reading: related)
        readiness[board.key] = made
        return made
    }
}
