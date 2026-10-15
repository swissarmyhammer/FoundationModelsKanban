import Foundation

/// The state of the board node. A repo has one board, so the board has no local id (plan.md §3.2).
struct BoardNode: NodeState {
    /// The body and the time values of the board.
    var fields: NodeFields

    /// The name of the board. It is empty when no patch set it.
    var name = ""

    /// The model of the board, for example the chat model `haiku`, or `nil` when no patch set it (divergence.md Q19).
    var model: String?

    /// The local ref of the board.
    var ref: LocalRef {
        .board
    }

    /// The board, as a case of the ``Node`` enum.
    var node: Node {
        .board(self)
    }
}
