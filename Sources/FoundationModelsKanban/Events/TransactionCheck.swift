import ULID

/// The transactions of a board that are not complete in all their log files (divergence.md Q23, S5).
///
/// Each line of a transaction records the count of the log files of its board that the transaction wrote
/// (``Event/files``). A crash between the appends of two files, or a copy of the board that misses a file, leaves a
/// transaction with lines in fewer files than that count. The load and the reload of a live graph do not apply the
/// events of such a transaction: they hold them. A line with no count is complete. A held transaction applies when
/// its missing lines arrive, for example when git brings the missing file, at the next load or reload.
struct IncompleteTransactions: Sendable {
    /// The ULIDs of the transactions that are not complete.
    let ids: Set<ULID>

    /// Finds the transactions that are not complete among the events of a board.
    ///
    /// - Parameter events: The events of all log files of the board, in any order.
    init(among events: some Sequence<Event>) {
        ids = Set(
            Dictionary(grouping: events, by: \.txn).compactMap { txn, transaction in
                Self.isComplete(transaction) ? nil : txn
            }
        )
    }

    /// Tells if the events of one transaction are in at least as many log files as their file count says. A
    /// transaction whose lines have no count is complete. When two lines have different counts, the largest applies.
    ///
    /// - Parameter transaction: The events of the transaction.
    /// - Returns: `true` when the transaction is complete.
    private static func isComplete(_ transaction: [Event]) -> Bool {
        guard let expected = transaction.compactMap(\.files).max() else {
            return true
        }
        return Set(transaction.map(\.patch.node)).count >= expected
    }

    /// Tells if the load holds an event: its transaction is not complete.
    ///
    /// - Parameter event: The event.
    /// - Returns: `true` when the transaction of the event is not complete.
    func holds(_ event: Event) -> Bool {
        ids.contains(event.txn)
    }

    /// Records the transactions that are not complete with swift-log, so that the skip is not silent. No transaction
    /// records nothing.
    func recordHold() {
        guard !ids.isEmpty else {
            return
        }
        Log.kanban.warning(
            "The load does not apply the events of transactions that are not complete in all their log files",
            metadata: ["transactions": "\(ids.map(\.ulidString).sorted())"]
        )
    }
}

/// The events of some log files of a board, split by the check of their transaction (divergence.md Q23).
struct CheckedEvents: Sendable {
    /// The events whose transaction is complete, in the order of their ids. The graph holds their state.
    let applied: [Event]

    /// The events of the transactions that are not complete, in the order of their ids. The graph does not hold
    /// their state.
    let held: [Event]

    /// No event.
    static let none = CheckedEvents(applied: [], held: [])

    /// Gives these events without the events of some nodes.
    ///
    /// - Parameter refs: The local refs of the nodes.
    /// - Returns: The events of the other nodes.
    func excluding(nodes refs: Set<LocalRef>) -> CheckedEvents {
        CheckedEvents(
            applied: applied.filter { event in !refs.contains(event.patch.node) },
            held: held.filter { event in !refs.contains(event.patch.node) }
        )
    }

    /// Folds again each node whose state a new check changes: a node with an applied event whose transaction is not
    /// complete now, or a node with a held event whose transaction is complete now.
    ///
    /// - Parameter incomplete: The transactions that are not complete after the new check.
    /// - Returns: The new log of each changed node, in no fixed order.
    func refolded(by incomplete: IncompleteTransactions) -> [StagedLog] {
        let changed = Set(applied.filter(incomplete.holds).map(\.patch.node))
            .union(held.filter { event in !incomplete.holds(event) }.map(\.patch.node))
        guard !changed.isEmpty else {
            return []
        }
        let eventsByNode = Dictionary(grouping: applied + held, by: \.patch.node)
        return changed.map { ref in StagedLog(ref: ref, folding: eventsByNode[ref, default: []], by: incomplete) }
    }
}
