import Foundation

/// The readiness of the tasks of one board at read time: done, `ready`, and `blockedBy` (plan.md §5.3 step 4, §6).
/// The dependencies go in one direction only: there is no reverse `blocks` list (divergence.md Q1).
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
/// - A `dependsOn` cycle from a merge (plan.md §5.3 step 5): each task in the cycle is blocked, also when the cycle
///   goes across boards (divergence.md X8). A dependency also blocks a task when a walk from the dependency over the
///   dependencies comes back to the task, also when the dependency is done. The walk follows the dependencies into
///   the loaded related boards with the same rules: it skips a tombstone, and a target that no loaded board has ends
///   its path. The walk reads only memory, and it stops at each task that it already visited, so it always ends.
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

    /// The current key of the board. A walk across boards reads a task with this key in ``graph``.
    private let boardKey: String

    /// The dependencies of each task, live or tombstoned, by the slot of the task. A dependency on a tombstoned node
    /// is not in the list.
    private let dependencies: [Int: [EdgeTarget]]

    /// The slots of the tasks, live and tombstoned, in board order: by the position of the column where the task
    /// shows, then by ordinal, then by ULID. A task with no live column to show in comes last.
    let taskOrder: [Int]

    /// The priority tier of each open task (live and not done), by the slot of the task
    /// (``PriorityTier/init(atRank:amongOpenTasks:)``). A done task and a tombstone are not in it.
    private let priorityTiers: [Int: PriorityTier]

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
        boardKey = currentBoardKey
        columnOrder = ColumnOrder(of: graph)
        let dependencies = Dictionary(
            uniqueKeysWithValues: graph.allSlots.compactMap { slot in
                graph.liveDependencies(ofTaskAt: slot, inBoard: currentBoardKey, reading: related).map { targets in
                    (slot, targets)
                }
            }
        )
        self.dependencies = dependencies
        let taskOrder = graph.boardOrder(of: columnOrder)
        self.taskOrder = taskOrder
        priorityTiers = graph.priorityTiers(of: taskOrder, by: columnOrder)
    }

    /// Gives the column where a task shows: the `column` field (``ColumnOrder/displaySlot(of:)``).
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: The slot of the column. A slot that holds no task, and a board with no live column, give `nil`.
    func column(ofTaskAt slot: Int) -> Int? {
        graph.column(ofTaskAt: slot, by: columnOrder)
    }

    /// Tells if a task is done: the task shows in the terminal column.
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: `true` when the task is done. A slot that holds no task gives `false`.
    func isDone(taskAt slot: Int) -> Bool {
        graph.isDone(taskAt: slot, by: columnOrder)
    }

    /// Gives the priority tier of a task: its third of the open tasks in board order
    /// (``PriorityTier/init(atRank:amongOpenTasks:)``).
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: The tier, or `nil` for a done task, a tombstone, or a slot that holds no task.
    func priorityTier(ofTaskAt slot: Int) -> PriorityTier? {
        priorityTiers[slot]
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

    /// Gives the dependencies of a task that no loaded board has as a task: the `unresolvedDependsOn` field
    /// (divergence.md Q2). Each one blocks the task (plan.md §3.3, rule 4), and `blockedBy` does not list it.
    ///
    /// A target is unresolved when this graph has no node for its local ref, when no loaded board has the task of a
    /// cross-board ref (the board is not found, cannot be read, or has no task for the ref), or when its node is not
    /// a task. A dependency on a tombstone is ignored, so it is not in the result.
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: The stored ref of each unresolved target, in the order of the dependencies. A slot that holds no
    ///   task gives no refs.
    func unresolvedDependencies(ofTaskAt slot: Int) -> [StoredRef] {
        dependencies(ofTaskAt: slot).compactMap(unresolvedRef(of:))
    }

    /// Tells if a task is ready: no dependency blocks it. A done task can also be ready.
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: `true` when the task is ready.
    func isReady(taskAt slot: Int) -> Bool {
        blockers(ofTaskAt: slot).isEmpty
    }
}

// MARK: - Walk

extension Readiness {
    /// Tells if one dependency blocks a task.
    ///
    /// - Parameters:
    ///   - target: The dependency.
    ///   - slot: The slot of the task that has the dependency.
    /// - Returns: `true` when the target is not done, or when a walk from the target comes back to the task, also
    ///   through related boards. A target of a related board is done when the task shows in the terminal column of
    ///   that board.
    private func isBlocking(_ target: EdgeTarget, forTaskAt slot: Int) -> Bool {
        !isDone(target) || hasDependencyPath(from: target, to: slot)
    }

