import Foundation

/// The counts of the live tasks and of the live actors of a board: the `Board.summary` field (plan.md §4.1, §6).
///
/// The counts are the counts of the Rust `get board` summary. A tombstoned task and a tombstoned actor are not
/// counted. A done task with no blocking dependency is also ready, so `ready` and `done` can both count one task.
struct BoardSummary: Hashable, Sendable {
    /// The number of live tasks.
    let total: Int

    /// The number of live tasks that no dependency blocks.
    let ready: Int

    /// The number of live tasks in the terminal column.
    let done: Int

    /// The number of live actors (divergence.md Q19). Rust calls it `total_actors`. The memberwise initializer gives
    /// 0 when the caller does not give it.
    var totalActors: Int = .zero

    /// The number of live tasks that a dependency blocks: the tasks that are not ready.
    var blocked: Int {
        total - ready
    }

    /// The part of the live tasks that is done, in percent, rounded to the nearest whole number. A board with no live
    /// task gives 0.
    var percent: Int {
        guard total > .zero else {
            return .zero
        }
        return Int((Double(done) / Double(total) * .percentScale).rounded())
    }
}

extension Readiness {
    /// The counts of the live tasks and of the live actors of the board: the `summary` field.
    var summary: BoardSummary {
        let tasks = graph.allSlots.filter(graph.isLiveTask(at:))
        return BoardSummary(
            total: tasks.count,
            ready: tasks.filter(isReady(taskAt:)).count,
            done: tasks.filter(isDone(taskAt:)).count,
            totalActors: graph.allSlots.filter(graph.isLiveActor(at:)).count
        )
    }

    /// Counts the live tasks that show in a column: the `Column.taskCount` field (divergence.md Q19). A task whose
    /// column is not a live column shows in the first column (``ColumnOrder/displaySlot(of:)``), so it counts there.
    ///
    /// - Parameter column: The slot of the column.
    /// - Returns: The number of live tasks in the column.
    func taskCount(inColumnAt column: Int) -> Int {
        liveTasks(inColumnAt: column).count
    }

    /// Counts the live tasks that show in a column and that no dependency blocks: the `Column.readyCount` field
    /// (divergence.md Q19). As in Rust, a done task with no blocking dependency counts.
    ///
    /// - Parameter column: The slot of the column.
    /// - Returns: The number of ready live tasks in the column.
    func readyCount(inColumnAt column: Int) -> Int {
        liveTasks(inColumnAt: column).filter(isReady(taskAt:)).count
    }

    /// Gives the live tasks that show in a column.
    ///
    /// - Parameter column: The slot of the column.
    /// - Returns: The slots of the tasks, in slot order.
    private func liveTasks(inColumnAt column: Int) -> [Int] {
        graph.allSlots.filter { slot in
            graph.isLiveTask(at: slot) && self.column(ofTaskAt: slot) == column
        }
    }
}

extension Graph {
    /// Tells if a slot holds a live actor.
    ///
    /// - Parameter slot: A slot that this graph gave.
    /// - Returns: `true` when the slot holds an actor that is not a tombstone.
    func isLiveActor(at slot: Int) -> Bool {
        node(at: slot, as: ActorNode.self)?.fields.isDeleted == false
    }
}
