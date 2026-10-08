import Foundation

/// The priority of an open task: its third of the open tasks of the board, in board order (plan.md §6, "Virtual
/// tags"). An open task is a live task that is not done. A done task and a tombstone have no tier.
///
/// The cases are in tier order: the first third of the open tasks is ``high``, the second third ``medium``, and the
/// rest ``low``.
enum PriorityTier: CaseIterable, Sendable {
    /// The task is in the first third of the open tasks.
    case high

    /// The task is in the second third of the open tasks.
    case medium

    /// The task is after the second third of the open tasks.
    case low

    /// Gives the tier of an open task from its place among the open tasks in board order.
    ///
    /// The rule: the task at rank `r` (from 0) of `n` open tasks gets the tier `r * 3 / n`, with integer division,
    /// where 3 is the number of tiers. Thus the first tier holds `ceil(n / 3)` tasks, and a board with 1 or 2 open
    /// tasks starts with `HIGH`: 1 open task is `HIGH`; 2 are `HIGH` and `MEDIUM`; 3 are `HIGH`, `MEDIUM`, and `LOW`;
    /// 7 are 3 `HIGH`, 2 `MEDIUM`, and 2 `LOW`.
    ///
    /// - Parameters:
    ///   - rank: The place of the task among the open tasks in board order, from 0. It is less than `count`.
    ///   - count: The number of open tasks of the board.
    init(atRank rank: Int, amongOpenTasks count: Int) {
        self = Self.allCases[rank * Self.allCases.count / count]
    }

    /// The virtual tag of the tier: `HIGH`, `MEDIUM`, or `LOW`.
    var virtualTag: VirtualTag {
        switch self {
        case .high: .high
        case .medium: .medium
        case .low: .low
        }
    }
}
