import Foundation

/// A board ref or a stored link of a run that names a board by an old name (divergence.md M9): a git key that the
/// board log records from before a change of the git key. The ref works: it names the board that has the old name
/// now. The response of the run has one warning for each such name, so that the user can find the links with
/// `checkLinks` and change them to the current name.
struct OldBoardName: Hashable, BoardWarning {
    /// The code of the warning, in `extensions.warnings` (plan.md §4.4).
    static let warningCode = "OLD_BOARD_NAME"

    /// The code of the warning of this name: always ``warningCode``.
    var warningCode: String {
        Self.warningCode
    }

    /// The old name, as the ref holds it, with the host in lowercase.
    let name: String

    /// The current key of the board that has the old name.
    let currentName: String

    /// The text of the warning: the old name, the current name, and what the user can do.
    var warningMessage: String {
        "The board name \(name) is an old name of the board \(currentName). The call read the board that has this "
            + "name now. Run checkLinks to find each link with an old board name, and change it to \(currentName)."
    }
}

extension BoardSnapshot {
    /// The names of the board (divergence.md M9): the current key, and the board IDs and the old names of the board
    /// node of its graph.
    var names: BoardNames {
        graph.boardNames(currentKey: key)
    }

    /// Gives the old name that a board key names this board by.
    ///
    /// - Parameter text: The board key of a board ref or of a stored link.
    /// - Returns: The old name, or `nil` when the key is the current key, a board ID, or no name of this board.
    func oldName(named text: String) -> OldBoardName? {
        guard names.kind(of: text) == .oldName else {
            return nil
        }
        return OldBoardName(name: BoardKey.normalizedText(of: text), currentName: key)
    }
}
