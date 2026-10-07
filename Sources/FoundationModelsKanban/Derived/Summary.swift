import Foundation

/// The counts of the live tasks of a board: the `Board.summary` field (plan.md §4.1, §6).
///
/// The counts are the counts of the Rust `get board` summary. A tombstoned task is not counted. A done task with no
/// blocking dependency is also ready, so `ready` and `done` can both count one task.
struct BoardSummary: Hashable, Sendable {
    /// The number of percent units in a whole.
    private static let percentScale = 100.0

    /// The number of live tasks.
    let total: Int

    /// The number of live tasks that no dependency blocks.
    let ready: Int

    /// The number of live tasks in the terminal column.
    let done: Int

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
        return Int((Double(done) / Double(total) * Self.percentScale).rounded())
    }
}

extension Readiness {
    /// The counts of the live tasks of the board: the `summary` field.
    var summary: BoardSummary {
        let tasks = graph.allSlots.filter(graph.isLiveTask(at:))
        return BoardSummary(
            total: tasks.count,
            ready: tasks.filter(isReady(taskAt:)).count,
            done: tasks.filter(isDone(taskAt:)).count
        )
    }
}
