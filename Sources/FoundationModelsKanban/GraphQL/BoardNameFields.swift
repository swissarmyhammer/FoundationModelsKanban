import Foundation

extension BoardObject {
    /// The names of the board (divergence.md M9): the current key, each board ID, and each old name.
    private var boardNames: BoardNames {
        BoardNames(key: view.boardKey, board: state)
    }

    /// The primary board ID of the board: the lowest board ID, or `nil` when the board has no ID yet. A board with no
    /// ID gets one on its next write (divergence.md M9).
    var boardId: String? {
        boardNames.primaryID?.ulidString
    }

    /// Each name of the board: the current key first, then each board ID, then each old name (divergence.md M9). A
    /// board ref or a URI with any of these names names this board.
    var names: [String] {
        boardNames.all
    }
}

extension SchemaDescription {
    /// The description of `Board.boardId`.
    static let boardID = """
        The primary board ID of the board: the lowest board ID in its log, as a ULID. A URI with the bare board ID, \
        kanban://<board-id>/<type>/<id>, names this board. Null when the board has no ID yet: the next write of the \
        board gives it one.
        """

    /// The description of `Board.names`.
    static let boardNames = """
        Each name of the board: the current key first, then each board ID, then each old git key of the board. A \
        board ref or a URI with any of these names names this board.
        """
}
