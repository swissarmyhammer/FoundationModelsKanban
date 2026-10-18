import Foundation

/// What git told about a folder that a path ref named, with the mark of its watched repo (divergence.md §16, Gap 1).
///
/// FSEvents gives an event id when fseventsd reads the change from the kernel, not when the change occurs. Thus the
/// file watcher of the parent folder of the watched repo can give a change that occurred before the record, for
/// example the `mkdir .git` that made the repo. The record compares the files of each change with its mark: a change
/// whose files are the same as the record saw them changes nothing that git told.
struct PathRefRecord: Sendable {
    /// What git told about the folder.
    let board: FolderBoard

    /// The canonical path of the watched repo folder (``FolderBoard/watchedRepo(ofFolderAt:)``).
    let repo: String

    /// The mark of the watched repo folder, or `nil` when the folder was no repo.
    let mark: RepoMark?

    /// Makes the record of a folder.
    ///
    /// The mark of the record must come from before the read of git, so that a change during the read gives files
    /// that are not the same as the mark. The caller reads the mark of the folder before the read of git. When the
    /// watched repo is the folder itself, the record uses that mark. Else the watched repo is the top folder of the
    /// worktree, which is known only after the read of git, so the record reads its mark now.
    ///
    /// - Parameters:
    ///   - board: What git told about the folder.
    ///   - folder: The folder that the path ref named.
    ///   - folderMark: The mark of the folder, read before the read of git.
    init(board: FolderBoard, ofFolderAt folder: URL, folderMark: RepoMark?) {
        let watched = board.watchedRepo(ofFolderAt: folder)
        self.board = board
        repo = watched.canonicalPath
        mark = repo == folder.canonicalPath ? folderMark : RepoMark(ofRepoAt: watched)
    }

    /// Tells if a change that the file watcher of the parent folder of the watched repo sees makes the record out of
    /// date. A change whose watched repo has the same mark as the record changes nothing. Else the rule of
    /// ``FolderBoard/isExpired(by:ofRepoAt:)`` applies.
    ///
    /// A change of the parent folder itself, or a batch of lost events, compares the mark of the watched repo with the
    /// mark of the record, and the rule applies to each change that the compare finds
    /// (``RepoMark/changes(ofRepoAt:from:to:)``). Thus a compare keeps the record for a new board log or for new
    /// commits of a repo whose key git read, the same as the events of those files.
    ///
    /// - Parameter change: The change.
    /// - Returns: `true` when the next call must read git again.
    func isExpired(by change: ScanChange) -> Bool {
        let current = RepoMark(ofRepoAt: URL(filePath: repo, directoryHint: .isDirectory))
        guard current != mark else {
            return false
        }
        guard case .place = change else {
            return board.isExpired(by: change, ofRepoAt: repo)
        }
        return RepoMark.changes(ofRepoAt: repo, from: mark, to: current).contains { repoChange in
            board.isExpired(by: repoChange, ofRepoAt: repo)
        }
    }
}
