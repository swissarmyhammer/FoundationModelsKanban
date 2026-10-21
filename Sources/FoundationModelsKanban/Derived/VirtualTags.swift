import Foundation

/// A virtual tag: a tag that the projection calculates for a task at read time, from the board state (plan.md §5.5,
/// §6). No patch writes it. The filter `#READY` and the other `#` atoms match it.
///
/// The cases are in the order of the Rust virtual tag registry. The new tags `CONFLICT`, `DELETED`, and `DONE`, and
/// then the priority tags `HIGH`, `MEDIUM`, and `LOW`, come last. The Rust tag `BLOCKING` is not a virtual tag here
/// (divergence.md Q1), so `#BLOCKING` is an ordinary tag atom. The raw value is the slug of the tag, and the match
/// ignores case (``init(named:)``).
enum VirtualTag: String, CaseIterable, Sendable {
    /// The task is live, it is not done, and no dependency blocks it (``BlockerWalk``): each dependency that is not a
    /// tombstone is done, and no chain of dependencies from it comes back to the task.
    case ready = "READY"

    /// The task is live, done or not, and a dependency blocks it (``BlockerWalk``): a dependency that is not a
    /// tombstone is not done, or a chain of dependencies from it comes back to the task. A dependency that no loaded
    /// board has is not done.
    case blocked = "BLOCKED"

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
    /// tombstones.
    ///
    /// A task with one of these tags is in a list only when the filter names the tag (``FilterExpr/names(_:)``).
    /// Then the filter decides. Thus `#DELETED` lists only the deleted tasks, and `!#DELETED` lists the live tasks.
    /// `DONE` is not in the set: a list with no filter gives each live task, done or not, and the filter selects
    /// exactly what it says, so `#DONE` lists the done tasks and `!#DONE` the open tasks.
    static let hiddenUnlessNamed: [VirtualTag] = [.deleted]

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

    /// The display color of the tag: 6 hex digits with no `#`, the same form as the color of a tag
    /// (divergence.md Q19). `READY` and `BLOCKED` have the colors of the Rust virtual tags. Each other tag has a color
    /// of the GitHub label palette that no other virtual tag has.
    var color: String {
        switch self {
        case .ready: "0e8a16"
        case .blocked: "e36209"
        case .conflict: "b60205"
        case .deleted: "6a737d"
        case .done: "5319e7"
        case .high: "d93f0b"
        case .medium: "fbca04"
        case .low: "c5def5"
        }
    }

    /// The meaning of the tag in one short sentence: the `description` field of the GraphQL `VirtualTag` type
    /// (divergence.md Q19). The Swift name is not `description`, so that the tag does not seem to be
    /// `CustomStringConvertible`.
    var explanation: String {
        switch self {
        case .ready: "The task is live and not done, and no dependency blocks it."
        case .blocked: "The task is live, and a dependency that is not deleted is not done or leads back to the task."
        case .conflict: "The body of the task has a conflict block from a diff that did not apply."
        case .deleted: "The task is deleted."
        case .done: "The task is live, and it is in the terminal column."
        case .high: "The task is in the first third of the open tasks, in board order."
        case .medium: "The task is in the second third of the open tasks, in board order."
        case .low: "The task is in the last third of the open tasks, in board order."
        }
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
    /// never has `READY`, `BLOCKED`, or `DONE`. A done task never has `READY`. As in Rust,
    /// it has `BLOCKED` when a dependency blocks it (``BlockerWalk``). Each open task has one priority tag, `HIGH`,
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
