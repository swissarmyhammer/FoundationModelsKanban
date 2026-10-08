import Foundation

/// The test of a task against the filter of a task list or of the change feed (plan.md §3.3 rule 3, §6.3, §6.7).
///
/// The test has two parts:
///
/// - The hidden states. Each tag of ``VirtualTag/hiddenUnlessNamed`` marks a task state that the test leaves out by
///   default: `DELETED` and `DONE`. A task with one of these tags passes only when the filter names the tag
///   (``FilterExpr/names(_:)``; a column atom names `DONE`). Thus a task list shows no tombstone and no done task,
///   but `#DELETED` lists the tombstones, `#DONE || #bug` lists the done tasks and the open tasks with the tag `bug`,
///   and `%done` lists the done tasks.
/// - The filter (``FilterEvaluator``). With no filter, each task that is not hidden passes.
///
/// `Board.tasks`, `Board.nextTask`, `Board.searchTasks`, the `tasks` fields of `Column`, `Actor`, and `Tag`, and the
/// task filter of `Board.history` and `Subscription.changes` all use this one test.
struct TaskFilter {
    /// The evaluator of the filter, or `nil` for no filter.
    private let evaluator: FilterEvaluator?

    /// The virtual tags of the hidden states that the filter does not name.
    private let hiddenTags: [VirtualTag]

    /// The readiness of the tasks of the board.
    private let readiness: Readiness

    /// Makes the test of a filter for one board.
    ///
    /// - Parameters:
    ///   - filter: The parsed filter, or `nil` for no filter.
    ///   - readiness: The readiness of the tasks of the board. It holds the graph and the column order.
    ///   - boardKey: The current key of the board. A URL with this key names a node of the board.
    init(filtering filter: FilterExpr?, over readiness: Readiness, inBoard boardKey: String) {
        evaluator = filter.map { expression in
            FilterEvaluator(evaluating: expression, over: readiness, inBoard: boardKey)
        }
        hiddenTags = VirtualTag.hiddenUnlessNamed.filter { tag in !(filter?.names(tag) ?? false) }
        self.readiness = readiness
    }

    /// Tells if a task passes the test.
    ///
    /// - Parameter slot: The slot of the task, live or tombstoned.
    /// - Returns: `true` when the task has no hidden state that the filter does not name, and matches the filter.
    func matches(taskAt slot: Int) -> Bool {
        !hiddenTags.contains { tag in readiness.hasVirtualTag(tag, taskAt: slot) }
            && (evaluator?.matches(taskAt: slot) ?? true)
    }
}
