import Foundation
import Synchronization

/// The readiness of the tasks of one board, kept in memory with the live graph of the board (divergence.md §2
/// "Performance", §16 Gap 3, K9).
///
/// A read gives its graph, the current key of the board, and its related boards. When these are the inputs of the
/// kept readiness, the read takes the kept readiness and walks nothing. Else the cache finds what changed, computes
/// again only the tasks that the change can affect, and keeps the new readiness (``ReadinessState``). Each of these
/// changes the inputs of the next read:
///
/// - a write: the commit makes the working copy the live graph;
/// - an apply of changed files from the file watcher, also a held transaction that now applies on a node whose file
///   did not change, and a full reload;
/// - a change of a related board that a cross-board dependency reads.
///
/// The result is always the same as a full walk. Each copy of the live graph shares the cache, so the cache is a
/// class. A lock keeps its state, because the read views of many sessions read it at the same time.
final class ReadinessCache: Sendable {
    /// The kept readiness and the number of walks, behind a lock.
    private let store = Mutex(Store())

    /// The number of dependency walks that the readiness of the board did since the board loaded. A test reads it to
    /// prove that a read with no change walks nothing.
    var walkCount: Int {
        store.withLock { stored in stored.walkCount }
    }

    /// Gives the readiness of the tasks of a graph: the kept readiness when its inputs are the same, else the
    /// readiness that the cache computes from the kept readiness, or from nothing, and then keeps.
    ///
    /// - Parameters:
    ///   - graph: The graph of the board, as the read sees it.
    ///   - key: The current key of the board.
    ///   - related: The related boards that the cross-board dependencies read.
    /// - Returns: The readiness.
    func readiness(of graph: Graph, inBoard key: String, reading related: RelatedBoards) -> ReadinessState {
        let known = store.withLock { stored in stored.state }
        if let known, known.isCurrent(for: graph, inBoard: key, reading: related) {
            return known
        }
        let next = known.flatMap { state in state.updated(to: graph, inBoard: key, reading: related) }
            ?? ReadinessState(computing: graph, inBoard: key, reading: related)
        store.withLock { stored in
            stored.state = next
            stored.walkCount += next.walkCount
        }
        return next
    }

    /// The state of the cache.
    private struct Store {
        /// The readiness that the cache keeps, or `nil` before the first read.
        var state: ReadinessState?

        /// The number of dependency walks since the board loaded.
        var walkCount: Int = .zero
    }
}

// MARK: - State

/// The readiness of the tasks of one board for one set of inputs: the dependencies and the blockers of each task, the
/// graph and the related boards that the computation read, and the dependency index that finds the tasks that a change
/// can affect.
struct ReadinessState: Sendable {
    /// The current key of the board.
    let boardKey: String

    /// The graph of the board that the computation read.
    let graph: Graph

    /// The dependencies of each task, live or tombstoned, by the slot of the task
    /// (``Graph/liveDependencies(inBoard:reading:)``).
    let dependencies: [Int: [EdgeTarget]]

    /// The dependencies that block each task, live or tombstoned, by the slot of the task
    /// (``BlockerWalk/blockers(ofTaskAt:)``).
    let blockers: [Int: [EdgeTarget]]

    /// The number of dependency walks of the computation that made this state.
    let walkCount: Int

    /// The related boards that the computation read.
    private let reads: RelatedReads

    /// The dependency edges of the tasks of the boards that the computation read, both ways.
    private let index: DependencyIndex

    /// Computes the readiness of each task of a graph: a full walk.
    ///
    /// - Parameters:
    ///   - graph: The graph of the board.
    ///   - key: The current key of the board.
    ///   - related: The related boards that the cross-board dependencies read.
    init(computing graph: Graph, inBoard key: String, reading related: RelatedBoards) {
        let reads = RelatedReads(of: graph, inBoard: key, reading: related)
        let dependencies = graph.liveDependencies(inBoard: key, reading: related)
        self.init(
            graph: graph,
            inBoard: key,
            reading: related,
            along: reads,
            indexedBy: DependencyIndex(of: reads.indexedGraphs(with: graph, inBoard: key), along: reads),
            with: dependencies,
            computing: dependencies.keys,
            keeping: [:]
        )
    }

