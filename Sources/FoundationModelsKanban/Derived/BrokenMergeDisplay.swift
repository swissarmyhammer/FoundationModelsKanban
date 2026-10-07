import Foundation

/// The display rules for comments and actors in a merged state that breaks a graph rule (plan.md §3.3 rule 7, §5.3
/// step 5). The rules for columns are in ``ColumnOrder``.
///
/// - A comment on a tombstoned task is hidden.
/// - A comment author or a `Change` actor that is a tombstoned actor resolves to the tombstone, with `deleted` set.
///   These fields are non-null, so the projection does not ignore this edge. This is an exception to plan.md §3.3,
///   rule 3.
extension Graph {
    /// Gives the comments of a task: the `comments` field.
    ///
    /// - Parameter slot: The slot of the task.
    /// - Returns: The slots of the live comments of the task, in the order of their ULIDs. A tombstoned task, and a
    ///   slot that holds no task, give no comments.
    func comments(ofTaskAt slot: Int) -> [Int] {
        guard isLiveTask(at: slot) else {
            return []
        }
        let comments = allSlots.compactMap { commentSlot -> (slot: Int, comment: CommentNode)? in
            guard let comment = node(at: commentSlot, as: CommentNode.self),
                !comment.fields.isDeleted,
                comment.task == .slot(slot)
            else {
                return nil
            }
            return (commentSlot, comment)
        }
        return comments.sorted { lhs, rhs in lhs.comment.id < rhs.comment.id }.map(\.slot)
    }

    /// Gives the author of a comment: the `author` field. A tombstoned actor is the author too.
    ///
    /// - Parameter slot: The slot of the comment.
    /// - Returns: The actor, live or tombstoned, or `nil` when the graph does not have the actor, or when the slot
    ///   holds no comment.
    func author(ofCommentAt slot: Int) -> ActorNode? {
        actor(at: node(at: slot, as: CommentNode.self)?.author?.resolvedSlot)
    }

    /// Gives the actor of a local ref, for example the envelope actor of a `Change`. A tombstoned actor is found too.
    ///
    /// - Parameter ref: The local ref of the actor.
    /// - Returns: The actor, live or tombstoned, or `nil` when the graph does not have an actor with this ref.
    func actor(for ref: LocalRef) -> ActorNode? {
        actor(at: slot(for: ref))
    }

    /// Gives the actor in a slot that a lookup found, live or tombstoned.
    ///
    /// - Parameter slot: The slot, or `nil` when the lookup found no slot.
    /// - Returns: The actor, or `nil` when there is no slot, or the slot holds no actor.
    private func actor(at slot: Int?) -> ActorNode? {
        slot.flatMap { actorSlot in
            node(at: actorSlot, as: ActorNode.self)
        }
    }
}
