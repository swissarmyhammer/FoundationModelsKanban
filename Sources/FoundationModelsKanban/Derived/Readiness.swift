import Foundation

/// The readiness of the tasks of one board at read time: done, `ready`, `blockedBy`, and `blocks` (plan.md §5.3
/// step 4, §6).
///
/// - A task is **done** when it shows in the terminal column (``ColumnOrder``). A task with no column, or with a
///   column that is tombstoned or missing, shows in the first column. Thus, it is done only when the first column is
///   also the terminal column: on a board with one column.
/// - The dependencies of a task are its `dependsOn` edges and its dependency markers
///   (``Graph/dependencies(of:inBoard:)``). A dependency on a tombstoned task is ignored (plan.md §3.3, rule 3), also
///   when the task is in a related board.
/// - A dependency **blocks** a task when it is not done. A dependency on a task of a related board reads that board
///   in ``RelatedBoards`` (plan.md §6.6). A target that no loaded board has, for example a task of a board that the
///   scan cannot find, is not done (plan.md §3.3, rule 4).
/// - A `dependsOn` cycle from a merge (plan.md §5.3 step 5): each task in the cycle is blocked. A dependency also
///   blocks a task when a walk from the dependency over the `dependsOn` edges comes back to the task, also when the
///   dependency is done. The walk stops at each task that it already visited, so it always ends.
/// - A task is **ready** when no dependency blocks it.
///
/// The value calculates the dependencies of all tasks one time, so that one read can ask about many tasks.
struct Readiness {
    /// The graph of the board.
    let graph: Graph

    /// The live columns of the board in board order.
    let columnOrder: ColumnOrder

    /// The related boards that the cross-board dependencies read.
    let related: RelatedBoards

    /// The dependencies of each task, live or tombstoned, by the slot of the task. A dependency on a tombstoned node
    /// is not in the list.
    private let dependencies: [Int: [EdgeTarget]]

    /// The live tasks that depend on each task, by the slot of the target task, in slot order.
    private let dependents: [Int: [Int]]

    /// Calculates the readiness of the tasks of a graph.
    ///
    /// - Parameters:
    ///   - graph: The graph of the board.
    ///   - currentBoardKey: The current key of the board. A dependency marker with this key resolves in the board.
    ///   - related: The related boards that the cross-board dependencies read. The default reads no related board,
    ///     so each cross-board dependency is not done.
    init(of graph: Graph, inBoard currentBoardKey: String, reading related: RelatedBoards = .unavailable) {
        self.graph = graph
        self.related = related
        columnOrder = ColumnOrder(of: graph)
        let dependencies = Dictionary(
            uniqueKeysWithValues: graph.allSlots.compactMap { slot in
                graph.liveDependencies(ofTaskAt: slot, inBoard: currentBoardKey, reading: related).map { targets in
                    (slot, targets)
                }
            }
        )
        self.dependencies = dependencies
        dependents = graph.dependents(from: dependencies)
    }

    /// Gives the column where a task shows: the `column` field (``ColumnOrder/displaySlot(of:)``).
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: The slot of the column. A slot that holds no task, and a board with no live column, give `nil`.
    func column(ofTaskAt slot: Int) -> Int? {
        graph.node(at: slot, as: TaskNode.self).flatMap { task in
            columnOrder.displaySlot(of: task.column)
        }
    }

    /// Tells if a task is done: the task shows in the terminal column.
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: `true` when the task is done. A slot that holds no task gives `false`.
    func isDone(taskAt slot: Int) -> Bool {
        graph.node(at: slot, as: TaskNode.self).map { task in columnOrder.isTerminal(task.column) } ?? false
    }

    /// Gives the dependencies of a task: its `dependsOn` edges and its dependency markers, without the dependencies
    /// on tombstoned nodes.
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: The targets, edges first and then markers. A target that the graph does not have stays an
    ///   unresolved edge. A slot that holds no task gives no targets.
    func dependencies(ofTaskAt slot: Int) -> [EdgeTarget] {
        dependencies[slot, default: []]
    }

    /// Gives the dependencies that block a task: the `blockedBy` field.
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: The blocking targets, in the order of the dependencies. A target that the graph does not have
    ///   stays an unresolved edge.
    func blockers(ofTaskAt slot: Int) -> [EdgeTarget] {
        dependencies(ofTaskAt: slot).filter { target in
            isBlocking(target, forTaskAt: slot)
        }
    }