    /// Makes a state, and computes the blockers of some tasks.
    ///
    /// - Parameters:
    ///   - graph: The graph of the board.
    ///   - key: The current key of the board.
    ///   - related: The related boards that the cross-board dependencies read.
    ///   - reads: The related boards that the computation read.
    ///   - index: The dependency edges of the tasks of the read boards.
    ///   - dependencies: The dependencies of each task.
    ///   - slots: The slots of the tasks whose blockers to compute.
    ///   - blockers: The blockers of the other tasks, which stay as they are.
    private init(
        graph: Graph,
        inBoard key: String,
        reading related: RelatedBoards,
        along reads: RelatedReads,
        indexedBy index: DependencyIndex,
        with dependencies: [Int: [EdgeTarget]],
        computing slots: some Sequence<Int>,
        keeping blockers: [Int: [EdgeTarget]]
    ) {
        let walk = BlockerWalk(of: graph, inBoard: key, reading: related, with: dependencies)
        let computed = slots.map { slot in (slot: slot, blockers: walk.blockers(ofTaskAt: slot)) }
        boardKey = key
        self.graph = graph
        self.dependencies = dependencies
        let computedBlockers = computed.map { task in (task.slot, task.blockers.targets) }
        self.blockers = blockers.merging(computedBlockers) { _, new in new }
        walkCount = computed.map(\.blockers.walkCount).reduce(.zero, +)
        self.reads = reads
        self.index = index
    }

    /// Tells if a read has the inputs of this state: the same graph, the same key, and the same graph for each
    /// related board that the computation read. A graph that shares its storage with the kept graph compares at once.
    ///
    /// - Parameters:
    ///   - graph: The graph of the board, as the read sees it.
    ///   - key: The current key of the board.
    ///   - related: The related boards of the read.
    /// - Returns: `true` when the state is the readiness of the read.
    func isCurrent(for graph: Graph, inBoard key: String, reading related: RelatedBoards) -> Bool {
        key == boardKey && graph == self.graph && reads.isCurrent(reading: related)
    }

    /// Gives the readiness of new inputs. Only the tasks that the change can affect walk again: each changed task,
    /// and each task that depends on a changed node, also across boards. A change of a column of the board, a change
    /// of the board that a key names, a graph that a full reload built again, a new key, and a changed task with a
    /// dependency on a board that the computation did not read need a full walk, which the caller does
    /// (``ReadinessCache/readiness(of:inBoard:reading:)``).
    ///
    /// - Parameters:
    ///   - newGraph: The graph of the board, as the read sees it.
    ///   - key: The current key of the board.
    ///   - related: The related boards of the read.
    /// - Returns: The readiness, the same as a full walk of the new inputs gives, or `nil` when the change needs a
    ///   full walk.
    func updated(to newGraph: Graph, inBoard key: String, reading related: RelatedBoards) -> ReadinessState? {
        guard
            key == boardKey,
            let ownRefs = newGraph.changedRefs(since: graph),
            !ownRefs.contains(where: { ref in ref.nodeType == .column }),
            let relatedChange = reads.change(reading: related)
        else {
            return nil
        }
        let positions = Set(ownRefs.map { ref in NodeURI(boardKey: key, ref: ref) }).union(relatedChange.positions)
        let graphs = relatedChange.reads.indexedGraphs(with: newGraph, inBoard: key)
        guard let newIndex = index.updating(positions, in: graphs, along: relatedChange.reads) else {
            return nil
        }
        let touched = Set(
            newIndex.closure(of: positions)
                .filter { position in position.boardKey == key }
                .compactMap { position in newGraph.slot(for: position.ref) }
        )
        let fresh = touched.compactMap { slot in
            newGraph.liveDependencies(ofTaskAt: slot, inBoard: key, reading: related).map { targets in (slot, targets) }
        }
        let kept = dependencies.filter { slot, _ in !touched.contains(slot) }
        return ReadinessState(
            graph: newGraph,
            inBoard: key,
            reading: related,
            along: relatedChange.reads,
            indexedBy: newIndex,
            with: kept.merging(fresh) { _, new in new },
            computing: fresh.map { slot, _ in slot },
            keeping: blockers.filter { slot, _ in !touched.contains(slot) }
        )
    }
}

