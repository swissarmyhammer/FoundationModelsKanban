import Foundation
import ULID

// MARK: - Inverse rule

/// The facts of one transaction that decide which of its changes have an inverse (plan.md §6.5, the inverse table).
///
/// The log does not record which mutation field made a patch, so the rule reads the `ops` of the transaction:
///
/// - The first patch of a node that a mutation made explicitly gets `delete: true`. A node is explicit when the `ops`
///   have a mutation that makes a node of its type (``makers``).
/// - The first patch of a node that a mutation made as a side effect has no inverse: the node stays. These are the
///   board, the actor of the transaction (the session actor), the default columns of an auto-init, and a node whose
///   type no mutation of the `ops` makes (an unknown tag in `addTask`, a new column in `moveTask`, a new author).
/// - A tag that a `#marker` or a tag name makes live again with `delete: false` keeps its `delete: false`, unless the
///   `ops` have a mutation that makes a tag live explicitly (``tagRestorers``).
///
/// An undo or a redo transaction is not an original transaction: each of its changes is reversed, except the first
/// patch of a node, which only a side effect of the call can make.
struct InverseRule: Sendable {
    /// The public mutations that make a node of each type explicitly.
    static let makers: [PatchNodeType: Set<String>] = [
        .column: [MutationName.addColumn],
        .actor: [MutationName.addActor],
        .tag: [MutationName.addTag, MutationName.renameTag],
        .task: [MutationName.addTask],
        .comment: [MutationName.addComment],
    ]

    /// The public mutations that make a tombstoned tag live explicitly.
    static let tagRestorers: Set<String> = [MutationName.addTag, MutationName.undeleteTag]

    /// The names of the public mutations of the transaction.
    let operations: Set<String>

    /// The actor of the transaction, or `nil` when the transaction has no event.
    let actor: LocalRef?

    /// `true` for an original transaction: one that is not an undo or a redo.
    let isOriginal: Bool

    /// `true` when the transaction made the board node: an auto-init.
    let makesBoard: Bool

    /// Tells if the transaction made a node explicitly, so that its inverse is a tombstone.
    ///
    /// - Parameter ref: The local ref of a node that the transaction made.
    /// - Returns: `true` when a mutation of the transaction made the node explicitly.
    func makesExplicitly(_ ref: LocalRef) -> Bool {
        guard isOriginal, !(Self.makers[ref.nodeType] ?? []).isDisjoint(with: operations) else {
            return false
        }
        switch ref {
        case .actor:
            return ref != actor
        case .column(let slug):
            return !(makesBoard && DefaultColumn.all.contains { column in column.slug == slug })
        case .board, .tag, .task, .comment:
            return true
        }
    }

    /// Tells if the transaction made a tombstoned node live explicitly, so that its inverse makes the tombstone
    /// again.
    ///
    /// - Parameter ref: The local ref of a node that the transaction made live.
    /// - Returns: `false` for a tag that an original transaction made live as a side effect, else `true`.
    func restoresExplicitly(_ ref: LocalRef) -> Bool {
        !isOriginal || ref.nodeType != .tag || !Self.tagRestorers.isDisjoint(with: operations)
    }
}

// MARK: - Body change

/// The change of the body of one node in one transaction: the body just before and just after the transaction.
struct BodyChange: Sendable {
    /// The body just before the transaction.
    let before: String

    /// The body just after the transaction.
    let after: String

    /// The reversed diff of the transaction: the `-` lines and the `+` lines change places (plan.md §5.5, §6.5).
    var reversedDiff: UnifiedDiff {
        UnifiedDiff(from: before, to: after).reversed()
    }

    /// Tells if the reversed diff applies to a body with the rules of plan.md §5.5. A later edit of other lines does
    /// not stop it.
    ///
    /// - Parameter current: The body now.
    /// - Returns: `true` when each hunk of the reversed diff matches the body.
    func applies(to current: String) -> Bool {
        reversedDiff.applies(exactlyTo: current)
    }

    /// Makes the `edit` part of the inverse patch.
    ///
    /// - Parameter current: The body now.
    /// - Returns: The reversed diff when it applies. Else the diff from the body now to the body before the
    ///   transaction, so that a forced undo wins (last write wins).
    func inverseEdit(onBody current: String) -> PatchEdit {
        let reversed = reversedDiff
        let diff = reversed.applies(exactlyTo: current) ? reversed : UnifiedDiff(from: current, to: before)
        return PatchEdit(body: diff.text)
    }
}

// MARK: - Node inverse

/// The inverse of one transaction on one node (plan.md §6.5, inverse patches): the changes that put the node back to
/// its state just before the transaction.
///
/// Each part comes from the state of the node just before and just after the transaction: `set` of the old value, or
/// `unset` when there was no old value; `remove` of each added member and `add` of each removed member; `delete` back
/// to the old tombstone state; and the reversed diff of the body.
struct NodeInverse: Sendable {
    /// The `set`, `unset`, `add`, `remove`, and `delete` parts. The `edit` part depends on the body now, so
    /// ``patch(onBody:)`` adds it.
    let parts: PatchInput

    /// The change of the body, or `nil` when the transaction did not change the body.
    let bodyChange: BodyChange?

    /// `true` when the transaction made the node, so that the inverse makes a tombstone. A later edge to the node is
    /// then a conflict.
    let isNewNode: Bool

    /// The local ref of the node.
    var node: LocalRef {
        parts.node
    }

