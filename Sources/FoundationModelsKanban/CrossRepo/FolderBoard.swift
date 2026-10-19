import Foundation

/// What git tells about the folder that a path board ref names (plan.md §6.6, board refs; divergence.md §16).
///
/// The host keeps it in memory, so that a later call with the same path ref runs no `git` (divergence.md §16, Gap 1).
/// A change of the folder, of its `.git` entry, or of its git config makes the host forget it
/// (``isExpired(by:ofRepoAt:)``), when the files of the change are not the same as the record saw them
/// (``PathRefRecord/isExpired(by:)``).
enum FolderBoard: Hashable, Sendable {
    /// The board of the folder: the copy at the top folder of its worktree for a folder in a git repo, or the copy of
    /// the board outside git (``BareBoard/root(of:)``, divergence.md M9).
    case board(BoardCopy)

    /// The folder is in a git repo whose key git cannot read, for example because git fails in it. The URL is the top
    /// folder of its worktree.
    case unreadableKey(top: URL)
}

extension FolderBoard {
    /// The copy of the board, or `nil` when the folder has no board with a key.
    var copy: BoardCopy? {
        guard case .board(let copy) = self else {
            return nil
        }
        return copy
    }

    /// Gives the board that the path ref names, as one call sees it.
    ///
    /// - Parameter root: The root directory of the current board.
    /// - Returns: The current board for a folder of the current board, the copy of the board of the folder, or `nil`
    ///   when the key of the repo cannot be read.
    func resolution(currentRoot root: URL) -> BoardResolution? {
        copy.map { copy in BoardResolution(of: copy, currentRoot: root) }
    }

    /// Gives the repo folder whose changes can change the result: the root directory of the board of the folder, or
    /// the top folder of the worktree of a repo whose key cannot be read. A `git init` in the root directory of a
    /// board outside git shows there.
    ///
    /// - Parameter folder: The folder that the path ref names.
    /// - Returns: The repo folder.
    func watchedRepo(ofFolderAt folder: URL) -> URL {
        switch self {
        case .board(let copy): copy.directory
        case .unreadableKey(let top): top
        }
    }

    /// Tells if a change that the file watcher of the parent folder of the watched repo sees makes the result out of
    /// date, the same as the scan index forgets a key (``BoardIndex/isExpired(by:)``).
    ///
    /// - A change of the repo folder, of its `.git` entry, or of its git config can make a new repo, remove a repo, or
    ///   change a key.
    /// - A change of the parent folder itself, or lost events, can be any change.
    /// - New commits can give a key to a repo whose key read failed.
    /// - A changed board log changes no key.
    ///
    /// - Parameters:
    ///   - change: The change.
    ///   - repo: The canonical path of the watched repo folder (``watchedRepo(ofFolderAt:)``).
    /// - Returns: `true` when the next call must read git again.
    func isExpired(by change: ScanChange, ofRepoAt repo: String) -> Bool {
        switch change {
        case .repo(let path): path == repo
        case .place: true
        case .commits(let path): path == repo && hasUnreadableKey
        case .board: false
        }
    }

    /// `true` when the folder is in a git repo whose key git cannot read.
    private var hasUnreadableKey: Bool {
        guard case .unreadableKey = self else {
            return false
        }
        return true
    }
}
