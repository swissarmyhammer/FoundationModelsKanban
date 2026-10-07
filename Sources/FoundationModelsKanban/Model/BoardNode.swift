import Foundation

/// The state of the board node. A repo has one board, so the board has no local id (plan.md §3.2).
struct BoardNode: NodeState {
    /// The body and the time values of the board.
    ///
    /// The synthesized `Hashable` `==` and `hash(into:)` read it; periphery sees no caller. The projection and the
    /// queries read it later (plan.md §5.3).
    // periphery:ignore
    var fields: NodeFields

    /// The local ref of the board.
    var ref: LocalRef {
        .board
    }

    /// The board, as a case of the ``Node`` enum.
    var node: Node {
        .board(self)
    }
}
