import Foundation

/// The readiness of the tasks of one board at read time: done, `ready`, `blockedBy`, and `blocks` (plan.md §5.3
/// step 4, §6).
///
/// - A task is **done** when it is in the terminal column (``Graph/terminalColumnSlot``).
/// - The dependencies of a task are its `dependsOn` edges and its dependency markers
///   (``Graph/dependencies(of:inBoard:)``). A dependency on a tombstoned task is ignored (plan.md §3.3, rule 3).
/// - A dependency **blocks** a task when it is not done. A target that the graph does not have, for example a task
///   of a board that is not loaded, is not done (plan.md §3.3, rule 4).
/// - A `dependsOn` cycle from a merge (plan.md §5.3 step 5): each task in the cycle is blocked. A dependency also
///   blocks a task when a walk from the dependency over the `dependsOn` edges comes back to the task, also when the
///   dependency is done. The walk stops at each task that it already visited, so it always ends.
/// - A task is **ready** when no dependency blocks it.
///
/// The value calculates the dependencies of all tasks one time, so that one read can ask about many tasks.
struct Readiness {
    /// The graph of the board.
    let graph: Graph

    /// The slot of the terminal column, or `nil` when the board has no live column.
    private let terminalColumnSlot: Int?

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
    init(of graph: Graph, inBoard currentBoardKey: String) {
        self.graph = graph
        terminalColumnSlot = graph.terminalColumnSlot
        let dependencies = Dictionary(
            uniqueKeysWithValues: graph.allSlots.compactMap { slot in
                graph.liveDependencies(ofTaskAt: slot, inBoard: currentBoardKey).map { targets in (slot, targets) }
            }
        )
        self.dependencies = dependencies
        dependents = graph.dependents(from: dependencies)
    }

    /// Tells if a task is done: the task is in the terminal column.
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: `true` when the task is done. A slot that holds no task gives `false`.
    func isDone(taskAt slot: Int) -> Bool {
        guard let terminalColumnSlot, let task = graph.task(at: slot) else {
            return false
        }
        return task.column == .slot(terminalColumnSlot)
    }

    /// Gives the dependencies that block a task: the `blockedBy` field.
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: The blocking targets, in the order of the dependencies. A target that the graph does not have
    ///   stays an unresolved edge.
    func blockers(ofTaskAt slot: Int) -> [EdgeTarget] {
        dependencies[slot, default: []].filter { target in
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
    /// - Returns: `true` when the target is not done, or when a walk from the target comes back to the task.
    private func isBlocking(_ target: EdgeTarget, forTaskAt slot: Int) -> Bool {
        guard let targetSlot = target.resolvedSlot else {
            return true
        }
        return !isDone(taskAt: targetSlot) || hasDependencyPath(from: targetSlot, to: slot)
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
        dependencies[slot, default: []].compactMap(\.resolvedSlot)
    }
}

// MARK: - Graph

extension Graph {
    /// The slot of the terminal column: the live column with the maximum `order` (plan.md §6). A task in this column
    /// is done.
    ///
    /// Two columns with the same `order` sort by slug (plan.md §5.3 step 5). Thus, of the columns with the maximum
    /// order, the column with the last slug is the terminal column. A tombstoned column is never the terminal column.
    /// The value is `nil` when the graph has no live column.
    var terminalColumnSlot: Int? {
        let columns = allSlots.compactMap { slot -> (slot: Int, column: ColumnNode)? in
            guard case .column(let column) = node(at: slot), !column.fields.isDeleted else {
                return nil
            }
            return (slot, column)
        }
        let terminal = columns.max { lhs, rhs in
            (lhs.column.order, lhs.column.slug) < (rhs.column.order, rhs.column.slug)
        }
        return terminal?.slot
    }

    /// Gives the task in a slot, live or tombstoned.
    ///
    /// - Parameter slot: A slot that this graph gave.
    /// - Returns: The task, or `nil` when the slot holds no node or a node that is not a task.
    fileprivate func task(at slot: Int) -> TaskNode? {
        guard case .task(let task) = node(at: slot) else {
            return nil
        }
        return task
    }

    /// Gives the dependencies of a task, without the dependencies on tombstoned nodes (plan.md §3.3, rule 3).
    ///
    /// - Parameters:
    ///   - slot: The slot of the task.
    ///   - currentBoardKey: The current key of the board.
    /// - Returns: The dependencies, or `nil` when the slot holds no task.
    fileprivate func liveDependencies(ofTaskAt slot: Int, inBoard currentBoardKey: String) -> [EdgeTarget]? {
        task(at: slot).map { task in
            dependencies(of: task, inBoard: currentBoardKey).filter { target in
                target.resolvedSlot.flatMap(node(at:))?.state.fields.isDeleted != true
            }
        }
    }

    /// Gives the live tasks that depend on each task.
    ///
    /// - Parameter dependencies: The dependencies of each task, by the slot of the task.
    /// - Returns: The slots of the live dependent tasks, in slot order, by the slot of the target task.
    fileprivate func dependents(from dependencies: [Int: [EdgeTarget]]) -> [Int: [Int]] {
        let links = dependencies.keys.sorted().flatMap { holder -> [(target: Int, holder: Int)] in
            guard task(at: holder)?.fields.isDeleted == false else {
                return []
            }
            return dependencies[holder, default: []].compactMap(\.resolvedSlot).map { target in (target, holder) }
        }
        return Dictionary(grouping: links, by: \.target).mapValues { group in group.map(\.holder) }
    }
}
