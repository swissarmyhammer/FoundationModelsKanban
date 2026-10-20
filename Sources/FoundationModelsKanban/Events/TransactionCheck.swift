import ULID

/// The transactions of a board that are not complete in all their log files (divergence.md Q23, S5).
///
/// Each line of a transaction records the local refs of the log files of its board that the transaction writes
/// (``Event/files``). A crash between the appends of two files, or a copy of the board that misses a file, leaves a
/// transaction with no line in a named file. The load and the reload of a live graph do not apply the events of such
/// a transaction: they hold them. A line in a file that the list does not name cannot make the transaction complete.
///
/// A line of an older version can record the count of the files in place of the list. A transaction whose lines hold
/// only counts is complete when its lines are in at least that count of files. When the lines of one transaction hold
/// both forms, the list applies. A line with no field is complete. A held transaction applies when its missing lines
/// arrive, for example when git brings the missing file, at the next load or reload.
struct IncompleteTransactions: Sendable {
    /// The local refs of the missing log files of each transaction that is not complete, sorted by their text, by the
    /// ULID of the transaction. A transaction that the count check holds has an empty list, because a count cannot
    /// tell which file is missing.
    let missingFiles: [ULID: [LocalRef]]

    /// Finds the transactions that are not complete among the events of a board.
    ///
    /// - Parameter events: The events of all log files of the board, in any order.
    init(among events: some Sequence<Event>) {
        missingFiles = Dictionary(grouping: events, by: \.txn).compactMapValues(Self.missingFiles(of:))
    }

    /// Gives the missing log files of one transaction.
    ///
    /// The named files are the union of the lists of all lines of the transaction, so that a line that names more
    /// files than a different line cannot make the transaction complete. With no list, the largest count applies.
    ///
    /// - Parameter transaction: The events of the transaction.
    /// - Returns: The sorted local refs of the named files with no line of the transaction, an empty list when the
    ///   count check finds fewer files than the count, or `nil` when the transaction is complete.
    private static func missingFiles(of transaction: [Event]) -> [LocalRef]? {
        let written = Set(transaction.map(\.patch.node))
        var named = Set<LocalRef>()
        var expected: Int?
        for event in transaction {
            switch event.files {
            case .refs(let refs)?: named.formUnion(refs)
            case .count(let count)?: expected = max(expected ?? count, count)
            case nil: break
            }
        }
        guard named.isEmpty else {
            let missing = named.subtracting(written).sorted()
            return missing.isEmpty ? nil : missing
        }
        guard let expected else {
            return nil
        }
        return written.count >= expected ? nil : []
    }

    /// Tells if the load holds an event: its transaction is not complete.
    ///
    /// - Parameter event: The event.
    /// - Returns: `true` when the transaction of the event is not complete.
    func holds(_ event: Event) -> Bool {
        missingFiles[event.txn] != nil
    }

    /// The detail of the hold warning: each transaction that is not complete, with the local refs of its missing log
    /// files, in the order of the transaction ULIDs. A transaction that the count check holds names no file.
    var holdDetail: String {
        missingFiles.sorted { lhs, rhs in lhs.key < rhs.key }
            .map { txn, refs in "\(txn.ulidString): [\(refs.map(\.description).joined(separator: ", "))]" }
            .joined(separator: "; ")
    }

    /// Records the transactions that are not complete with swift-log, with the missing log files of each one, so that
    /// the skip is not silent. No transaction records nothing.
    func recordHold() {
        guard !missingFiles.isEmpty else {
            return
        }
        Log.kanban.warning(
            "The load does not apply the events of transactions that are not complete in all their log files",
            metadata: ["missingFiles": "\(holdDetail)"]
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
