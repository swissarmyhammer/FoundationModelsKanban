import Foundation

/// A virtual tag: a tag that the projection calculates for a task at read time, from the board state (plan.md §5.5,
/// §6). No patch writes it. The filter `#READY` and the other `#` atoms match it.
///
/// The cases are in the order of the Rust virtual tag registry, and `CONFLICT` comes last. The raw value is the slug
/// of the tag, and the match is case-sensitive.
enum VirtualTag: String, CaseIterable, Sendable {
    /// The task is not done, and all its dependencies are done.
    case ready = "READY"

    /// At least one dependency of the task is not done.
    case blocked = "BLOCKED"

    /// The task is not done, and a live task depends on it.
    case blocking = "BLOCKING"

    /// The body of the task has a conflict block from a diff that could not apply.
    case conflict = "CONFLICT"
}

extension Readiness {
    /// Gives the virtual tags of a task: the `virtualTags` field.
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: The virtual tags that apply to the task, in the order of ``VirtualTag/allCases``. A slot that holds
    ///   no task gives no tags, because the other node types do not have virtual tags.
    func virtualTags(ofTaskAt slot: Int) -> [VirtualTag] {
        guard graph.node(at: slot, as: TaskNode.self) != nil else {
            return []
        }
        return VirtualTag.allCases.filter { tag in
            applies(tag, toTaskAt: slot)
        }
    }

    /// Tells if one virtual tag applies to a task.
    ///
    /// - Parameters:
    ///   - tag: The virtual tag.
    ///   - slot: The slot of the task.
    /// - Returns: `true` when the tag applies.
    private func applies(_ tag: VirtualTag, toTaskAt slot: Int) -> Bool {
        switch tag {
        case .ready:
            !isDone(taskAt: slot) && isReady(taskAt: slot)
        case .blocked:
            !isReady(taskAt: slot)
        case .blocking:
            !isDone(taskAt: slot) && !dependents(ofTaskAt: slot).isEmpty
        case .conflict:
            graph.node(at: slot)?.state.fields.hasConflict == true
        }
    }
}