    /// Tells if a task is ready: no dependency blocks it. A done task can also be ready.
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: `true` when the task is ready.
    func isReady(taskAt slot: Int) -> Bool {
        blockers(ofTaskAt: slot).isEmpty
    }

    /// Gives the live tasks that depend on a task: the `blocks` field.
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: The slots of the dependent tasks, in slot order.
    func dependents(ofTaskAt slot: Int) -> [Int] {
        dependents[slot, default: []]
    }
}

// MARK: - Walk

extension Readiness {
    /// Tells if one dependency blocks a task.
    ///
    /// - Parameters:
    ///   - target: The dependency.
    ///   - slot: The slot of the task that has the dependency.
    /// - Returns: `true` when the target is not done, or when a walk from the target comes back to the task. A
    ///   target of a related board is done when the task shows in the terminal column of that board.
    private func isBlocking(_ target: EdgeTarget, forTaskAt slot: Int) -> Bool {
        switch target {
        case .slot(let targetSlot):
            !isDone(taskAt: targetSlot) || hasDependencyPath(from: targetSlot, to: slot)
        case .unresolved(let ref):
            !related.isDone(ref)
        }
    }

    /// Walks the `dependsOn` edges from a task, and tells if the walk reaches a second task.
    ///
    /// The walk stops at each task that it already visited, so it ends also when the edges have a cycle.
    ///
    /// - Parameters:
    ///   - start: The slot of the task where the walk starts.
    ///   - goal: The slot of the task to find.
    /// - Returns: `true` when the goal is the start, or when a chain of dependencies leads from the start to the goal.
    private func hasDependencyPath(from start: Int, to goal: Int) -> Bool {
        var visited: Set<Int> = []
        var pending = [start]
        while let current = pending.popLast() {
            if current == goal {
                return true
            }
            if visited.insert(current).inserted {
                pending += dependencySlots(ofTaskAt: current)
            }
        }
        return false
    }

    /// Gives the slots of the dependencies of a task that the graph has.
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: The slots. An unresolved dependency has no slot, so it is not in the result.
    private func dependencySlots(ofTaskAt slot: Int) -> [Int] {
        dependencies(ofTaskAt: slot).compactMap(\.resolvedSlot)
    }
}

// MARK: - Graph

extension Graph {
    /// Tells if a slot holds a live task.
    ///
    /// - Parameter slot: A slot that this graph gave.
    /// - Returns: `true` when the slot holds a task that is not a tombstone.
    func isLiveTask(at slot: Int) -> Bool {
        node(at: slot, as: TaskNode.self)?.fields.isDeleted == false
    }

    /// Gives the dependencies of a task, without the dependencies on tombstoned nodes (plan.md §3.3, rule 3).
    ///
    /// - Parameters:
    ///   - slot: The slot of the task.
    ///   - currentBoardKey: The current key of the board.
    ///   - related: The related boards. A dependency on a tombstoned task of a related board is not in the result.
    /// - Returns: The dependencies, or `nil` when the slot holds no task.
    fileprivate func liveDependencies(
        ofTaskAt slot: Int,
        inBoard currentBoardKey: String,
        reading related: RelatedBoards
    ) -> [EdgeTarget]? {
        node(at: slot, as: TaskNode.self).map { task in
            dependencies(of: task, inBoard: currentBoardKey).filter { target in
                switch target {
                case .slot(let targetSlot): node(at: targetSlot)?.state.fields.isDeleted != true
                case .unresolved(let ref): !related.isTombstone(ref)
                }
            }
        }
    }

    /// Gives the live tasks that depend on each task.
    ///
    /// - Parameter dependencies: The dependencies of each task, by the slot of the task.
    /// - Returns: The slots of the live dependent tasks, in slot order, by the slot of the target task.
    fileprivate func dependents(from dependencies: [Int: [EdgeTarget]]) -> [Int: [Int]] {
        let links = dependencies.keys.sorted().flatMap { holder -> [(target: Int, holder: Int)] in
            guard isLiveTask(at: holder) else {
                return []
            }
            return dependencies[holder, default: []].compactMap(\.resolvedSlot).map { target in (target, holder) }
        }
        return Dictionary(grouping: links, by: \.target).mapValues { group in group.map(\.holder) }
    }
}
