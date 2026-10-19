import Foundation
import OrderedCollections
import ULID

/// A `.kanban/` in a subfolder below the top folder of a git repo (divergence.md M9, where the board is). In a git
/// repo, the board is always at the top folder of the repo, so the calls do not read the subfolder board. Each
/// response of a session that finds one gives a warning that names the subfolder board and tells the user to run
/// `collectBoards`.
struct SubfolderBoard: Hashable, BoardWarning {
    /// The code of the warning, in `extensions.warnings` (plan.md §4.4).
    static let warningCode = "BOARD_IN_SUBFOLDER"

    /// The code of the warning of this board: always ``warningCode``.
    var warningCode: String {
        Self.warningCode
    }

    /// The subfolder that holds the `.kanban/`.
    let folder: URL

    /// The top folder of the repo, whose board the calls use.
    let top: URL

    /// Finds the nearest subfolder board, from the working directory up to the top folder of its repo. The top folder
    /// itself is not a subfolder.
    ///
    /// - Parameters:
    ///   - workingDirectory: The working directory of the session, in the repo.
    ///   - top: The top folder of the worktree of the working directory.
    /// - Returns: The subfolder board, or `nil` when no folder between the working directory and the top folder has a
    ///   `.kanban/`.
    static func nearest(from workingDirectory: URL, below top: URL) -> SubfolderBoard? {
        BareBoard.nearestBoardFolder(from: workingDirectory, below: top).map { folder in
            SubfolderBoard(folder: folder, top: top)
        }
    }

    /// The text of the warning: the subfolder board, the board that the call used, and what the user can do.
    var warningMessage: String {
        let subfolderBoard = EventLog(repositoryAt: folder).directory.path
        let repoBoard = EventLog(repositoryAt: top).directory.path
        return "The folder `\(subfolderBoard)` is a board in a subfolder of the git repo at `\(top.path)`. In a git "
            + "repo the board is at the top folder of the repo, so the call used `\(repoBoard)` and did not read the "
            + "subfolder board. Run collectBoards to combine the subfolder board into the board of the repo."
    }
}

/// Two or more boards outside git with the same board ID that a scan found (divergence.md M9), for example a bare
/// folder and its copy. The calls work: a ref with the board ID names the first board in scan order. The response
/// gives a warning that names each path.
///
/// Clones and worktrees of one git repo share their board log through git, and thus their board IDs. They have a git
/// key, so they are not in this check.
struct SharedBoardID: Hashable, BoardWarning {
    /// The code of the warning, in `extensions.warnings` (plan.md §4.4).
    static let warningCode = "BOARD_ID_SHARED"

    /// The code of the warning of this board ID: always ``warningCode``.
    var warningCode: String {
        Self.warningCode
    }

    /// The smallest number of folders that share one board ID in a warning.
    private static let sharedFolderCount = 2

    /// The board ID that the folders share.
    let id: ULID

    /// The root directory of each board with the ID, in scan order.
    let directories: [URL]

    /// Finds the board IDs that more than one board outside git has.
    ///
    /// - Parameter copies: The copies that a scan found, in scan order.
    /// - Returns: One value for each shared board ID, in the order of the first copy with the ID.
    static func shared(among copies: [BoardCopy]) -> [SharedBoardID] {
        let named = copies.filter(\.key.isBoardID).flatMap { copy in
            copy.names.ids.map { id in (id: id, directory: copy.directory) }
        }
        return OrderedDictionary(grouping: named, by: \.id).compactMap { id, entries in
            let folders = entries.map(\.directory).firstByKey(\.canonicalPath)
            return folders.count < sharedFolderCount ? nil : SharedBoardID(id: id, directories: folders)
        }
    }

    /// The text of the warning: the board ID, each path, and what the user can do.
    var warningMessage: String {
        let paths = directories.map { directory in "`\(directory.path)`" }.joined(separator: ", ")
        return "The boards at \(paths) have the same board ID \(id.ulidString), for example because a folder was "
            + "copied. The call continued, and a ref with this board ID names the first of these boards. Remove the "
            + "copy, or combine the boards into one board with collectBoards."
    }
}
