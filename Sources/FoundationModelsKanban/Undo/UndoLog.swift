import Foundation
import OrderedCollections
import ULID

// MARK: - Direction

/// The direction of a reverse call (plan.md §6.5).
enum ReverseDirection: Sendable {
    /// `undo`: with no `txn`, it takes the newest original transaction of the session actor that is not undone.
    case undo

    /// `redo`: with no `txn`, it takes the newest `undo` transaction of the session actor that is not reversed.
    case redo
}

// MARK: - Transactions

extension Sequence<Event> {
    /// Groups the events by transaction.
    ///
    /// - Returns: The events of each transaction, in the order of the transaction ULIDs: the time order of the calls.
    ///   The events of one transaction keep their order.
    func groupedByTransaction() -> [(txn: ULID, events: [Event])] {
        OrderedDictionary(grouping: self, by: \.txn)
            .map { txn, events in (txn: txn, events: events) }
            .sorted { lhs, rhs in lhs.txn < rhs.txn }
    }
}

// MARK: - Undo log

/// The transactions of the log of a board, for `undo` and `redo` (plan.md §6.5, §12 item 12): the target of a call,
/// the inverse of a transaction, and the later transactions that conflict with it.
///
/// The log is the global event list of the board: the committed log. Only the loaded board is searched (plan.md §12,
/// item 27).
struct UndoLog: Sendable {
    /// One transaction of the log.
    private struct Transaction: Sendable {
        /// The transaction ULID.
        let txn: ULID

        /// The events of the transaction, in the order of their ids.
        let events: [Event]

        /// The transaction that this transaction reverses, or `nil` for an original transaction.
        var undoes: ULID? {
            events.lazy.compactMap(\.undoes).first
        }

        /// The actor of the transaction.
        var actor: LocalRef? {
            events.first?.actor
        }
    }

    /// The transactions, in the order of their ULIDs.
    private let transactions: [Transaction]

    /// The undone state of the transactions.
    private let undoneState: UndoneState

    /// Reads the transactions of a board.
    ///
    /// - Parameter events: The global event list of the board.
    init(of events: [Event]) {
        transactions = events.groupedByTransaction().map { txn, events in Transaction(txn: txn, events: events) }
        undoneState = UndoneState(of: events)
    }

    // MARK: Target

    /// Finds the transaction that a reverse call reverses.
    ///
    /// - Parameters:
    ///   - direction: `undo` or `redo`.
    ///   - text: The `txn` of the call, in any case, or `nil` for the newest target of the session actor.
    ///   - actor: The session actor.
    /// - Returns: The transaction ULID.
    /// - Throws: ``KanbanError/nothingToUndo`` when the log has no such transaction.
    func target(of direction: ReverseDirection, named text: String?, by actor: LocalRef) throws(KanbanError) -> ULID {
        guard let text else {
            let candidate = transactions.last { transaction in
                transaction.actor == actor && !undoneState.isUndone(txn: transaction.txn)
                    && isCandidate(transaction, of: direction)
            }
            guard let candidate else {
                throw .nothingToUndo
            }
            return candidate.txn
        }
        // Each ULID text of the log is Crockford base 32 in uppercase, so a txn in lowercase compares in uppercase.
        guard let txn = ULID(ulidString: text.uppercased()), index(of: txn) != nil else {
            throw .nothingToUndo
        }
        return txn
    }

    /// Tells if a transaction is a target of a call with no `txn`: an original transaction for `undo`, and an undo of
    /// an original transaction for `redo`.
    ///
    /// - Parameters:
    ///   - transaction: The transaction.
    ///   - direction: `undo` or `redo`.
    /// - Returns: `true` when the call can take the transaction.
    private func isCandidate(_ transaction: Transaction, of direction: ReverseDirection) -> Bool {
        switch direction {
        case .undo:
            return transaction.undoes == nil
        case .redo:
            guard let target = transaction.undoes else {
                return false
            }
            return index(of: target).map { index in transactions[index].undoes == nil } ?? true
        }
    }

    /// Gives the index of a transaction.
    ///
    /// - Parameter txn: The transaction ULID.
    /// - Returns: The index in ``transactions``, or `nil` when the log has no such transaction.
    private func index(of txn: ULID) -> Int? {
        transactions.firstIndex { transaction in transaction.txn == txn }
    }

    // MARK: Inverse

    /// Makes the inverse of a transaction (plan.md §6.5, inverse patches), from the state of each changed node just
    /// before and just after the transaction.
    ///
    /// - Parameter txn: A transaction of the log.
    /// - Returns: The inverse of each node that the transaction changed and that has an inverse, in the order of the
    ///   first patch of each node.
    /// - Throws: An ``EventError`` from ``NodeInverse``. A valid log gives no error.
    func inverses(of txn: ULID) throws(EventError) -> [NodeInverse] {
        guard let index = index(of: txn) else {
            return []
        }
        let target = transactions[index]
        let earlier = transactions[..<index].flatMap(\.events)
        let nodes = OrderedSet(target.events.map(\.patch.node))
        let before = Dictionary(
            uniqueKeysWithValues: nodes.map { node in (node, events(of: node, in: earlier)) }
        )
        let rule = InverseRule(
            operations: Set(target.events.flatMap(\.ops)),
            actor: target.actor,
            isOriginal: target.undoes == nil,
            makesBoard: before[.board]?.isEmpty == true
        )
        let inverses = try nodes.map { node throws(EventError) -> NodeInverse? in
            let earlierEvents = before[node] ?? []
            let laterEvents = earlierEvents + events(of: node, in: target.events)
            guard let after = NodeSnapshot(folding: laterEvents, for: node) else {
                return nil
            }
            let snapshot = NodeSnapshot(folding: earlierEvents, for: node)
            return try NodeInverse(of: node, from: snapshot, to: after, following: rule)
        }
        return inverses.compactMap(\.self)
    }

    /// Gives the events of one node.
    ///
    /// - Parameters:
    ///   - node: The local ref of the node.
    ///   - events: Some events.
    /// - Returns: The events that change the node.
    private func events(of node: LocalRef, in events: [Event]) -> [Event] {
        events.filter { event in event.patch.node == node }
    }

    // MARK: Conflict

    /// Lists the later transactions that conflict with the inverse of a transaction (plan.md §6.5, conflict).
    ///
    /// A later transaction counts when it is not undone, and when it is not an undo or a redo of a transaction after
    /// the target: such a pair cancels a later change. It conflicts when one of its patches conflicts with an inverse
    /// (``NodeInverse/conflicts(with:)``), or when it edited a body whose reversed diff does not apply to the body
    /// now.
    ///
    /// - Parameters:
    ///   - inverses: The inverse of the transaction.
    ///   - txn: The transaction.
    ///   - currentBody: Gives the body of a node now.
    /// - Returns: The later transactions that conflict, in the order of their ULIDs.
    func conflicts(
        with inverses: [NodeInverse],
        of txn: ULID,
        readingBodiesWith currentBody: (LocalRef) -> String
    ) -> [ULID] {
        let blockedBodies = Set(
            inverses.filter { inverse in
                inverse.bodyChange.map { change in !change.applies(to: currentBody(inverse.node)) } ?? false
            }
            .map(\.node)
        )
        return transactions.filter { transaction in
            transaction.txn > txn && !undoneState.isUndone(txn: transaction.txn)
                && !(transaction.undoes.map { target in target > txn } ?? false)
                && transaction.events.contains { event in
                    blockedBodies.contains(event.patch.node) && event.patch.edit != nil
                        || inverses.contains { inverse in inverse.conflicts(with: event.patch) }
                }
        }
        .map(\.txn)
    }
}