// MARK: - Related reads

/// One related board that a readiness read: its current key and its graph.
struct ReadBoard: Equatable, Sendable {
    /// The current key of the board.
    let key: String

    /// The graph of the board.
    let graph: Graph
}

extension ReadBoard {
    /// Finds the related board that the key of a cross-board ref names, as each read of a task of the key finds it
    /// (``RelatedBoards/board(forKey:)``).
    ///
    /// - Parameters:
    ///   - rawKey: The board key of a URI, as the URI holds it.
    ///   - related: The related boards of the read.
    init?(resolving rawKey: String, in related: RelatedBoards) {
        guard let board = related.board(forKey: rawKey) else {
            return nil
        }
        self.init(key: board.key, graph: board.graph)
    }

    /// Lists the nodes of this board that differ from an older graph of the same board, as node positions. When a
    /// column changed, each task of the board is in the list, because the change can make each task done or not done.
    ///
    /// - Parameter older: The board as an older read saw it.
    /// - Returns: The positions, or `nil` when a full reload built the graph again.
    func changedPositions(since older: ReadBoard) -> Set<NodeURI>? {
        guard let refs = graph.changedRefs(since: older.graph) else {
            return nil
        }
        let columnChanged = refs.contains { ref in ref.nodeType == .column }
        let all = columnChanged ? refs.union(graph.taskRefs).union(older.graph.taskRefs) : refs
        return Set(all.map { ref in NodeURI(boardKey: key, ref: ref) })
    }
}

/// The related boards that a readiness read, by the key of a cross-board ref as the ref holds it: each board that a
/// cross-board dependency of the board names, and each board that a cross-board dependency of such a board names.
struct RelatedReads: Sendable {
    /// The loaded board of each key that names one.
    private var boards: [String: ReadBoard] = [:]

    /// The keys that name no loaded board.
    private var missingKeys: Set<String> = []

    /// Finds the related boards that a readiness of a graph reads.
    ///
    /// - Parameters:
    ///   - graph: The graph of the board.
    ///   - key: The current key of the board.
    ///   - related: The related boards of the read.
    init(of graph: Graph, inBoard key: String, reading related: RelatedBoards) {
        var pending = Array(graph.remoteDependencyKeys(inBoard: key))
        while let rawKey = pending.popLast() {
            guard !knows(rawKey) else {
                continue
            }
            guard let board = ReadBoard(resolving: rawKey, in: related) else {
                missingKeys.insert(rawKey)
                continue
            }
            boards[rawKey] = board
            pending += board.graph.remoteDependencyKeys(inBoard: board.key)
        }
    }

    /// Tells if a key is one that the readiness read.
    ///
    /// - Parameter rawKey: The board key of a URI, as the URI holds it.
    /// - Returns: `true` when the readiness read the key.
    func knows(_ rawKey: String) -> Bool {
        boards.keys.contains(rawKey) || missingKeys.contains(rawKey)
    }

    /// Tells if the related boards of a read give the same board, with the same graph, for each key.
    ///
    /// - Parameter related: The related boards of the read.
    /// - Returns: `true` when each key reads the same.
    func isCurrent(reading related: RelatedBoards) -> Bool {
        missingKeysStillMissing(in: related) && loadedBoards(in: related) == boards
    }

    /// Finds the changes of the related boards of a read.
    ///
    /// - Parameter related: The related boards of the read.
    /// - Returns: The reads of the new related boards and the positions of the nodes that changed, or `nil` when a key
    ///   names a different board, or a board that a full reload built again.
    func change(reading related: RelatedBoards) -> (reads: RelatedReads, positions: Set<NodeURI>)? {
        guard missingKeysStillMissing(in: related) else {
            return nil
        }
        let newBoards = loadedBoards(in: related)
        guard
            newBoards.count == boards.count,
            newBoards.allSatisfy({ rawKey, board in boards[rawKey]?.key == board.key })
        else {
            return nil
        }
        let changes = newBoards.map { rawKey, board in boards[rawKey].flatMap(board.changedPositions(since:)) }
        guard let changes = changes.allValues() else {
            return nil
        }
        var reads = self
        reads.boards = newBoards
        return (reads, Set(changes.joined()))
    }

