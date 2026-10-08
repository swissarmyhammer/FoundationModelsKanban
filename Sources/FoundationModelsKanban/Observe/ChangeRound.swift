import Foundation

/// The changes of one loaded board in one operation of the serial gate, and the session of the board after them.
struct BoardChanges: Sendable {
    /// The session of the board after the operation.
    let session: CommitSession

    /// The changes of the live graph of the board that added events, in the order that they happened.
    let changes: [LiveGraphChange]

    /// The graph of the board before the first change.
    let before: Graph

    /// Collects the changes of one board.
    ///
    /// - Parameters:
    ///   - session: The session of the board after the operation.
    ///   - changes: The changes of the live graph of the board that added events, in the order that they happened.
    /// - Returns: The changes, or `nil` when the board did not change.
    init?(of session: CommitSession, changes: [LiveGraphChange]) {
        guard let first = changes.first else {
            return nil
        }
        self.session = session
        self.changes = changes
        before = first.before
    }
}

/// The changes of the loaded boards in one operation of the serial gate: the commits of a call, or the batch of a
/// file watcher (plan.md §6.7). The round makes the `Change` values for the subscribers of a board.
///
/// A board that changed gets one `Change` for each new transaction, in `txn` order. The values before and after come
/// from the live graph before and after each change of the board, so a watcher batch with many transactions gives
/// each of them the values before and after the batch. A board that did not change, but whose tasks depend on a task
/// of a board that changed, gets the `DERIVED` updates of each transaction of that board (plan.md §6.7, derived
/// updates across boards).
///
/// The cross-board dependencies of each view read the other boards: before the operation for the view before, and
/// after the operation for the view after.
struct ChangeRound {
    /// The changes of each board that changed, by the canonical path of its repo directory.
    private let changed: [String: BoardChanges]

    /// The other boards as the reads see them after the operation.
    let after: RelatedBoards

    /// The other boards as the reads see them before the operation.
    private let before: RelatedBoards

    /// Makes the round of one operation.
    ///
    /// - Parameters:
    ///   - changed: The changes of each board that changed, by the canonical path of its repo directory.
    ///   - sessions: The session of each loaded board after the operation, by the canonical path of its repo
    ///     directory.
    ///   - currentPath: The canonical path of the repo directory of the current board.
    ///   - related: The related boards with a resolution of each board key that a dependency of a loaded board names.
    init(
        of changed: [String: BoardChanges],
        amongBoards sessions: [String: CommitSession],
        currentPath: String,
        reading related: RelatedBoards
    ) {
        self.changed = changed
        let place = { (boards: RelatedBoards, path: String, board: BoardSnapshot) in
            path == currentPath ? boards.with(current: board) : boards.with(board: board, atPath: path)
        }
        let after = sessions.reduce(related) { boards, entry in
            place(boards, entry.key, Self.snapshot(of: entry.value, graph: entry.value.live.graph))
        }
        self.after = after
        before = changed.reduce(after) { boards, entry in
            place(boards, entry.key, Self.snapshot(of: entry.value.session, graph: entry.value.before))
        }
    }

    /// Makes the changes of one board for its subscribers.
    ///
    /// - Parameters:
    ///   - session: The session of the board after the operation.
    ///   - path: The canonical path of the repo directory of the board.
    /// - Returns: The changes, in `txn` order. A change can have no update: the filters of each subscriber then
    ///   leave it out.
    func changes(of session: CommitSession, atPath path: String) -> [Change] {
        guard let own = changed[path] else {
            return derivedChanges(of: session)
        }
        let undone = UndoneState(of: session.live.events)
        return own.changes.flatMap { change in
            let builder = ChangeBuilder(
                from: Self.snapshot(of: session, graph: change.before).view(reading: before),
                to: Self.snapshot(of: session, graph: change.after).view(reading: after)
            )
            return change.events.groupedByTransaction().compactMap { txn, events in
                builder.change(of: events, markingUndone: undone.isUndone(txn: txn))
            }
        }
    }

    /// Gives the read view of a board after the operation. The task filter of each subscriber tests its tasks.
    ///
    /// - Parameter session: The session of the board after the operation.
    /// - Returns: The read view.
    func view(of session: CommitSession) -> BoardView {
        view(of: session, reading: after)
    }

    /// Makes the `DERIVED` changes of a board that did not change: one for each transaction of each board that
    /// changed.
    ///
    /// - Parameter session: The session of the board.
    /// - Returns: The changes, in `txn` order.
    private func derivedChanges(of session: CommitSession) -> [Change] {
        let builder = ChangeBuilder(from: view(of: session, reading: before), to: view(of: session))
        let changes = changed.values.flatMap { board in
            let undone = UndoneState(of: board.session.live.events)
            let key = board.session.key.description
            return board.changes.flatMap { change in
                change.events.groupedByTransaction().compactMap { txn, events in
                    builder.derivedChange(of: events, inBoard: key, markingUndone: undone.isUndone(txn: txn))
                }
            }
        }
        return changes.sorted { lhs, rhs in lhs.txn.text < rhs.txn.text }
    }

    /// Gives the read view of the live graph of a board, with the other boards of a time.
    ///
    /// - Parameters:
    ///   - session: The session of the board.
    ///   - boards: The other boards as the reads see them.
    /// - Returns: The read view.
    private func view(of session: CommitSession, reading boards: RelatedBoards) -> BoardView {
        Self.snapshot(of: session, graph: session.live.graph).view(reading: boards)
    }

    /// Gives a board with one of its graphs.
    ///
    /// - Parameters:
    ///   - session: The session of the board.
    ///   - graph: The graph of the board: before or after a change.
    /// - Returns: The board.
    private static func snapshot(of session: CommitSession, graph: Graph) -> BoardSnapshot {
        BoardSnapshot(key: session.key.description, graph: graph, source: session.source)
    }
}