    /// `true` when the inverse makes a column a tombstone. The graph rule of plan.md §3.3, rule 5, applies to it.
    var makesColumnTombstone: Bool {
        node.nodeType == .column && parts.delete == true
    }

    /// Makes the inverse of the events of one transaction on one node.
    ///
    /// - Parameters:
    ///   - node: The local ref of the node.
    ///   - before: The state of the node just before the transaction, or `nil` when the transaction made the node.
    ///   - after: The state of the node just after the transaction.
    ///   - rule: The facts of the transaction.
    /// - Returns: The inverse, or `nil` when the change has no inverse: a side-effect node, or no change.
    /// - Throws: An ``EventError`` from ``PatchInput``. The values come from the log, so a valid log gives no error.
    init?(
        of node: LocalRef,
        from before: NodeSnapshot?,
        to after: NodeSnapshot,
        following rule: InverseRule
    ) throws(EventError) {
        guard let before else {
            guard rule.makesExplicitly(node) else {
                return nil
            }
            try self.init(parts: PatchInput(node: node, delete: true), bodyChange: nil, isNewNode: true)
            return
        }
        let values = after.properties.valueChanges(
            to: before.properties,
            named: Set(before.properties.values.keys).union(after.properties.values.keys)
        )
        let members = after.properties.memberChanges(
            to: before.properties,
            named: Set(before.properties.members.keys).union(after.properties.members.keys)
        )
        let isRestore = before.isDeleted && !after.isDeleted
        let changesTombstone = before.isDeleted != after.isDeleted && (!isRestore || rule.restoresExplicitly(node))
        let parts = try PatchInput(
            node: node,
            set: values.set,
            unset: values.unset,
            add: members.add,
            remove: members.remove,
            delete: changesTombstone ? before.isDeleted : nil
        )
        let bodyChange = before.body == after.body ? nil : BodyChange(before: before.body, after: after.body)
        guard !parts.isEmpty || bodyChange != nil else {
            return nil
        }
        self.init(parts: parts, bodyChange: bodyChange, isNewNode: false)
    }

    /// Makes an inverse from its parts.
    ///
    /// - Parameters:
    ///   - parts: The `set`, `unset`, `add`, `remove`, and `delete` parts.
    ///   - bodyChange: The change of the body, or `nil`.
    ///   - isNewNode: `true` when the transaction made the node.
    private init(parts: PatchInput, bodyChange: BodyChange?, isNewNode: Bool) {
        self.parts = parts
        self.bodyChange = bodyChange
        self.isNewNode = isNewNode
    }

    /// Makes the inverse patch on the node now.
    ///
    /// - Parameter current: The body of the node now.
    /// - Returns: The patch: the parts, and the `edit` of ``BodyChange/inverseEdit(onBody:)``.
    /// - Throws: An ``EventError`` from ``PatchInput``. The parts are valid, so no error comes.
    func patch(onBody current: String) throws(EventError) -> PatchInput {
        try PatchInput(
            node: node,
            set: parts.set,
            unset: parts.unset,
            add: parts.add,
            remove: parts.remove,
            delete: parts.delete,
            edit: bodyChange?.inverseEdit(onBody: current)
        )
    }

    /// Tells if a later patch conflicts with the inverse (plan.md §6.5, conflict): it changes the same property, the
    /// same set member, or the tombstone state of the node, or it makes an edge to a node that the transaction made.
    /// A later edit of the body is not a conflict here: ``BodyChange/applies(to:)`` decides it.
    ///
    /// - Parameter patch: The later patch.
    /// - Returns: `true` when the patch conflicts.
    func conflicts(with patch: PatchInput) -> Bool {
        guard patch.node == node else {
            return isNewNode && patch.makesEdge(to: node)
        }
        return !patch.propertyNames.isDisjoint(with: parts.propertyNames)
            || !patch.setMembers.isDisjoint(with: parts.setMembers)
            || (patch.delete != nil && parts.delete != nil)
    }
}

// MARK: - Patch parts

/// One member of a set-valued property: the name of the property and the ref.
private struct SetMember: Hashable {
    /// The name of the property, for example `tags`.
    // The synthesized `Hashable` conformance reads this property; periphery sees no reader.
    // periphery:ignore
    let property: String

    /// The member.
    // The synthesized `Hashable` conformance reads this property; periphery sees no reader.
    // periphery:ignore
    let ref: StoredRef
}

extension PatchInput {
    /// `true` when the patch has no `set`, `unset`, `add`, `remove`, `delete`, or `edit` part.
    fileprivate var isEmpty: Bool {
        self.set.isEmpty && unset.isEmpty && add.isEmpty && remove.isEmpty && delete == nil && edit == nil
    }

    /// The names of the single-value properties that the `set` and the `unset` parts change.
    fileprivate var propertyNames: Set<String> {
        Set(set.keys).union(unset)
    }

    /// The members that the `add` and the `remove` parts change.
    fileprivate var setMembers: Set<SetMember> {
        Set(
            [add, remove].joined().flatMap { property, refs in
                refs.map { ref in SetMember(property: property, ref: ref) }
            }
        )
    }

    /// Tells if the patch makes an edge to a node: a `set` of a ref, or an `add` of a member.
    ///
    /// - Parameter target: The local ref of the node.
    /// - Returns: `true` when a ref of the patch names the node.
    fileprivate func makesEdge(to target: LocalRef) -> Bool {
        let ref = StoredRef.local(target)
        return set.values.contains(.ref(ref)) || add.values.contains { members in members.contains(ref) }
    }
}
