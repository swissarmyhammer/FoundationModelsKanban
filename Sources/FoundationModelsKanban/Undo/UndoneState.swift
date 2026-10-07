import Foundation
import ULID

/// The undone state of the transactions of one board, derived from the global event list (plan.md §6.5, §12 item 12).
///
/// A transaction is undone when a later transaction has `undoes` = its `txn`, and that later transaction is not itself
/// undone. The state reads only the `undoes` of each transaction. Thus there is no stack to store, and after a git
/// merge the state holds the transactions of both branches.
///
/// The walk goes from the newest undo or redo transaction to the oldest. Only a later transaction can reverse a
/// transaction, so when the walk comes to a transaction, its state is final: an undo that is not undone makes its
/// target undone. An `undoes` that names a later transaction (a log that a tool did not write) is ignored.
struct UndoneState: Sendable {
    /// The transactions that are undone.
    private let undone: Set<ULID>

    /// Derives the undone state from the events of a board.
    ///
    /// - Parameter events: The events of the board, in any order. All patches of one transaction have the same
    ///   `undoes`.
    init(of events: [Event]) {
        let targets = Dictionary(
            events.compactMap { event in event.undoes.map { target in (event.txn, target) } },
            uniquingKeysWith: { first, _ in first }
        )
        undone = targets.keys.sorted(by: >).reduce(into: []) { undone, txn in
            guard !undone.contains(txn), let target = targets[txn], target < txn else {
                return
            }
            undone.insert(target)
        }
    }

    /// Tells if a transaction is undone.
    ///
    /// - Parameter txn: The transaction ULID.
    /// - Returns: `true` when a later transaction that is not undone reverses the transaction.
    func isUndone(txn: ULID) -> Bool {
        undone.contains(txn)
    }
}
