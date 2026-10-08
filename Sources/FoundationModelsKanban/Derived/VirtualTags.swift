import Foundation

/// A virtual tag: a tag that the projection calculates for a task at read time, from the board state (plan.md §5.5,
/// §6). No patch writes it. The filter `#READY` and the other `#` atoms match it.
///
/// The cases are in the order of the Rust virtual tag registry. The new tags `CONFLICT`, `DELETED`, and `DONE`, and
/// then the priority tags `HIGH`, `MEDIUM`, and `LOW`, come last. The raw value is the slug of the tag, and the match
/// is case-sensitive.
enum VirtualTag: String, CaseIterable, Sendable {
    /// The task is live, it is not done, and all its dependencies are done.
    case ready = "READY"

    /// The task is live, and at least one dependency of the task is not done.
    case blocked = "BLOCKED"

    /// The task is live, it is not done, and a live task depends on it.
    case blocking = "BLOCKING"

    /// The body of the task has a conflict block from a diff that could not apply.
    case conflict = "CONFLICT"

    /// The task is a tombstone: it has a `deleted` time (plan.md §3.3, rule 3).
    case deleted = "DELETED"

    /// The task is live, and it shows in the terminal column.
    case done = "DONE"

    /// The task is open, and it is in the first third of the open tasks in board order.
    case high = "HIGH"

    /// The task is open, and it is in the second third of the open tasks in board order.
    case medium = "MEDIUM"

    /// The task is open, and it is after the second third of the open tasks in board order.
    case low = "LOW"
}

extension VirtualTag {
    /// The virtual tags of the task states that a task list leaves out by default (plan.md §3.3 rule 3, §6.3): the
    /// tombstones and the done tasks.
    ///
    /// A task with one of these tags is in a list only when the filter names the tag (``FilterExpr/names(_:)``).
    /// Then the filter decides. Thus `#DELETED` lists only the deleted tasks, `#DONE` lists only the done tasks, and
    /// `!#DONE` lists the live tasks that are not done. A column atom also names `DONE`, so `%done` lists the done
    /// tasks.
    static let hiddenUnlessNamed: [VirtualTag] = [.deleted, .done]

    /// Finds the virtual tag that a tag name names.
    ///
    /// - Parameter name: The name as a filter writes it, in any case, for example `ready`.
    init?(named name: String) {
        let isNamed: (Self) -> Bool = { tag in tag.rawValue.caseInsensitiveCompare(name) == .orderedSame }
        guard let tag = Self.allCases.first(where: isNamed) else {
            return nil
        }
        self = tag
    }
}

extension Readiness {
    /// Gives the virtual tags of a task: the `virtualTags` field.
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: The virtual tags that apply to the task, in the order of ``VirtualTag/allCases``. A slot that holds
    ///   no task gives no tags, because the other node types do not have virtual tags.
    func virtualTags(ofTaskAt slot: Int) -> [VirtualTag] {
        VirtualTag.allCases.filter { tag in
            hasVirtualTag(tag, taskAt: slot)
        }
    }

    /// Tells if one virtual tag applies to a task. A tombstone has the tag `DELETED`, and it can have `CONFLICT`. It
    /// never has `READY`, `BLOCKED`, `BLOCKING`, or `DONE`. A done task never has `READY` or `BLOCKING`. As in Rust,
    /// it has `BLOCKED` when one of its dependencies is not done. Each open task has one priority tag, `HIGH`,
    /// `MEDIUM`, or `LOW` (``priorityTier(ofTaskAt:)``). A done task and a tombstone have no priority tag.
    ///
    /// - Parameters:
    ///   - tag: The virtual tag.
    ///   - slot: The slot of the task.
    /// - Returns: `true` when the tag applies. A slot that holds no task gives `false`.
    func hasVirtualTag(_ tag: VirtualTag, taskAt slot: Int) -> Bool {
        guard let task = graph.node(at: slot, as: TaskNode.self) else {
            return false
        }
        let isLive = !task.fields.isDeleted
        switch tag {
        case .ready:
            return isLive && !isDone(taskAt: slot) && isReady(taskAt: slot)
        case .blocked:
            return isLive && !isReady(taskAt: slot)
        case .blocking:
            return isLive && !isDone(taskAt: slot) && !dependents(ofTaskAt: slot).isEmpty
        case .conflict:
            return task.fields.hasConflict
        case .deleted:
            return task.fields.isDeleted
        case .done:
            return isLive && isDone(taskAt: slot)
        case .high, .medium, .low:
            return priorityTier(ofTaskAt: slot)?.virtualTag == tag
        }
    }
}
