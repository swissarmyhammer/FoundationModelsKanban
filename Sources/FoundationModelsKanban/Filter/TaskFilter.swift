import Foundation

/// The test of a task against the filter of a task list, or of the node of an update against the filter of the change
/// feed (plan.md §3.3 rule 3, §6.3, §6.7).
///
/// The test has two parts:
///
/// - The hidden states. Each tag of ``VirtualTag/hiddenUnlessNamed`` marks a task state that the test leaves out by
///   default: `DELETED` and `DONE`. A task with one of these tags passes only when the filter names the tag
///   (``FilterExpr/names(_:)``; a column atom names `DONE`, and a `^` or `~task` atom names both). Thus a task list
///   shows no tombstone and no done task, but `#DELETED` lists the tombstones, `#DONE || #bug` lists the done tasks
///   and the open tasks with the tag `bug`, and `%done` lists the done tasks.
/// - The filter (``FilterEvaluator``). With no filter, each node that is not hidden passes.
///
/// `Board.tasks`, `Board.nextTask`, `Board.searchTasks`, the `tasks` fields of `Column`, `Actor`, and `Tag`, and the
/// filter of `Board.history`, `Subscription.changes`, and `Change.updates` all use this one test.
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

    /// Tells if a task passes the test: the test of a task list.
    ///
    /// - Parameter slot: The slot of the task, live or tombstoned.
    /// - Returns: `true` when the slot holds a task, the task has no hidden state that the filter does not name, and
    ///   the task matches the filter.
    func matches(taskAt slot: Int) -> Bool {
        readiness.graph.node(at: slot, as: TaskNode.self) != nil && matches(nodeAt: slot)
    }

    /// Tells if a node of any type passes the test: the test of an update of the change feed.
    ///
    /// - Parameter slot: The slot of the node, live or tombstoned.
    /// - Returns: `true` when the node has no hidden state that the filter does not name, and matches the filter.
    ///   Only a task can have a hidden state.
    func matches(nodeAt slot: Int) -> Bool {
        !hiddenTags.contains { tag in readiness.hasVirtualTag(tag, taskAt: slot) }
            && (evaluator?.matches(nodeAt: slot) ?? true)
    }
}
