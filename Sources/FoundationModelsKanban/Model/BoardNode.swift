import Foundation

/// The state of the board node. A repo has one board, so the board has no local id (plan.md §3.2).
struct BoardNode: NodeState {
    /// The body and the time values of the board.
    var fields: NodeFields

    /// The local ref of the board.
    var ref: LocalRef {
        .board
    }

    /// The board, as a case of the ``Node`` enum.
    var node: Node {
        .board(self)
    }

    /// Does nothing, because the board has no stored edges.
    ///
    /// - Parameter transform: Not used.
    func updateEdges(using transform: (EdgeTarget) -> EdgeTarget) {}
}