    /// Gives the position of the target of a cross-board ref: the URI with the current key of the board that the key
    /// of the ref names, or the URI as it is when no loaded board has the key.
    ///
    /// - Parameter uri: The URI of the target, as the ref holds it.
    /// - Returns: The position.
    func position(of uri: NodeURI) -> NodeURI {
        boards[uri.boardKey].map { board in NodeURI(boardKey: board.key, ref: uri.ref) } ?? uri
    }

    /// Gives the graphs of the boards whose dependency edges a walk can follow, by the current key of the board: the
    /// graph of the board itself, and each read board with a different key. A walk reads a task with the key of the
    /// board in the graph of the board (``BlockerWalk``).
    ///
    /// - Parameters:
    ///   - graph: The graph of the board.
    ///   - key: The current key of the board.
    /// - Returns: The graphs of each key.
    func indexedGraphs(with graph: Graph, inBoard key: String) -> [String: [Graph]] {
        let related = boards.values.filter { board in board.key != key }
        let byKey = Dictionary(grouping: related, by: \.key).mapValues { boards in
            boards.map(\.graph).reduce(into: [Graph]()) { graphs, graph in
                if !graphs.contains(graph) {
                    graphs.append(graph)
                }
            }
        }
        return byKey.merging([key: [graph]]) { _, own in own }
    }

    /// Tells if each key that named no loaded board still names no loaded board in the related boards of a read.
    ///
    /// - Parameter related: The related boards of the read.
    /// - Returns: `true` when no missing key names a loaded board now.
    private func missingKeysStillMissing(in related: RelatedBoards) -> Bool {
        missingKeys.allSatisfy { rawKey in related.board(forKey: rawKey) == nil }
    }

    /// Finds the board that each key of a loaded board names in the related boards of a read. A key that names no
    /// loaded board now is not in the result.
    ///
    /// - Parameter related: The related boards of the read.
    /// - Returns: The board of each key that still names a loaded board.
    private func loadedBoards(in related: RelatedBoards) -> [String: ReadBoard] {
        Dictionary(
            uniqueKeysWithValues: boards.keys.compactMap { rawKey in
                ReadBoard(resolving: rawKey, in: related).map { board in (rawKey, board) }
            }
        )
    }
}

// MARK: - Dependency index

/// The dependency edges of the tasks of the boards that a readiness read, as node positions: the targets of each
/// task, and the tasks that have an edge to each target. A position is the URI of a node with the current key of its
/// board. The index holds each `dependsOn` edge and each dependency marker, also to a tombstone and to a node that the
/// graph does not have, so that a change of the target finds each task that can change.
struct DependencyIndex: Sendable {
    /// The targets of the dependencies of each task.
    private var targets: [NodeURI: [NodeURI]] = [:]

    /// The tasks that have a dependency on each target.
    private var dependents: [NodeURI: Set<NodeURI>] = [:]

    /// Makes the index of the tasks of some boards.
    ///
    /// - Parameters:
    ///   - graphs: The graphs of the boards, by the current key of the board.
    ///   - reads: The related boards that the readiness read.
    init(of graphs: [String: [Graph]], along reads: RelatedReads) {
        for (key, boardGraphs) in graphs {
            for ref in Set(boardGraphs.flatMap(\.taskRefs)) {
                // The reads hold each key that a task of a read board names, so each replace is complete.
                _ = replaceTargets(of: NodeURI(boardKey: key, ref: ref), in: boardGraphs, along: reads)
            }
        }
    }