    /// Tells if one dependency is done.
    ///
    /// - Parameter target: The dependency.
    /// - Returns: `true` when the task of the target shows in the terminal column of its board. A target that no
    ///   loaded board has is not done.
    private func isDone(_ target: EdgeTarget) -> Bool {
        switch target {
        case .slot(let targetSlot): isDone(taskAt: targetSlot)
        case .unresolved(let ref): related.isDone(ref)
        }
    }

    /// Gives the stored ref of a dependency that no loaded board has as a task.
    ///
    /// - Parameter target: The dependency.
    /// - Returns: The ref of the target, or `nil` when a loaded board has a task for it, live or tombstoned.
    private func unresolvedRef(of target: EdgeTarget) -> StoredRef? {
        switch target {
        case .slot(let targetSlot):
            guard graph.node(at: targetSlot, as: TaskNode.self) == nil else {
                return nil
            }
            return graph.node(at: targetSlot).map { node in .local(node.ref) }
        case .unresolved(let ref):
            return related.task(for: ref) == nil ? ref : nil
        }
    }

    /// Walks the dependencies from a dependency of a task, and tells if the walk comes back to the task.
    ///
    /// The walk follows the dependencies into the loaded related boards (divergence.md X8). It reads only memory. A
    /// dependency on a tombstone is not in the walk, a target that no loaded board has ends its path, and the walk
    /// stops at each task that it already visited, so it ends also when the dependencies have a cycle.
    ///
    /// - Parameters:
    ///   - start: The dependency where the walk starts.
    ///   - goal: The slot of the task to find, in this board.
    /// - Returns: `true` when the goal is the start, or when a chain of dependencies leads from the start to the goal.
    private func hasDependencyPath(from start: EdgeTarget, to goal: Int) -> Bool {
        let goalPosition = TaskPosition(boardKey: boardKey, slot: goal)
        var visited: Set<TaskPosition> = []
        var pending = step(to: start, from: currentBoard).map { first in [first] } ?? []
        while let current = pending.popLast() {
            if current.position == goalPosition {
                return true
            }
            if visited.insert(current.position).inserted {
                pending += nextSteps(after: current)
            }
        }
        return false
    }

    /// This board, as a walk across boards reads it.
    private var currentBoard: WalkBoard {
        WalkBoard(key: boardKey, graph: graph)
    }

    /// Gives the steps of a walk across boards from one task: one step to each dependency of the task that a loaded
    /// board has.
    ///
    /// - Parameter step: The task.
    /// - Returns: The steps, in the order of the dependencies.
    private func nextSteps(after step: WalkStep) -> [WalkStep] {
        dependencies(ofTaskAt: step.slot, in: step.board).compactMap { target in
            self.step(to: target, from: step.board)
        }
    }

    /// Gives the dependencies of a task of a board that a walk reads, without the dependencies on tombstoned nodes.
    ///
    /// - Parameters:
    ///   - slot: The slot of the task in the graph of the board.
    ///   - board: The board of the task.
    /// - Returns: The dependencies. A slot that holds no task gives no dependencies.
    private func dependencies(ofTaskAt slot: Int, in board: WalkBoard) -> [EdgeTarget] {
        guard board.key != boardKey else {
            return dependencies(ofTaskAt: slot)
        }
        return board.graph.liveDependencies(ofTaskAt: slot, inBoard: board.key, reading: related) ?? []
    }

    /// Gives the step of a walk across boards to one dependency.
    ///
    /// - Parameters:
    ///   - target: The dependency.
    ///   - board: The board of the task that has the dependency.
    /// - Returns: The step, or `nil` when no loaded board has the target.
    private func step(to target: EdgeTarget, from board: WalkBoard) -> WalkStep? {
        switch target {
        case .slot(let slot): WalkStep(board: board, slot: slot)
        case .unresolved(let ref): step(toTaskOf: ref)
        }
    }

    /// Gives the step of a walk across boards to the task of a cross-board ref. A task with the key of this board is
    /// read in ``graph``, so that the walk can come back to a task of this board.
    ///
    /// - Parameter ref: The stored ref of the task.
    /// - Returns: The step, or `nil` for a local ref, for a task that no loaded board has, and for a task of this
    ///   board that is not a live task.
    private func step(toTaskOf ref: StoredRef) -> WalkStep? {
        guard case .remote(let uri) = ref, let found = related.task(for: ref) else {
            return nil
        }
        guard found.board.key == boardKey else {
            return WalkStep(board: WalkBoard(of: found.board), slot: found.slot)
        }
        return graph.slot(for: uri.ref).flatMap { slot in
            graph.isLiveTask(at: slot) ? WalkStep(board: currentBoard, slot: slot) : nil
        }
    }
}

