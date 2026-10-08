import Graphiti
import GraphQL
import ULID

// MARK: - Names

extension MutationName {
    /// The mutation that reverses a transaction.
    static let undo = "undo"

    /// The mutation that reverses an undo transaction.
    static let redo = "redo"
}

extension ReverseDirection {
    /// The name of the public mutation of the direction, for the `ops` of the events.
    fileprivate var operation: String {
        switch self {
        case .undo: MutationName.undo
        case .redo: MutationName.redo
        }
    }
}

// MARK: - Arguments

/// The `input` object of `undo` and `redo` (plan.md §4.2, §6.5).
private struct UndoInput: Decodable, Sendable {
    /// The transaction to reverse, or `nil` for the newest target of the session actor.
    let txn: NodeID?

    /// `true` to write the inverse also when a later transaction conflicts with it.
    let force: Bool?
}

/// The arguments of `undo` and `redo`. The `input` argument is optional, because ``UndoInput`` has no required field
/// (plan.md §4.2).
private struct UndoArguments: Decodable, Sendable {
    /// The transaction and the force flag, or `nil` for the newest target and no force.
    let input: UndoInput?
}

// MARK: - Resolvers

extension KanbanResolver {
    /// Resolves `Mutation.undo`: reverses a transaction with inverse patches (plan.md §6.5).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The transaction and the force flag.
    /// - Returns: The change that the undo wrote. The GraphQL field is nullable, so that an error gives `null` for this
    ///   field only, and the other fields of the call keep their data.
    /// - Throws: An error of ``BoardStore/reverse(_:with:at:)``.
    fileprivate func undo(context: KanbanContext, arguments: UndoArguments) async throws -> Change? {
        try await context.store.reverse(.undo, with: arguments.input, at: context.clock())
    }

    /// Resolves `Mutation.redo`: reverses an undo transaction with inverse patches (plan.md §6.5).
    ///
    /// - Parameters:
    ///   - context: The context of the call.
    ///   - arguments: The transaction and the force flag.
    /// - Returns: The change that the redo wrote. The GraphQL field is nullable, so that an error gives `null` for this
    ///   field only, and the other fields of the call keep their data.
    /// - Throws: An error of ``BoardStore/reverse(_:with:at:)``.
    fileprivate func redo(context: KanbanContext, arguments: UndoArguments) async throws -> Change? {
        try await context.store.reverse(.redo, with: arguments.input, at: context.clock())
    }
}

// MARK: - Store

extension BoardStore {
    /// Runs one `undo` or `redo` field: finds the target transaction, checks the conflicts, writes the inverse
    /// patches with `undoes` = the target, and gives the change that the field wrote (plan.md §6.5).
    ///
    /// The field obeys the rules of ``runMutation(named:at:_:)``.
    ///
    /// - Parameters:
    ///   - direction: `undo` or `redo`.
    ///   - input: The transaction and the force flag, or `nil`.
    ///   - time: The time of the change.
    /// - Returns: The change of the patches that the field kept.
    /// - Throws: ``KanbanError/nothingToUndo`` when the log has no target, or the inverse changes nothing.
    ///   ``KanbanError/undoConflict(transaction:laterTransactions:)`` when a later transaction conflicts and the call
    ///   does not force. An error of a graph rule (plan.md §3.3). An ``EventError`` when a patch breaks a rule of the
    ///   log.
    fileprivate func reverse(
        _ direction: ReverseDirection,
        with input: UndoInput?,
        at time: DateTime
    ) throws -> Change? {
        let before = view
        let keptCount = work.kept.count
        let request = ReverseRequest(
            direction: direction,
            txn: input?.txn?.text,
            isForced: input?.force == true,
            actor: sessionActor.ref,
            boardKey: boardKey
        )
        try runMutation(named: direction.operation, at: time) { work in
            try work.reverse(request, at: time)
        }
        let operations = Array(work.operations)
        let events = work.kept.dropFirst(keptCount).map { event in
            event.recording(operations: operations, boards: nil)
        }
        return ChangeBuilder(from: before, to: view).change(of: events, markingUndone: false)
    }
}

