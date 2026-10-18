import Darwin
import Foundation
import OrderedCollections

/// The state of the files that one scan of the places read, recorded before the scan read the keys (divergence.md
/// §16, Gap 1).
///
/// FSEvents gives an event id when fseventsd reads the change from the kernel, not when the change occurs. Thus the
/// file watcher of a scan place can give a change that occurred before the scan, after the scan ended. The index of
/// the scan compares the files of each change with these marks: a change whose files are the same as the scan saw
/// them changes nothing that the scan read. The marks are recorded before the reads of the scan, so a change during
/// the reads gives files that are not the same as the marks.
struct ScanMarks: Sendable {
    /// The canonical path of each repo of each place, in scan order, by the canonical path of the place.
    private let reposOfPlaces: [String: [String]]

    /// The mark of each repo of the places, by the canonical path of the repo folder.
    private let repos: [String: RepoMark]

    /// Records the marks of the repos that a scan found in its places.
    ///
    /// - Parameter listings: Each place of the scan, with the root directory of each repo that the scan found in it.
    init(listing listings: [(place: URL, repos: [URL])]) {
        reposOfPlaces = Dictionary(
            listings.map { listing in (listing.place.canonicalPath, listing.repos.map(\.canonicalPath)) },
            uniquingKeysWith: { first, _ in first }
        )
        repos = Dictionary(
            listings.flatMap(\.repos).compactMap { repo in
                RepoMark(ofRepoAt: repo).map { mark in (repo.canonicalPath, mark) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Tells if the files of a change are not the same as the scan saw them.
    ///
    /// - A change of a repo, of its board log, or of its commits compares the mark of the repo.
    /// - A change of the place compares the list of repos of the place, and the mark of each repo of the place
    ///   (``changes(inPlaceAt:)``). A place that the scan did not read changed.
    ///
    /// - Parameter change: The change.
    /// - Returns: `true` when a file of the change is not the same as the scan saw it.
    func isChanged(by change: ScanChange) -> Bool {
        switch change {
        case .repo(let repo), .board(inRepo: let repo), .commits(inRepo: let repo):
            isChanged(repoAt: repo)
        case .place(let place):
            changes(inPlaceAt: place).map { changes in !changes.isEmpty } ?? true
        }
    }

    /// Gives the change of each repo of a place whose files are not the same as the scan saw them, for a change of the
    /// place itself or for a batch of lost events. A receiver that compares each file of the place gets the same
    /// changes that the events of the files give (``RepoMark/changes(ofRepoAt:from:to:)``). A new or a removed repo
    /// folder is a repo change.
    ///
    /// - Parameter path: The canonical path of the place.
    /// - Returns: The changes, in the order of the repos of the scan and then the new repos, or `nil` when the scan did
    ///   not read the place.
    func changes(inPlaceAt path: String) -> [ScanChange]? {
        guard let scanned = reposOfPlaces[path] else {
            return nil
        }
        let current = BoardLocator.repos(in: Self.folder(at: path)).map(\.canonicalPath)
        return OrderedSet(scanned + current).flatMap { repo in
            RepoMark.changes(ofRepoAt: repo, from: repos[repo], to: RepoMark(ofRepoAt: Self.folder(at: repo)))
        }
    }

    /// Tells if the files of a repo folder are not the same as the scan saw them. A folder that was no repo at the
    /// scan and is no repo now did not change.
    ///
    /// - Parameter path: The canonical path of the repo folder.
    /// - Returns: `true` when the mark of the repo is not the same.
    private func isChanged(repoAt path: String) -> Bool {
        repos[path] != RepoMark(ofRepoAt: Self.folder(at: path))
    }

    /// Gives the folder at a canonical path.
    ///
    /// - Parameter path: The canonical path.
    /// - Returns: The folder.
    private static func folder(at path: String) -> URL {
        URL(filePath: path, directoryHint: .isDirectory)
    }
}

// MARK: - Repo mark

/// The state of the files of one repo folder that the key and the board of the repo come from: the folder, its
/// `.git` entry, its git config, its branch refs, and its board log.
struct RepoMark: Hashable, Sendable {
    /// The identity of the repo folder.
    let folder: FolderIdentity

    /// The `.git` entry: the directory of a clone, or the file of a worktree.
    let gitEntry: FileStamp

    /// The git config file, or `nil` when it is not there.
    let config: FileStamp?

    /// The directory of the branch refs, or `nil` when it is not there. A first commit adds a branch ref.
    let branchRefs: FileStamp?

    /// The file of the packed refs, or `nil` when it is not there.
    let packedRefs: FileStamp?

    /// `true` when the repo has `.kanban/board.jsonl`.
    let hasBoardLog: Bool

    /// Reads the mark of a repo folder.
    ///
    /// - Parameter directory: The repo folder.
    /// - Returns: The mark, or `nil` when the folder is not there or has no `.git` entry: then it is no repo.
    init?(ofRepoAt directory: URL) {
        let git = directory.appending(path: BoardKey.gitDirectoryName)
        guard let folder = try? FolderIdentity(of: directory), let gitEntry = FileStamp(ofItemAt: git) else {
            return nil
        }
        self.folder = folder
        self.gitEntry = gitEntry
        config = FileStamp(ofItemAt: git.appending(path: GitEntryName.config))
        branchRefs = FileStamp(ofItemAt: git.appending(path: GitEntryName.refs).appending(path: GitEntryName.heads))
        packedRefs = FileStamp(ofItemAt: git.appending(path: GitEntryName.packedRefs))
        hasBoardLog = BoardCopy.hasBoardLog(at: directory)
    }

    /// Gives the changes of a repo folder from an earlier mark to a later mark: the same kinds of change that the
    /// events of its files give (``WatchedPlace/change(at:)``). A receiver that compares each file of a folder, for
    /// example after lost events, finds the changes in this way.
    ///
    /// - A new or a removed repo, a different folder, a different `.git` entry, or a different git config is a repo
    ///   change. A new entry in a `.git` directory is not: the event of that entry gives no change either.
    /// - Different branch refs or different packed refs are a commits change.
    /// - A new or a removed board log is a board change.
    ///
    /// - Parameters:
    ///   - repo: The canonical path of the repo folder.
    ///   - earlier: The earlier mark, or `nil` when the folder was no repo.
    ///   - later: The later mark, or `nil` when the folder is no repo now.
    /// - Returns: A repo change; or a commits change, a board change, both, or none.
    static func changes(ofRepoAt repo: String, from earlier: RepoMark?, to later: RepoMark?) -> [ScanChange] {
        guard earlier != later else {
            return []
        }
        guard let earlier, let later, later.isSameRepo(as: earlier) else {
            return [.repo(repo)]
        }
        let commits = later.hasSameCommits(as: earlier) ? nil : ScanChange.commits(inRepo: repo)
        let board = later.hasBoardLog == earlier.hasBoardLog ? nil : ScanChange.board(inRepo: repo)
        return [commits, board].compactMap { change in change }
    }

    /// Tells if a later mark has the same repo folder, `.git` entry, and git config as an earlier mark, so that the
    /// key of the repo is the same.
    ///
    /// - Parameter earlier: The earlier mark.
    /// - Returns: `true` when the key of the repo is the same.
    private func isSameRepo(as earlier: RepoMark) -> Bool {
        folder == earlier.folder && gitEntry.isSameEntry(as: earlier.gitEntry) && config == earlier.config
    }

    /// Tells if a later mark has the same branch refs and packed refs as an earlier mark.
    ///
    /// - Parameter earlier: The earlier mark.
    /// - Returns: `true` when the refs are the same.
    private func hasSameCommits(as earlier: RepoMark) -> Bool {
        branchRefs == earlier.branchRefs && packedRefs == earlier.packedRefs
    }
}

/// The names of the entries in the `.git` directory of a repo that a scan reads or watches.
enum GitEntryName {
    /// The git config file.
    static let config = "config"

    /// The directory of the refs.
    static let refs = "refs"

    /// The directory of the branch refs in the refs directory.
    static let heads = "heads"

    /// The file of the packed refs.
    static let packedRefs = "packed-refs"
}

// MARK: - File stamp

/// The state of one file or directory: its identity, its size, the time of its last change of content, and the time
/// of its last change of status. A write, a rename onto the path, or a new entry in a directory gives a new stamp.
struct FileStamp: Hashable, Sendable {
    /// The device of the item.
    let device: UInt64

    /// The inode number of the item on its device.
    let inode: UInt64

    /// The size of the item, in bytes.
    let size: Int64

    /// The time of the last change of the content.
    let modified: StampTime

    /// The time of the last change of the status.
    let changed: StampTime

    /// `true` when the item is a directory.
    let isDirectory: Bool

    /// Reads the stamp of an item. A symbolic link gives the stamp of the item that it points to.
    ///
    /// - Parameter item: The item.
    /// - Returns: The stamp, or `nil` when the item is not there or cannot be read.
    init?(ofItemAt item: URL) {
        var status = stat()
        guard stat(item.path, &status) == 0 else {
            return nil
        }
        device = UInt64(bitPattern: Int64(status.st_dev))
        inode = UInt64(status.st_ino)
        size = Int64(status.st_size)
        modified = StampTime(status.st_mtimespec)
        changed = StampTime(status.st_ctimespec)
        isDirectory = status.st_mode & S_IFMT == S_IFDIR
    }

    /// Tells if an earlier stamp is of the same entry. A directory is the same entry while it is the same item: a new
    /// entry in the directory gives new times, and the directory stays the same entry. A file is the same entry while
    /// its stamp is the same.
    ///
    /// - Parameter earlier: The earlier stamp.
    /// - Returns: `true` when the entry is the same.
    func isSameEntry(as earlier: FileStamp) -> Bool {
        guard isDirectory, earlier.isDirectory else {
            return self == earlier
        }
        return device == earlier.device && inode == earlier.inode
    }
}

/// One time of a ``FileStamp``, to the nanosecond.
struct StampTime: Hashable, Sendable {
    /// The seconds since 1970.
    let seconds: Int

    /// The nanoseconds in the second.
    let nanoseconds: Int

    /// Makes the time of a `timespec`.
    ///
    /// - Parameter time: The time.
    init(_ time: timespec) {
        seconds = time.tv_sec
        nanoseconds = time.tv_nsec
    }
}