/// A board that a walk across boards reads: its current key and its graph. The readiness walk and
/// ``DependencyWalk`` both use it.
struct WalkBoard {
    /// The current key of the board.
    let key: String

    /// The graph of the board.
    let graph: Graph
}

extension WalkBoard {
    /// Makes the board of a walk from a loaded related board.
    ///
    /// - Parameter board: The loaded board.
    init(of board: BoardSnapshot) {
        self.init(key: board.key, graph: board.graph)
    }
}

/// One task that a walk across boards reached.
private struct WalkStep {
    /// The board of the task.
    let board: WalkBoard

    /// The slot of the task in the graph of its board.
    let slot: Int

    /// The place of the task on the walk.
    var position: TaskPosition {
        TaskPosition(boardKey: board.key, slot: slot)
    }
}

/// The place of a task on a walk across boards: the current key of its board and its slot in that board.
private struct TaskPosition: Hashable {
    /// The current key of the board of the task.
    /// Read by the synthesized `Hashable` conformance; periphery sees no caller.
    // periphery:ignore
    let boardKey: String

    /// The slot of the task in the graph of its board.
    /// Read by the synthesized `Hashable` conformance; periphery sees no caller.
    // periphery:ignore
    let slot: Int
}

// MARK: - Graph

extension Graph {
    /// Tells if a slot holds a live task.
    ///
    /// - Parameter slot: A slot that this graph gave.
    /// - Returns: `true` when the slot holds a task that is not a tombstone.
    func isLiveTask(at slot: Int) -> Bool {
        isLive(TaskNode.self, at: slot)
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

    /// Gives the column where a task shows (``ColumnOrder/displaySlot(of:)``).
    ///
    /// - Parameters:
    ///   - slot: The slot of the task.
    ///   - columnOrder: The live columns of the board in board order.
    /// - Returns: The slot of the column. A slot that holds no task, and a board with no live column, give `nil`.
    fileprivate func column(ofTaskAt slot: Int, by columnOrder: ColumnOrder) -> Int? {
        node(at: slot, as: TaskNode.self).flatMap { task in
            columnOrder.displaySlot(of: task.column)
        }
    }

    /// Tells if a task is done: the task shows in the terminal column.
    ///
    /// - Parameters:
    ///   - slot: The slot of the task.
    ///   - columnOrder: The live columns of the board in board order.
    /// - Returns: `true` when the task is done. A slot that holds no task gives `false`.
    fileprivate func isDone(taskAt slot: Int, by columnOrder: ColumnOrder) -> Bool {
        node(at: slot, as: TaskNode.self).map { task in columnOrder.isTerminal(task.column) } ?? false
    }

    /// Sorts the tasks of the graph, live and tombstoned, in board order: by the position of the column where the
    /// task shows, then by ordinal, then by ULID. A task with no live column to show in comes last.
    ///
    /// - Parameter columnOrder: The live columns of the board in board order.
    /// - Returns: The slots of the tasks, in board order.
    fileprivate func boardOrder(of columnOrder: ColumnOrder) -> [Int] {
        let columnSlots = columnOrder.slots
        let positions = Dictionary(uniqueKeysWithValues: zip(columnSlots, columnSlots.indices))
        let tasks = allSlots.compactMap { slot -> (slot: Int, position: Int, task: TaskNode)? in
            guard let task = node(at: slot, as: TaskNode.self) else {
                return nil
            }
            let position = column(ofTaskAt: slot, by: columnOrder).flatMap { column in positions[column] }
            return (slot, position ?? positions.count, task)
        }
        return tasks.sorted { lhs, rhs in
            (lhs.position, lhs.task.ordinal, lhs.task.id) < (rhs.position, rhs.task.ordinal, rhs.task.id)
        }
        .map(\.slot)
    }

    /// Gives the priority tier of each open task: each live task that is not done, by its rank in board order
    /// (``PriorityTier/init(atRank:amongOpenTasks:)``).
    ///
    /// - Parameters:
    ///   - taskOrder: The slots of the tasks in board order.
    ///   - columnOrder: The live columns of the board in board order.
    /// - Returns: The tier of each open task, by the slot of the task.
    fileprivate func priorityTiers(of taskOrder: [Int], by columnOrder: ColumnOrder) -> [Int: PriorityTier] {
        let openTasks = taskOrder.filter { slot in
            isLiveTask(at: slot) && !isDone(taskAt: slot, by: columnOrder)
        }
        return Dictionary(
            uniqueKeysWithValues: openTasks.enumerated().map { rank, slot in
                (slot, PriorityTier(atRank: rank, amongOpenTasks: openTasks.count))
            }
        )
    }
}
