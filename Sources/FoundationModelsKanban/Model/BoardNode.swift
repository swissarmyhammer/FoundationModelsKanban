import Foundation
import ULID

/// The state of the board node. A repo has one board, so the board has no local id (plan.md §3.2).
struct BoardNode: NodeState {
    /// The properties that hold the names of the board (divergence.md M9): the board IDs, the git key that the last
    /// write saw, and the old names. An undo never reverses them, because a link to the board uses them.
    static let nameProperties: Set<String> = [PropertyName.boardIDs, PropertyName.gitKey, PropertyName.oldNames]

    /// The body and the time values of the board.
    var fields: NodeFields

    /// The name of the board. It is empty when no patch set it.
    var name = ""

    /// The model of the board, for example the chat model `haiku`, or `nil` when no patch set it (divergence.md Q19).
    var model: String?

    /// The board IDs of the board, in sort order (divergence.md M9). A board has one ID. A merge of two clones that
    /// each made the board gives more than one, and the lowest is the primary ID.
    var ids: [ULID] = []

    /// The git key that the last write of the board saw, or `nil` when no write recorded one (divergence.md M9).
    var gitKey: String?

    /// The old names of the board: each git key that the board had before, in the order of their first record
    /// (divergence.md M9).
    var oldNames: [String] = []

    /// The local ref of the board.
    var ref: LocalRef {
        .board
    }

    /// The board, as a case of the ``Node`` enum.
    var node: Node {
        .board(self)
    }
}

extension BoardNode {
    /// Reads the board node of a repo or of a folder from its board log now. The read takes no lock and makes no file.
    ///
    /// - Parameter directory: The root directory of the board.
    /// - Returns: The board node, or `nil` when the board log has no board node.
    /// - Throws: An ``EventLogError`` when the board log cannot be read.
    static func stored(inRepoAt directory: URL) throws -> BoardNode? {
        try EventLog(repositoryAt: directory).readLog(of: .board).node?.state as? BoardNode
    }
}
