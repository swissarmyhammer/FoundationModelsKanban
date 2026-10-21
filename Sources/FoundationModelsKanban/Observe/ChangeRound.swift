import Foundation

/// The changes of one loaded board in one operation of the serial gate, and the session of the board after them.
struct BoardChanges: Sendable {
    /// The session of the board after the operation.
    let session: CommitSession

    /// The changes of the live graph of the board that added events, in the order that they happened.
    let changes: [LiveGraphChange]

    /// The graph of the board before the first change.
    let before: Graph

    /// The identity of the repo directory of the engine that made the changes. A new repo at the same path has a
    /// different identity, so a session view can tell the changes of the engine that it holds for the path from the
    /// changes of the engine of an old repo at that path (divergence.md §16).
    let identity: FolderIdentity

    /// Collects the changes of one board.
    ///
    /// - Parameters:
    ///   - session: The session of the board after the operation.
    ///   - changes: The changes of the live graph of the board that added events, in the order that they happened.
    ///   - identity: The identity of the repo directory of the engine that made the changes.
    /// - Returns: The changes, or `nil` when the board did not change.
    init?(of session: CommitSession, changes: [LiveGraphChange], madeBy identity: FolderIdentity) {
        guard let first = changes.first else {
            return nil
        }
        self.session = session
        self.changes = changes
        self.identity = identity
        before = first.before
    }
}

/// The changes of the loaded boards in one operation of the serial gate: the commits of a call, or the batch of a
/// file watcher (plan.md §6.7). The round makes the `Change` values for the change log of a board (``ChangeFeed``).
///
/// A board that changed gets one `Change` for each new transaction of its own: the changes of its live graph in the
/// order that they happened, and the transactions of each one in `txn` order. Each change of the live graph is one
/// batch of ``ChangeBuilder/changes(ofBatch:)``: the values before and after come from the live graph before and after
/// that change, so a watcher batch with many transactions gives each of them the values before and after the batch,
/// and each node has at most one update in the batch, as ``ChangeBuilder`` tells. A board that changed gets no
/// `Change` for the transactions of the other boards, also when the same call changed them.
///
/// A board that did not change gets one `Change` for each transaction of all the boards that changed, in `txn` order,
/// all of them one batch of ``ChangeBuilder/changesOfOtherBoards(ofBatch:)`` (plan.md §6.7, updates across boards):
/// the update of a live task whose assignee is an actor that a transaction patched goes to the last transaction of the
/// batch that patched one of its assignee actors, and each other update of its live nodes whose fields changed goes
/// to the last transaction of the batch.
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

    /// Makes the changes of one board for its change log.
    ///
    /// - Parameters:
    ///   - session: The session of the board after the operation.
    ///   - path: The canonical path of the repo directory of the board.
    /// - Returns: The changes of the board's own transactions when it changed, else the changes of the transactions of
    ///   the boards that changed (``changesOfOtherBoards(in:)``). A change can have no update: the change log then
    ///   leaves it out (``ChangeFeed/append(_:readingNodesOf:resolvingIn:)``).
    func changes(of session: CommitSession, atPath path: String) -> [Change] {
        guard let own = changed[path] else {
            return changesOfOtherBoards(in: session)
        }
        let undone = UndoneState(of: session.live.events)
        let key = session.key.description
        return own.changes.flatMap { change in
            let builder = ChangeBuilder(
                from: Self.snapshot(of: session, graph: change.before).view(reading: before),
                to: Self.snapshot(of: session, graph: change.after).view(reading: after)
            )
            let batch = BatchTransaction.grouping(change.events, inBoard: key, markingUndoneBy: undone)
            return builder.changes(ofBatch: batch)
        }
    }

    /// Gives the read view of a board after the operation. The filter of each subscriber tests its nodes.
    ///
    /// - Parameter session: The session of the board after the operation.
    /// - Returns: The read view.
    func view(of session: CommitSession) -> BoardView {
        view(of: session, reading: after)
    }

    /// Makes the changes of a board that did not change: one for each transaction of each board that changed, in `txn`
    /// order, as one batch of ``ChangeBuilder/changesOfOtherBoards(ofBatch:)``. The update of a live task of this board
    /// whose assignee is an actor that a transaction patched is in the change of the last transaction that patched one
    /// of its assignee actors. Each other update of the nodes of this board whose fields changed is in the change of
    /// the last transaction. A change can have no update.
    ///
    /// - Parameter session: The session of the board.
    /// - Returns: The changes, in `txn` order.
    private func changesOfOtherBoards(in session: CommitSession) -> [Change] {
        let builder = ChangeBuilder(from: view(of: session, reading: before), to: view(of: session))
        let batch = changed.values.flatMap { board in
            let undone = UndoneState(of: board.session.live.events)
            let key = board.session.key.description
            return board.changes.flatMap { change in
                BatchTransaction.grouping(change.events, inBoard: key, markingUndoneBy: undone)
            }
        }
        let ordered = batch.sorted { lhs, rhs in lhs.txn.ulidString < rhs.txn.ulidString }
        return builder.changesOfOtherBoards(ofBatch: ordered)
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