/// The values of one `undo` or `redo` field.
private struct ReverseRequest: Sendable {
    /// `undo` or `redo`.
    let direction: ReverseDirection

    /// The `txn` of the input, or `nil` for the newest target of the session actor.
    let txn: String?

    /// `true` to write the inverse also when a later transaction conflicts with it.
    let isForced: Bool

    /// The session actor.
    let actor: LocalRef

    /// The current key of the board, for the read view of the graph rules.
    let boardKey: String
}

// MARK: - Patches

extension WorkingCopy {
    /// Writes the inverse patches of the target transaction of a request (plan.md §6.5).
    ///
    /// The patches of a column tombstone come last, so that the inverse moves its tasks out first. Then the graph
    /// rules of plan.md §3.3 apply: a column tombstone needs an empty column, and the restored edges must make no
    /// `dependsOn` cycle and no rename cycle.
    ///
    /// - Parameters:
    ///   - request: The values of the field.
    ///   - time: The time of the change.
    /// - Throws: ``KanbanError/nothingToUndo`` when the log has no target, or the inverse changes nothing.
    ///   ``KanbanError/undoConflict(transaction:laterTransactions:)`` when a later transaction conflicts and the
    ///   request does not force. An error of a graph rule. An ``EventError`` when a patch breaks a rule of the log.
    fileprivate mutating func reverse(_ request: ReverseRequest, at time: DateTime) throws {
        let log = UndoLog(of: liveEvents)
        let target = try log.target(of: request.direction, named: request.txn, by: request.actor)
        let inverses = try log.inverses(of: target)
        if !request.isForced {
            let graph = graph
            let later = log.conflicts(with: inverses, of: target) { ref in graph.body(of: ref) }
            guard later.isEmpty else {
                throw KanbanError.undoConflict(
                    transaction: target.ulidString,
                    laterTransactions: later.map(\.ulidString)
                )
            }
        }
        let keptCount = kept.count
        let ordered = inverses.filter { inverse in !inverse.makesColumnTombstone }
            + inverses.filter(\.makesColumnTombstone)
        for inverse in ordered {
            if inverse.makesColumnTombstone {
                try checkEmpty(column: inverse.node, inBoard: request.boardKey)
            }
            try apply(inverse.patch(onBody: graph.body(of: inverse.node)), at: time, undoing: target)
        }
        guard kept.count > keptCount else {
            throw KanbanError.nothingToUndo
        }
        try checkCycles(after: inverses, inBoard: request.boardKey)
    }

    /// Checks that the inverse patches make no `dependsOn` cycle and no rename cycle (plan.md §3.3, rule 6, §6.2).
    ///
    /// - Parameters:
    ///   - inverses: The inverse patches that the working copy applied.
    ///   - key: The current key of the board.
    /// - Throws: ``KanbanError/dependencyCycle(path:)`` or ``KanbanError/tagRenameCycle(path:)``.
    private func checkCycles(after inverses: [NodeInverse], inBoard key: String) throws(KanbanError) {
        for inverse in inverses {
            let node = inverse.node
            if node.nodeType == .task, inverse.bodyChange != nil || inverse.parts.add[PropertyName.dependsOn] != nil {
                try checkNoCycle(throughTask: node, inBoard: key)
            }
            if node.nodeType == .tag, inverse.parts.set[PropertyName.renamedTo] != nil {
                try checkNoRenameCycle(fromTagAt: graph.slot(for: node))
            }
        }
    }
}

// MARK: - Schema

extension SchemaBuilder where Resolver == KanbanResolver, Context == KanbanContext {
    /// Adds the `undo` and `redo` mutations and their `input` type (plan.md §4.2, §6.5). Each one gives the `Change`
    /// that it wrote.
    ///
    /// - Returns: This builder, for method chaining.
    func addUndoMutations() -> Self {
        add {
            Input(UndoInput.self) {
                InputField("txn", at: \.txn)
                InputField("force", at: \.force)
            }
        }
        .addMutation {
            Field(MutationName.undo, at: KanbanResolver.undo) { Argument("input", at: \.input) }
            Field(MutationName.redo, at: KanbanResolver.redo) { Argument("input", at: \.input) }
        }
    }
}