    /// Gives the index after a change of some nodes.
    ///
    /// - Parameters:
    ///   - positions: The positions of the changed nodes.
    ///   - graphs: The new graphs of the boards of the index, by the current key of the board.
    ///   - reads: The related boards that the readiness reads now.
    /// - Returns: The index, or `nil` when a changed task has a dependency on a board that the readiness did not read.
    func updating(
        _ positions: Set<NodeURI>,
        in graphs: [String: [Graph]],
        along reads: RelatedReads
    ) -> DependencyIndex? {
        var index = self
        for position in positions {
            guard let boardGraphs = graphs[position.boardKey] else {
                continue
            }
            guard index.replaceTargets(of: position, in: boardGraphs, along: reads) else {
                return nil
            }
        }
        return index
    }

    /// Gives some positions and each task that depends on one of them, also through other tasks.
    ///
    /// - Parameter seeds: The positions.
    /// - Returns: The positions and the dependent tasks.
    func closure(of seeds: Set<NodeURI>) -> Set<NodeURI> {
        var reached = seeds
        var pending = Array(seeds)
        while let position = pending.popLast() {
            for holder in dependents[position, default: []] where reached.insert(holder).inserted {
                pending.append(holder)
            }
        }
        return reached
    }

    /// Replaces the targets of one task with its dependency edges in the graphs of its board. A node that is not a
    /// task has no targets.
    ///
    /// - Parameters:
    ///   - holder: The position of the task.
    ///   - graphs: The graphs of the board of the task.
    ///   - reads: The related boards that the readiness reads.
    /// - Returns: `false` when the task has a dependency on a board that the readiness did not read. Then the index
    ///   is not complete.
    private mutating func replaceTargets(
        of holder: NodeURI,
        in graphs: [Graph],
        along reads: RelatedReads
    ) -> Bool {
        for target in targets.removeValue(forKey: holder) ?? [] {
            dependents[target]?.remove(holder)
        }
        let edges = graphs.flatMap { graph in graph.dependencyURIs(ofTask: holder.ref, inBoard: holder.boardKey) }
        guard edges.allSatisfy({ uri in uri.boardKey == holder.boardKey || reads.knows(uri.boardKey) }) else {
            return false
        }
        let positions = edges.map { uri in uri.boardKey == holder.boardKey ? uri : reads.position(of: uri) }
        targets[holder] = positions
        for target in positions {
            dependents[target, default: []].insert(holder)
        }
        return true
    }
}

// MARK: - Graph

extension Graph {
    /// The local refs of the tasks of the graph, live or tombstoned.
    var taskRefs: [LocalRef] {
        allSlots.compactMap { slot in node(at: slot, as: TaskNode.self)?.ref }
    }

    /// Gives the board keys of the cross-board dependencies of the tasks of the graph, as the URIs hold them.
    ///
    /// - Parameter key: The current key of the board.
    /// - Returns: The keys.
    func remoteDependencyKeys(inBoard key: String) -> Set<String> {
        remoteBoardKeys { task in dependencies(of: task, inBoard: key) }
    }

    /// Gives the targets of the dependencies of a task as URIs: the `dependsOn` edges and the dependency markers, also
    /// to a tombstone and to a node that the graph does not have. A target of this board has the key of this board,
    /// and a target of a different board keeps the key that the URI holds.
    ///
    /// - Parameters:
    ///   - ref: The local ref of the task.
    ///   - key: The current key of the board.
    /// - Returns: The URIs, or no URIs when the graph has no task for the ref.
    func dependencyURIs(ofTask ref: LocalRef, inBoard key: String) -> [NodeURI] {
        guard let task = slot(for: ref).flatMap({ slot in node(at: slot, as: TaskNode.self) }) else {
            return []
        }
        return dependencies(of: task, inBoard: key).compactMap { target in uri(of: target, inBoard: key) }
    }

    /// Gives the URI of the target of one edge of a node of the graph. A target of this board has the key of this
    /// board, and a target of a different board keeps the key that its URI holds.
    ///
    /// - Parameters:
    ///   - target: The target of the edge.
    ///   - key: The current key of the board.
    /// - Returns: The URI, or `nil` for a slot that holds no node.
    func uri(of target: EdgeTarget, inBoard key: String) -> NodeURI? {
        switch target {
        case .slot(let slot): node(at: slot).map { node in NodeURI(boardKey: key, ref: node.ref) }
        case .unresolved(let stored): stored.uri(inBoard: key)
        }
    }
}
