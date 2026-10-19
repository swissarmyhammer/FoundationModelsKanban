import Foundation

extension CommitSession {
    /// The names of the board of the session (divergence.md M9): its current key, and the board IDs and the old names
    /// of the board node of the live graph. A call reads them from memory, with no read of a file.
    var names: BoardNames {
        BoardNames(key: key.description, board: live.graph.boardNode)
    }

    /// Gives the copy of the board of the session, as the board refs of a call see the current board.
    ///
    /// - Parameter root: The root directory of the repo of the board, in the path form of its engine.
    /// - Returns: The copy, with the names of the live graph.
    func copy(at root: URL) -> BoardCopy {
        BoardCopy(directory: root, key: key, isEnabled: BoardCopy.hasBoardLog(at: root), names: names)
    }
}
